-- =====================================================================
-- 066: 빌드 저장(북마크) (2026-11-22, SPEC 6-82) - 새 표 1개 + 새 함수 3개. 기존 표·함수·권한·데이터는 바꾸지 않는다
--
-- 1. 표 build_bookmarks (user_id, build_id, created_at)
--    - 기본 키 (user_id, build_id) = 같은 빌드를 두 번 저장할 수 없다(중복 방지).
--    - user_id → profiles(id) on delete cascade: 탈퇴(auth.users 삭제 → profiles 삭제)하면 저장도 지워진다.
--    - build_id → builds(id) on delete cascade: 빌드가 완전히 지워지면 그 빌드의 저장도 지워진다.
--    - 빌드나 상대법이 숨겨지면 저장 줄은 남겨 두고 목록(my_saved_builds)에서만 뺀다 → 다시 공개되면 돌아온다.
--    - RLS: 본인 줄만 읽는다. 넣기·지우기는 아래 함수로만 (표에 직접 넣기·고치기·지우기 권한 없음). 비로그인은 아무 권한 없음.
--    - 다른 사람에게 숫자나 목록을 보여 주는 함수·화면은 없다(저장 수는 공개하지 않는다).
-- 2. save_build(빌드 id) → { saved: true, count }
--    - 로그인 + 닉네임(has_nickname, 비회원 계정도 닉네임이 있으면 가능 - 나만 보는 기능이라).
--    - 공개된 빌드(빌드 approved + 상대법 approved)만. 내 빌드도 저장할 수 있다.
--    - 한 사람당 500개까지 (save_build_limit()). 이미 저장한 빌드면 그대로 성공(개수 안 늘어남).
-- 3. unsave_build(빌드 id) → { saved: false, count } - 로그인만 있으면 (숨겨진 빌드의 저장도 지울 수 있게 닉네임·공개 여부를 보지 않는다).
-- 4. my_saved_builds() → { total, hidden, limit, items: [...] } - 내 저장 전부(최대 500개라 한 번에), 최근 저장순.
--    items = [{ id, name, seq, max_skill, up, created_at, author_id, influencer, target, mine, saved_at }] - 공개된 것만.
--    hidden = 저장했지만 지금 볼 수 없는(숨긴 빌드·숨긴 상대법) 개수, total = 저장한 전체 개수.
--
-- 옛 앱(1.1 이하) 영향 없음: 기존 표·함수·정책을 하나도 고치지 않는다(새 것만 더함).
-- 새 알림 종류·새 설정값·pg_cron·Edge Function 변경 없음.
-- 실행 전 supabase/scripts/check_bookmarks_before.sql, 실행 뒤 check_bookmarks_after.sql (두 파일의 "적어 둘 값"이 같아야 한다).
-- 065까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다. 그 뒤에 새 화면을 배포(푸시)한다
-- (먼저 배포해도 화면은 죽지 않는다: 표가 없으면 저장 버튼이 "준비 중" 안내만 한다).
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 065 상태로 돌아간다.
--    저장 기록(build_bookmarks)도 함께 지워진다. 기존 빌드·투표·수정 기록·알림은 066이 바꾸지 않았으므로 되돌릴 것이 없다.
--     begin;
--     drop function if exists public.my_saved_builds();
--     drop function if exists public.unsave_build(bigint);
--     drop function if exists public.save_build(bigint);
--     drop function if exists public.save_build_limit();
--     drop table if exists public.build_bookmarks;
--     commit;
-- =====================================================================

begin;

create table public.build_bookmarks (
  user_id uuid not null references public.profiles (id) on delete cascade,
  build_id bigint not null references public.builds (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, build_id)
);
comment on table public.build_bookmarks is '066 빌드 저장(북마크): 본인만 읽음, 넣기·지우기는 save_build/unsave_build로만. 탈퇴·빌드 삭제 때 함께 지워짐';
-- 빌드를 지울 때(cascade) 빨리 찾게, 내 목록을 최근 저장순으로 읽게
create index build_bookmarks_build_idx on public.build_bookmarks (build_id);
create index build_bookmarks_user_recent_idx on public.build_bookmarks (user_id, created_at desc);

