-- =====================================================================
-- 계정: 닉네임 변경 · 회원 탈퇴 · 카카오 연결 끊기 + DB 문구 정리 (SPEC 6-8)
-- 1. 닉네임 변경: 30일에 한 번 (xp_rules.nickname_change_days). 처음 정하는 것은 변경이 아님.
--    변경 기록(nickname_changes)은 본인·운영자만 본다 (프로필 표는 누구나 읽으므로 시각을 거기 두지 않음)
-- 2. 회원 탈퇴: delete_my_account(닉네임 확인) — 본인 계정만, 운영자는 불가.
--    auth.users를 지우면 지금까지의 on delete 규칙대로 정리된다. 카카오가 연결돼 있었으면 그 카카오 ID를 돌려준다
--    (Edge Function delete-account가 카카오 연결 끊기 API를 부른다)
-- 3. 카카오 연결 끊기 알림: kakao_unlinked(카카오 ID) — Edge Function kakao-unlink만 (service_role)
--    구글도 연결돼 있으면 카카오 연결만 떼고, 카카오만 있으면 탈퇴 처리. 운영자 계정은 지우지 않는다
-- 4. DB 오류 문구: 조사 자리표시 "을(를)" → 받침으로 고르기(public.josa), "다시 제출" → "다시 보내기"
-- 016까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- 0. 이 SQL을 실행하는 역할(SQL Editor = postgres)이 계정을 지울 수 있는지 먼저 확인 — 안 되면 아무것도 바꾸지 않는다
do $$
begin
  if not (has_table_privilege('auth.users', 'DELETE') and has_table_privilege('auth.users', 'UPDATE')
          and has_table_privilege('auth.identities', 'DELETE') and has_table_privilege('auth.identities', 'SELECT')) then
    raise exception '이 역할에는 auth.users·auth.identities를 지울 권한이 없어요. Supabase SQL Editor에서 실행해 주세요.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 4. 조사 (먼저 만든다 — 아래 문구 정리에서 쓴다)
-- ---------------------------------------------------------------------
-- 받침을 보고 조사를 고른다 (화면의 src/lib/josa.js와 같은 규칙). pair: '을/를' '은/는' '이/가' '과/와' '으로/로'
-- 한글이 아니면 "을(를)" 모양으로 둔다
create function public.josa(word text, pair text)
returns text language plpgsql immutable set search_path = ''
as $$
declare
  w text := btrim(coalesce(word, ''));
  code integer;
  jong integer;
  a text := split_part(pair, '/', 1);
  b text := split_part(pair, '/', 2);
begin
  if a = '' or b = '' then
    raise exception '모르는 조사예요: %', pair;
  end if;
  code := case when w = '' then -1 else ascii(right(w, 1)) - 44032 end;  -- UTF-8 DB에서 ascii()는 유니코드 번호
  if code < 0 or code > 11171 then
    return w || case when pair = '으로/로' then '(으)로' else a || '(' || b || ')' end;
  end if;
  jong := code % 28;
  if pair = '으로/로' then
    return w || case when jong = 0 or jong = 8 then '로' else '으로' end;  -- ㄹ 받침은 "로"
  end if;
  return w || case when jong = 0 then b else a end;
end;
$$;

-- 지금 DB에 있는 함수 정의를 읽어 문구만 바꿔 다시 만든다 (긴 함수를 옮겨 쓰지 않으려고).
-- 함수 이름·인자·권한·security definer·search_path는 그대로 남는다 (create or replace).
do $$
declare
  f record;
  def text;
  fixed text;
  pairs text[][] := array[
    ['raise exception ''%은(는) %~%개 골라 주세요.'', what,', 'raise exception ''% %~%개 골라 주세요.'', public.josa(what, ''은/는''),'],
    ['raise exception ''%을(를) 골라 주세요.'', what', 'raise exception ''% 골라 주세요.'', public.josa(what, ''을/를'')'],
    ['제안자가 이미 다시 제출했어요.', '제안자가 이미 다시 보냈어요.'],
    ['다시 제출할 수 있어요.', '다시 보낼 수 있어요.'],
    ['다시 제출할 수 없어요.', '다시 보낼 수 없어요.'],
    ['고쳐서 다시 제출해 주세요.', '고쳐서 다시 보내 주세요.'],
    ['[고쳐서 다시 제출]로', '[고쳐서 다시 보내기]로'],
    ['''작성자가 고쳐서 다시 제출''', '''작성자가 고쳐서 다시 보냄''']
  ];
  i integer;
  n integer := 0;
begin
  for f in
    select p.oid from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
      and (p.prosrc like '%다시 제출%' or p.prosrc like '%을(를)%' or p.prosrc like '%은(는)%')
  loop
    def := pg_get_functiondef(f.oid);
    fixed := def;
    for i in 1 .. array_length(pairs, 1) loop
      fixed := replace(fixed, pairs[i][1], pairs[i][2]);
    end loop;
    if fixed <> def then
      execute fixed;
      n := n + 1;
    end if;
  end loop;
  -- 화면에 나가는 오류 문구에 자리표시·"다시 제출"이 남았으면 멈춘다 (주석은 괜찮음)
  if exists (
    select 1 from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.prosrc ~ 'raise exception ''[^'']*(다시 제출|을\(를\)|은\(는\))'
  ) then
    raise exception '문구 정리가 덜 됐어요 (raise exception에 "다시 제출"이나 조사 자리표시가 남음).';
  end if;
  raise notice '문구를 고친 함수: %개', n;
end $$;

