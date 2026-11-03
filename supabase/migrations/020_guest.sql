-- =====================================================================
-- 비회원(Supabase 익명 로그인) — SPEC 6-10
-- 1. profiles.is_guest: auth.users.is_anonymous를 트리거로 따라간다 (가입할 때, 구글·카카오를 연결해 정식 계정이 될 때).
--    누구나 읽음(닉네임 옆 "비회원" 표시), 본인도 직접 못 바꿈.
-- 2. 비회원이 못 하는 것: 따봉/비추(build_votes), 노가리방 추천(post_votes), 신고(reports) — 표에 트리거로 막는다.
--    글·댓글·문서 댓글·제안·빌드는 회원과 같다. 경험치·칭호도 똑같이 쌓이고, 연결하면 같은 계정이라 그대로 이어진다.
-- 3. 마지막 접속: profiles.last_seen_at (touch_last_seen(), 화면이 하루 한 번 부름)
-- 4. 오래 안 쓴 비회원 정리: cleanup_guest_accounts() — 남긴 게 없으면 guest_empty_days(30)일, 있으면 guest_idle_days(90)일 동안
--    접속하지 않은 비회원 계정을 지운다 (탈퇴와 같은 규칙). 매일 pg_cron으로 부른다 (SPEC 11-9, 이 파일에는 예약을 넣지 않음).
-- 5. 비회원 기록 지우기: delete_my_account를 그대로 쓰되, 닉네임 없는 비회원의 확인 문구는 "지우기".
-- 019_mypage_wording.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- (먼저 Supabase → Authentication → Sign In / Providers → "Allow anonymous sign-ins"를 켠다)
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 0. 숫자
-- ---------------------------------------------------------------------
insert into public.xp_rules (key, value, note) values
  ('guest_empty_days', 30, '남긴 기록이 없는 비회원 계정을 지우는 미접속 일수'),
  ('guest_idle_days',  90, '기록을 남긴 비회원 계정을 지우는 미접속 일수 (탈퇴와 같은 규칙)');

-- ---------------------------------------------------------------------
-- 1. 비회원 표시 · 마지막 접속
-- ---------------------------------------------------------------------
alter table public.profiles
  add column is_guest     boolean not null default false,
  add column last_seen_at timestamptz not null default now();
comment on column public.profiles.is_guest is '비회원(익명 로그인)인가. auth.users.is_anonymous를 트리거로 따라감';
comment on column public.profiles.last_seen_at is '마지막 접속 (하루 한 번 touch_last_seen). 비회원 정리 기준';

update public.profiles p set is_guest = u.is_anonymous
  from auth.users u where u.id = p.id and u.is_anonymous;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, is_guest) values (new.id, coalesce(new.is_anonymous, false)) on conflict (id) do nothing;
  return new;
end;
$$;

-- 구글·카카오를 연결하면 Supabase가 is_anonymous를 false로 바꾼다 → 정식 계정
create function public.sync_guest_flag()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  update public.profiles set is_guest = coalesce(new.is_anonymous, false)
   where id = new.id and is_guest is distinct from coalesce(new.is_anonymous, false);
  return new;
end;
$$;
create trigger on_auth_user_guest_changed after update of is_anonymous on auth.users
  for each row execute function public.sync_guest_flag();

create function public.is_guest(p_user uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select coalesce((select is_guest from public.profiles where id = p_user), false) $$;

create function public.touch_last_seen()
returns void language sql security definer set search_path = ''
as $$
  update public.profiles set last_seen_at = now()
   where id = (select auth.uid()) and last_seen_at < now() - interval '1 hour';
$$;
revoke execute on function public.touch_last_seen() from public, anon;
grant execute on function public.touch_last_seen() to authenticated;

-- ---------------------------------------------------------------------
-- 2. 비회원이 못 하는 것: 따봉/비추, 노가리방 추천, 신고
-- ---------------------------------------------------------------------
create function public.block_guest_vote()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  who uuid := (to_jsonb(new) ->> case tg_table_name when 'reports' then 'reporter_id' else 'user_id' end)::uuid;
begin
  if public.is_guest(who) then
    raise exception '%', case tg_table_name
      when 'build_votes' then '비회원은 따봉·비추를 누를 수 없어요. 구글·카카오를 연결하면 할 수 있어요.'
      when 'post_votes' then '비회원은 추천할 수 없어요. 구글·카카오를 연결하면 할 수 있어요.'
      else '비회원은 신고할 수 없어요. 구글·카카오를 연결하면 할 수 있어요.'
    end using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger build_votes_no_guest before insert on public.build_votes for each row execute function public.block_guest_vote();
create trigger post_votes_no_guest before insert on public.post_votes for each row execute function public.block_guest_vote();
create trigger reports_no_guest before insert on public.reports for each row execute function public.block_guest_vote();

-- ---------------------------------------------------------------------
-- 3. 비회원 기록 지우기 = 탈퇴 (닉네임 없는 비회원의 확인 문구는 "지우기")
-- ---------------------------------------------------------------------
create or replace function public.delete_my_account(p_confirm text)
returns text language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  prof public.profiles%rowtype;
  kakao text;
  word text;
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  select * into prof from public.profiles where id = me for update;
  if found and prof.role = 'admin' then
    raise exception '운영자 계정은 탈퇴할 수 없어요.' using errcode = '42501';
  end if;
  word := case when coalesce(prof.is_guest, false) then '지우기' else '탈퇴' end;
  if btrim(coalesce(p_confirm, '')) is distinct from coalesce(prof.nickname, word) then
    if prof.nickname is null then
      raise exception '확인 칸에 "%"를 그대로 적어 주세요.', word using errcode = '22023';
    end if;
    raise exception '확인 칸에 내 닉네임을 그대로 적어 주세요.' using errcode = '22023';
  end if;
  select provider_id into kakao from auth.identities where user_id = me and provider = 'kakao' limit 1;
  delete from auth.users where id = me;  -- 프로필과 그 밖의 기록은 on delete 규칙대로 (SPEC 개인정보 메모)
  return kakao;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 오래 안 쓴 비회원 정리 (pg_cron이 매일 부른다, 운영자·정식 계정은 절대 지우지 않음)
-- ---------------------------------------------------------------------
create function public.guest_has_records(p_user uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.posts where author_id = p_user)
      or exists (select 1 from public.post_comments where author_id = p_user)
      or exists (select 1 from public.doc_comments where author_id = p_user)
      or exists (select 1 from public.edit_proposals where proposer_id = p_user)
      or exists (select 1 from public.builds where author_id = p_user);
$$;

create function public.cleanup_guest_accounts()
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  empty_days integer := public.xp_rule('guest_empty_days');
  idle_days integer := public.xp_rule('guest_idle_days');
  n integer;
begin
  with gone as (
    delete from auth.users u
     using public.profiles p
     where p.id = u.id and u.is_anonymous and p.is_guest and p.role <> 'admin'
       and p.last_seen_at < now() - make_interval(days =>
             case when public.guest_has_records(p.id) then idle_days else empty_days end)
    returning u.id
  )
  select count(*) into n from gone;
  return n;
end;
$$;

revoke execute on function public.sync_guest_flag() from public, anon, authenticated;
revoke execute on function public.block_guest_vote() from public, anon, authenticated;
revoke execute on function public.guest_has_records(uuid) from public, anon, authenticated;
revoke execute on function public.cleanup_guest_accounts() from public, anon, authenticated;
-- is_guest(uuid)는 그대로 둔다: 부른 사람 권한으로 도는 검사에서 쓸 수 있게 (비회원 여부는 공개 정보)

commit;