alter table public.build_bookmarks enable row level security;
create policy "build_bookmarks: 본인 읽기" on public.build_bookmarks
  for select to authenticated using (user_id = (select auth.uid()));

revoke all on public.build_bookmarks from public, anon, authenticated;
grant select on public.build_bookmarks to authenticated;

-- 한 사람당 저장 한도 (화면 문구와 맞춘다)
create function public.save_build_limit()
returns integer language sql immutable set search_path = ''
as $$ select 500 $$;

create function public.save_build(p_build bigint)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  n integer;
begin
  if me is null then
    raise exception '로그인이 필요합니다.' using errcode = '42501';
  end if;
  if not public.has_nickname() then
    raise exception '닉네임을 정한 뒤에 저장할 수 있습니다.' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.builds b join public.counters c on c.id = b.counter_id
     where b.id = p_build and b.status = 'approved' and c.status = 'approved'
  ) then
    raise exception '공개된 빌드만 저장할 수 있습니다.' using errcode = '23514';
  end if;
  -- 같은 사람이 동시에 여러 번 눌러도 한도를 넘지 않게 그 사람 줄을 잠근다
  perform 1 from public.profiles where id = me for update;
  if exists (select 1 from public.build_bookmarks where user_id = me and build_id = p_build) then
    select count(*) into n from public.build_bookmarks where user_id = me;
    return jsonb_build_object('saved', true, 'count', n);
  end if;
  select count(*) into n from public.build_bookmarks where user_id = me;
  if n >= public.save_build_limit() then
    raise exception '저장은 %개까지 할 수 있습니다. 안 보는 빌드를 해제해 주세요.', public.save_build_limit() using errcode = '23514';
  end if;
  insert into public.build_bookmarks (user_id, build_id) values (me, p_build);
  return jsonb_build_object('saved', true, 'count', n + 1);
end;
$$;

create function public.unsave_build(p_build bigint)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  n integer;
begin
  if me is null then
    raise exception '로그인이 필요합니다.' using errcode = '42501';
  end if;
  delete from public.build_bookmarks where user_id = me and build_id = p_build;
  select count(*) into n from public.build_bookmarks where user_id = me;
  return jsonb_build_object('saved', false, 'count', n);
end;
$$;

create function public.my_saved_builds()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  all_n integer;
  shown jsonb;
begin
  if me is null then
    raise exception '로그인이 필요합니다.' using errcode = '42501';
  end if;
  select count(*) into all_n from public.build_bookmarks where user_id = me;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id, 'name', b.name, 'seq', b.seq, 'max_skill', b.max_skill, 'up', b.up_count, 'created_at', b.created_at,
           'author_id', b.author_id, 'influencer', a.influencer,
           'target', c.target_champion, 'mine', c.counter_champion, 'saved_at', k.created_at)
         order by k.created_at desc, b.id desc), '[]'::jsonb)
    into shown
    from public.build_bookmarks k
    join public.builds b on b.id = k.build_id
    join public.counters c on c.id = b.counter_id
    left join public.profiles a on a.id = b.author_id
   where k.user_id = me and b.status = 'approved' and c.status = 'approved';
  return jsonb_build_object('total', all_n, 'hidden', all_n - jsonb_array_length(shown),
                            'limit', public.save_build_limit(), 'items', shown);
end;
$$;

revoke execute on function public.save_build_limit() from public, anon;
revoke execute on function public.save_build(bigint) from public, anon;
revoke execute on function public.unsave_build(bigint) from public, anon;
revoke execute on function public.my_saved_builds() from public, anon;
grant execute on function public.save_build_limit() to authenticated;
grant execute on function public.save_build(bigint) to authenticated;
grant execute on function public.unsave_build(bigint) to authenticated;
grant execute on function public.my_saved_builds() to authenticated;

commit;