-- ---------------------------------------------------------------------
-- 1. 닉네임 변경: 30일에 한 번
-- ---------------------------------------------------------------------
insert into public.xp_rules (key, value, note) values
  ('nickname_change_days', 30, '닉네임을 바꿀 수 있는 간격 (일). 처음 정하는 것은 세지 않음');

create table public.nickname_changes (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  old_nickname  text not null,
  new_nickname  text not null,
  changed_at    timestamptz not null default now()
);
create index nickname_changes_user_idx on public.nickname_changes (user_id, changed_at desc);
revoke all on public.nickname_changes from anon, authenticated;
grant select on public.nickname_changes to authenticated;
alter table public.nickname_changes enable row level security;
create policy "nickname_changes: 본인·운영자만 읽기" on public.nickname_changes
  for select using (user_id = (select auth.uid()) or public.is_admin());

-- 002의 keep_nickname(비울 수 없음)에 간격 검사와 기록을 더한다
create or replace function public.keep_nickname()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  days integer := public.xp_rule('nickname_change_days');
  last_at timestamptz;
begin
  if old.nickname is not null and new.nickname is null then
    raise exception '닉네임은 비울 수 없어요.' using errcode = '23514';
  end if;
  if old.nickname is null or new.nickname is not distinct from old.nickname then
    return new;  -- 처음 정하기 / 닉네임은 그대로 (대표 칭호만 바꿈 등)
  end if;
  select max(changed_at) into last_at from public.nickname_changes where user_id = old.id;
  if last_at is not null and now() < last_at + make_interval(days => days) then
    raise exception '닉네임은 %일에 한 번 바꿀 수 있어요. %부터 다시 바꿀 수 있어요.', days,
      to_char((last_at + make_interval(days => days)) at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI')
      using errcode = 'P0001';
  end if;
  insert into public.nickname_changes (user_id, old_nickname, new_nickname) values (old.id, old.nickname, new.nickname);
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. 회원 탈퇴
-- ---------------------------------------------------------------------
-- p_confirm: 내 닉네임을 그대로 (닉네임을 아직 안 정했으면 '탈퇴')
-- 돌려주는 값: 연결돼 있던 카카오 ID (없으면 null) — 카카오 쪽 연결 끊기에 쓴다
create function public.delete_my_account(p_confirm text)
returns text language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  prof public.profiles%rowtype;
  kakao text;
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  select * into prof from public.profiles where id = me for update;
  if found and prof.role = 'admin' then
    raise exception '운영자 계정은 탈퇴할 수 없어요.' using errcode = '42501';
  end if;
  if btrim(coalesce(p_confirm, '')) is distinct from coalesce(prof.nickname, '탈퇴') then
    if prof.nickname is null then
      raise exception '확인 칸에 "탈퇴"를 그대로 적어 주세요.' using errcode = '22023';
    end if;
    raise exception '확인 칸에 내 닉네임을 그대로 적어 주세요.' using errcode = '22023';
  end if;
  select provider_id into kakao from auth.identities where user_id = me and provider = 'kakao' limit 1;
  delete from auth.users where id = me;  -- 프로필과 그 밖의 기록은 on delete 규칙대로 (SPEC 개인정보 메모)
  return kakao;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. 카카오 연결 끊기 알림 (Edge Function kakao-unlink → service_role로만)
-- ---------------------------------------------------------------------
-- 돌려주는 값: 'unlinked'(카카오 연결만 뗌) / 'deleted'(탈퇴 처리) / 'operator_kept'(운영자라 그대로) / 'not_found'
create function public.kakao_unlinked(p_kakao_id text)
returns text language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid;
  left_providers jsonb;
begin
  select user_id into uid from auth.identities where provider = 'kakao' and provider_id = p_kakao_id;
  if uid is null then
    return 'not_found';  -- 이미 탈퇴했거나 연결을 뗀 사람 (우리 탈퇴 버튼이 카카오 연결 끊기를 부르면 이 알림이 다시 온다)
  end if;
  if exists (select 1 from auth.identities where user_id = uid and provider <> 'kakao') then
    delete from auth.identities where user_id = uid and provider = 'kakao';
    select coalesce(jsonb_agg(provider order by provider), '[]'::jsonb) into left_providers
    from (select distinct provider from auth.identities where user_id = uid) x;
    update auth.users
    set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
      || jsonb_build_object('providers', left_providers)
      || case when raw_app_meta_data ->> 'provider' = 'kakao'
              then jsonb_build_object('provider', left_providers ->> 0) else '{}'::jsonb end
    where id = uid;
    return 'unlinked';
  end if;
  if exists (select 1 from public.profiles where id = uid and role = 'admin') then
    return 'operator_kept';  -- 운영자 1명 규칙: 지우지 않고 기록만 (Edge Function 로그)
  end if;
  delete from auth.users where id = uid;
  return 'deleted';
end;
$$;

-- ---------------------------------------------------------------------
-- 5. 함수 권한
-- ---------------------------------------------------------------------
revoke execute on function public.keep_nickname() from public, anon, authenticated;
revoke execute on function public.delete_my_account(text) from public, anon;
grant execute on function public.delete_my_account(text) to authenticated;
revoke execute on function public.kakao_unlinked(text) from public, anon, authenticated;
grant execute on function public.kakao_unlinked(text) to service_role;
-- josa는 그대로 둔다: 빌드 검사(check_build_ids·text_array)는 부른 사람 권한으로 돌아서, 막으면 오류 문구 대신 권한 오류가 난다

commit;
