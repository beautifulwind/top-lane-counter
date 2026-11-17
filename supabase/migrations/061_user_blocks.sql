-- =====================================================================
-- 061: 사용자 차단 (2026-11-17, SPEC 6-67) - App Store 심사 가이드 1.2(UGC 앱의 악성 사용자 차단) 대응. 추가만 하는 변경
--
-- 1. 새 표 user_blocks (blocker_id, blocked_id, created_at). 기본 키 (blocker_id, blocked_id), 자기 자신 차단은 검사(CHECK)로 막는다.
--    두 칸 모두 profiles(id)를 참조하고 on delete cascade -> 둘 중 누가 탈퇴해도 차단 줄이 함께 지워진다
--    (delete_my_account -> withdraw_account_unchecked가 auth.users를 지우면 profiles가 지워지고 그 cascade로. 함수 변경 없음).
--    RLS: 로그인한 본인이 blocker인 줄만 읽기·추가·지우기. 고치기(update) 권한 없음, 비로그인(anon) 권한 없음.
--    넣기 전 트리거: 운영자 계정은 차단 불가, 한 사람 1000명까지, 차단 시각은 DB 시각.
--    넣은 뒤 트리거: 내가 팔로우하던 장인을 차단하면 그 팔로우를 끊는다(새 빌드 알림이 오지 않게). 상대가 나를 팔로우하던 것은 그대로.
-- 2. my_blocked_ids(): 내가 차단한 사람 id 목록 (비로그인은 빈 목록).
-- 3. board_page(커뮤니티 글 목록·검색): 내가 차단한 사람의 글을 빼고 센다.
-- 4. notify_new_comment: 받는 사람이 차단한 사람의 댓글·답글로는 알림을 만들지 않고, 합친 알림의 "N개"에서도 뺀다.
-- 5. new_follower_digest: 장인이 차단한 팔로워는 "오늘 새 팔로워 N명"에 세지 않는다.
-- 차단된 사람에게는 아무 알림도 가지 않는다. 운영진의 신고·관리 화면은 차단과 상관없이 그대로 다 보인다.
-- 글 댓글·문서 댓글·빌드·장인 목록 등 표를 직접 읽는 화면은 화면이 내 차단 목록(user_blocks)으로 거른다.
--
-- 새 알림 종류·새 설정값·새 pg_cron 없음, Edge Function 재배포 없음.
-- 실행 전 supabase/scripts/check_blocks_before.sql, 실행 뒤 check_blocks_after.sql.
-- 060까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다. 지금 화면(차단 전)과도 호환된다 - 순서는 상관없지만 SQL을 먼저 실행하는 것을 권한다.
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 060 상태로 돌아간다.
--    되돌릴 수 없는 것: 차단 목록은 지워진다. 차단할 때 끊긴 팔로우는 되살아나지 않는다. 함수 내용은 060과 같다.
--    (화면은 차단 표가 없으면 차단 기능만 "준비 중"으로 보이고 나머지는 그대로 동작한다)
--     begin;
--     -- 1) 함수를 060 내용으로 (board_page가 my_blocked_ids를 부르므로 먼저 되돌린다)
--     CREATE OR REPLACE FUNCTION public.board_page(p_q text DEFAULT NULL::text, p_page integer DEFAULT 1, p_size integer DEFAULT 20)
--      RETURNS jsonb
--      LANGUAGE plpgsql
--      STABLE
--      SET search_path TO ''
--     AS $function$
--     declare
--       q text := nullif(btrim(coalesce(p_q, '')), '');
--       pat text;
--       sz integer := least(greatest(coalesce(p_size, 20), 1), 50);
--       pg integer := greatest(coalesce(p_page, 1), 1);
--       total integer;
--       items jsonb;
--       pinned jsonb := '[]'::jsonb;
--     begin
--       if q is not null then
--         pat := '%' || replace(replace(replace(left(q, 50), '\', '\\'), '%', '\%'), '_', '\_') || '%';
--       end if;
--       select count(*) into total from public.posts p
--       where p.deleted_at is null and (pat is null or p.title ilike pat or p.body ilike pat);
--
--       select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc, x.id desc), '[]'::jsonb) into items
--       from (
--         select p.id, p.title, p.status, false as deleted, p.comment_count, p.up_count,
--                p.created_at, p.edited_at, p.is_notice,
--                (select count(*) from public.board_attachments a where a.post_id = p.id) as media_count,
--                (select jsonb_build_object('nickname', a.nickname, 'role', a.role, 'level', a.level, 'main_title', a.main_title, 'influencer', a.influencer, 'nickname_state', a.nickname_state)
--                 from public.profiles a where a.id = p.author_id) as author
--         from public.posts p
--         where p.deleted_at is null and (pat is null or p.title ilike pat or p.body ilike pat)
--         order by p.created_at desc, p.id desc
--         limit sz offset (pg - 1) * sz
--       ) x;
--
--       if pg = 1 and q is null then
--         select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc, x.id desc), '[]'::jsonb) into pinned
--         from (
--           select p.id, p.title, p.status, false as deleted, p.comment_count, p.up_count,
--                  p.created_at, p.edited_at, p.is_notice,
--                  (select count(*) from public.board_attachments a where a.post_id = p.id) as media_count,
--                  (select jsonb_build_object('nickname', a.nickname, 'role', a.role, 'level', a.level, 'main_title', a.main_title, 'influencer', a.influencer, 'nickname_state', a.nickname_state)
--                   from public.profiles a where a.id = p.author_id) as author
--           from public.posts p
--           where p.deleted_at is null and p.is_notice
--           order by p.created_at desc, p.id desc
--           limit 3
--         ) x;
--       end if;
--       return jsonb_build_object('total', total, 'size', sz, 'rows', items, 'notices', pinned);
--     end;
--     $function$;
--     CREATE OR REPLACE FUNCTION public.notify_new_comment(p_kind text, p_target bigint, p_owner uuid, p_parent_author uuid, p_is_reply boolean)
--      RETURNS void
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       me uuid := (select auth.uid());
--       lq text := chr(12300);  -- 낫표 여는 것 (SQL Editor에 붙여도 깨지지 않게 코드 번호로)
--       rq text := chr(12301);
--       what text;      -- 낫표로 감싼 글 제목 (문서는 없음 - 화면이 매치업 이름을 붙인다)
--       n public.notifications%rowtype;
--       cnt integer;
--     begin
--       if p_kind = 'post' then
--         select lq || public.post_snippet(title) || rq into what from public.posts where id = p_target;
--       end if;
--
--       -- 답글 -> 부모 댓글 작성자
--       if p_is_reply and p_parent_author is not null and p_parent_author is distinct from me then
--         select * into n from public.notifications
--          where user_id = p_parent_author and kind = 'comment_reply' and read_at is null
--            and ((p_kind = 'post' and post_id = p_target)
--                 or (p_kind = 'doc' and counter_id = p_target and post_id is null and build_id is null))
--          order by created_at limit 1 for update;
--         if found then
--           if p_kind = 'post' then
--             select count(*) into cnt from public.post_comments r join public.post_comments pc on pc.id = r.parent_id
--              where r.post_id = p_target and pc.author_id = p_parent_author and r.author_id is distinct from p_parent_author
--                and r.status = 'visible' and r.deleted_at is null and r.created_at >= n.created_at;
--           else
--             select count(*) into cnt from public.doc_comments r join public.doc_comments pc on pc.id = r.parent_id
--              where r.counter_id = p_target and pc.author_id = p_parent_author and r.author_id is distinct from p_parent_author
--                and r.status = 'visible' and r.deleted_at is null and r.created_at >= n.created_at;
--           end if;
--           update public.notifications
--              set message = case when p_kind = 'doc' then format('상대법 문서에 쓴 내 댓글에 새 답글 %s개가 달렸습니다.', greatest(cnt, 2))
--                                 else format('%s에 쓴 내 댓글에 새 답글 %s개가 달렸습니다.', what, greatest(cnt, 2)) end
--            where id = n.id;
--         else
--           insert into public.notifications (user_id, kind, message, post_id, counter_id)
--           values (p_parent_author, 'comment_reply',
--                   case when p_kind = 'doc' then '상대법 문서에 쓴 내 댓글에 새 답글이 달렸습니다.'
--                        else format('%s에 쓴 내 댓글에 새 답글이 달렸습니다.', what) end,
--                   case when p_kind = 'post' then p_target end, case when p_kind = 'doc' then p_target end);
--         end if;
--       end if;
--
--       -- 글 주인, 문서는 상대법을 처음 제안한 분 (답글의 부모 작성자와 같은 사람이면 위 알림 하나로)
--       if p_owner is null or p_owner = me or (p_is_reply and p_owner is not distinct from p_parent_author) then
--         return;
--       end if;
--       if p_kind = 'post' then
--         select * into n from public.notifications
--          where user_id = p_owner and kind = 'post_comment' and post_id = p_target and read_at is null
--          order by created_at limit 1 for update;
--         if found then
--           select count(*) into cnt from public.post_comments
--            where post_id = p_target and author_id is distinct from p_owner and status = 'visible' and deleted_at is null and created_at >= n.created_at;
--           update public.notifications set message = format('내 글 %s에 새 댓글 %s개가 달렸습니다.', what, greatest(cnt, 2)) where id = n.id;
--         else
--           insert into public.notifications (user_id, kind, message, post_id)
--           values (p_owner, 'post_comment', format('내 글 %s에 새 댓글이 달렸습니다.', what), p_target);
--         end if;
--       else
--         select * into n from public.notifications
--          where user_id = p_owner and kind = 'doc_comment' and counter_id = p_target and read_at is null
--          order by created_at limit 1 for update;
--         if found then
--           select count(*) into cnt from public.doc_comments
--            where counter_id = p_target and author_id is distinct from p_owner and status = 'visible' and deleted_at is null and created_at >= n.created_at;
--           update public.notifications set message = format('내가 제안한 상대법 문서에 새 댓글 %s개가 달렸습니다.', greatest(cnt, 2)) where id = n.id;
--         else
--           insert into public.notifications (user_id, kind, message, counter_id)
--           values (p_owner, 'doc_comment', '내가 제안한 상대법 문서에 새 댓글이 달렸습니다.', p_target);
--         end if;
--       end if;
--     end;
--     $function$;
--     CREATE OR REPLACE FUNCTION public.new_follower_digest()
--      RETURNS jsonb
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       win constant interval := interval '25 hours';
--       keep constant interval := interval '30 days';
--       n_notified integer := 0;
--       n_counted integer := 0;
--       n_pruned integer := 0;
--     begin
--       -- 두 번 겹쳐 돌지 않게
--       if not pg_try_advisory_xact_lock(hashtext('new_follower_digest')) then
--         return jsonb_build_object('notified', 0, 'counted', 0, 'pruned', 0, 'skipped', true);
--       end if;
--       delete from public.new_follower_counted where counted_at < now() - keep;
--       get diagnostics n_pruned = row_count;
--       with fresh as (
--         -- 지금도 팔로우 중 + 지난 25시간 안에 팔로우 + 받는 사람이 지금 인증된 장인
--         select f.influencer_id, f.follower_id
--           from public.influencer_follows f
--           join public.profiles a on a.id = f.influencer_id and a.influencer is not null
--          where f.created_at > now() - win
--            and f.follower_id <> f.influencer_id
--       ), mark as (
--         -- 이미 센 짝은 on conflict로 빠진다 = 새로 센 사람만 남는다
--         insert into public.new_follower_counted (influencer_id, follower_id)
--         select influencer_id, follower_id from fresh
--         on conflict (influencer_id, follower_id) do nothing
--         returning influencer_id
--       ), ins as (
--         insert into public.notifications (user_id, kind, message)
--         select m.influencer_id, 'new_followers', format('오늘 새 팔로워 %s명이 생겼습니다.', count(*))
--           from mark m
--          group by m.influencer_id
--         returning 1
--       )
--       select (select count(*) from mark), (select count(*) from ins) into n_counted, n_notified;
--       return jsonb_build_object('notified', n_notified, 'counted', n_counted, 'pruned', n_pruned);
--     end;
--     $function$;
--     -- 2) 차단 표(트리거·정책·인덱스 함께)와 함수
--     drop table public.user_blocks;
--     drop function public.user_blocks_check();
--     drop function public.user_blocks_unfollow();
--     drop function public.my_blocked_ids();
--     commit;
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 0. 안전장치: 060까지 실행한 DB에서 한 번만
-- ---------------------------------------------------------------------
do $guard$
begin
  if to_regclass('public.user_blocks') is not null then
    raise exception '061을 이미 실행했습니다 (user_blocks 표가 있음). 다시 실행하지 마세요. 아무것도 바뀌지 않았습니다.' using errcode = 'P0001';
  end if;
  if to_regclass('public.build_comments') is not null
     or to_regprocedure('public.notify_new_comment(text, bigint, uuid, uuid, boolean)') is null
     or to_regprocedure('public.new_follower_digest()') is null then
    raise exception '060까지 실행한 DB에서만 실행합니다. 아무것도 바뀌지 않았습니다.' using errcode = 'P0001';
  end if;
end;
$guard$;

-- ---------------------------------------------------------------------
-- 1. 차단 표 user_blocks: 차단한 사람 -> 차단된 사람. 둘 중 누가 탈퇴해도(프로필이 지워지면) 함께 지워진다
-- ---------------------------------------------------------------------
create table public.user_blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint user_blocks_not_self check (blocker_id <> blocked_id)
);
create index user_blocks_blocked_idx on public.user_blocks (blocked_id);
comment on table public.user_blocks is
  '사용자 차단 (061, SPEC 6-67). 차단한 사람 화면에서만 차단된 사람의 글·댓글·빌드가 숨겨지고 그 사람이 일으킨 알림이 오지 않는다. 차단된 사람에게는 아무것도 알리지 않는다. 본인 것만 읽기·추가·지우기(고치기 없음)';

alter table public.user_blocks enable row level security;
revoke all on public.user_blocks from anon, authenticated;
grant select, insert, delete on public.user_blocks to authenticated;
create policy "user_blocks: 본인 것 읽기" on public.user_blocks
  for select to authenticated using (blocker_id = (select auth.uid()));
create policy "user_blocks: 본인이 차단" on public.user_blocks
  for insert to authenticated with check (blocker_id = (select auth.uid()));
create policy "user_blocks: 본인이 해제" on public.user_blocks
  for delete to authenticated using (blocker_id = (select auth.uid()));

-- 넣기 전 검사: 운영자 계정은 차단할 수 없다(공지 등 공식 안내가 사라지지 않게), 한 사람이 1000명까지. 차단 시각은 DB 시각으로
create function public.user_blocks_check()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if exists (select 1 from public.profiles where id = new.blocked_id and role = 'admin') then
    raise exception '운영자 계정은 차단할 수 없습니다.' using errcode = '42501';
  end if;
  if (select count(*) from public.user_blocks where blocker_id = new.blocker_id) >= 1000 then
    raise exception '차단은 1000명까지 할 수 있습니다. 설정에서 차단을 해제한 뒤 다시 시도해 주세요.' using errcode = '54000';
  end if;
  new.created_at := now();
  return new;
end;
$function$;
revoke execute on function public.user_blocks_check() from public, anon, authenticated;
create trigger user_blocks_check before insert on public.user_blocks
  for each row execute function public.user_blocks_check();

-- 넣은 뒤: 내가 팔로우하던 장인을 차단하면 팔로우를 끊는다 (새 빌드 알림이 오지 않게).
-- 상대가 나를 팔로우하던 것은 그대로 둔다 (끊으면 차단 사실이 드러난다) - 새 팔로워 수·팔로워 목록에서만 뺀다
create function public.user_blocks_unfollow()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  delete from public.influencer_follows where follower_id = new.blocker_id and influencer_id = new.blocked_id;
  return null;
end;
$function$;
revoke execute on function public.user_blocks_unfollow() from public, anon, authenticated;
create trigger user_blocks_unfollow after insert on public.user_blocks
  for each row execute function public.user_blocks_unfollow();

-- 내가 차단한 사람 id 목록 (로그인 안 했으면 빈 목록). 다른 함수가 걸러 낼 때 쓴다
create function public.my_blocked_ids()
 returns uuid[]
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select coalesce(array_agg(blocked_id), '{}'::uuid[]) from public.user_blocks where blocker_id = (select auth.uid());
$function$;
revoke execute on function public.my_blocked_ids() from public, anon, authenticated;
grant execute on function public.my_blocked_ids() to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. 커뮤니티 글 목록·검색: 내가 차단한 사람의 글은 빼고 센다 (나머지는 060 그대로)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.board_page(p_q text DEFAULT NULL::text, p_page integer DEFAULT 1, p_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  q text := nullif(btrim(coalesce(p_q, '')), '');
  pat text;
  sz integer := least(greatest(coalesce(p_size, 20), 1), 50);
  pg integer := greatest(coalesce(p_page, 1), 1);
  total integer;
  items jsonb;
  pinned jsonb := '[]'::jsonb;
  blk uuid[] := public.my_blocked_ids();  -- 061: 내가 차단한 사람 (작성자가 빈 글은 그대로)
begin
  if q is not null then
    pat := '%' || replace(replace(replace(left(q, 50), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  end if;
  select count(*) into total from public.posts p
  where p.deleted_at is null and (pat is null or p.title ilike pat or p.body ilike pat)
    and not coalesce(p.author_id = any(blk), false);

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc, x.id desc), '[]'::jsonb) into items
  from (
    select p.id, p.title, p.status, false as deleted, p.comment_count, p.up_count,
           p.created_at, p.edited_at, p.is_notice,
           (select count(*) from public.board_attachments a where a.post_id = p.id) as media_count,
           (select jsonb_build_object('nickname', a.nickname, 'role', a.role, 'level', a.level, 'main_title', a.main_title, 'influencer', a.influencer, 'nickname_state', a.nickname_state)
            from public.profiles a where a.id = p.author_id) as author
    from public.posts p
    where p.deleted_at is null and (pat is null or p.title ilike pat or p.body ilike pat)
      and not coalesce(p.author_id = any(blk), false)
    order by p.created_at desc, p.id desc
    limit sz offset (pg - 1) * sz
  ) x;

  if pg = 1 and q is null then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc, x.id desc), '[]'::jsonb) into pinned
    from (
      select p.id, p.title, p.status, false as deleted, p.comment_count, p.up_count,
             p.created_at, p.edited_at, p.is_notice,
             (select count(*) from public.board_attachments a where a.post_id = p.id) as media_count,
             (select jsonb_build_object('nickname', a.nickname, 'role', a.role, 'level', a.level, 'main_title', a.main_title, 'influencer', a.influencer, 'nickname_state', a.nickname_state)
              from public.profiles a where a.id = p.author_id) as author
      from public.posts p
      where p.deleted_at is null and p.is_notice
        and not coalesce(p.author_id = any(blk), false)
      order by p.created_at desc, p.id desc
      limit 3
    ) x;
  end if;
  return jsonb_build_object('total', total, 'size', sz, 'rows', items, 'notices', pinned);
end;
$function$;

-- ---------------------------------------------------------------------
-- 3. 댓글·답글 알림: 받는 사람이 차단한 사람의 댓글·답글로는 알림을 만들지 않고, 합친 알림의 "N개"에서도 뺀다
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_new_comment(p_kind text, p_target bigint, p_owner uuid, p_parent_author uuid, p_is_reply boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  me uuid := (select auth.uid());
  lq text := chr(12300);  -- 낫표 여는 것 (SQL Editor에 붙여도 깨지지 않게 코드 번호로)
  rq text := chr(12301);
  what text;      -- 낫표로 감싼 글 제목 (문서는 없음 - 화면이 매치업 이름을 붙인다)
  n public.notifications%rowtype;
  cnt integer;
begin
  if p_kind = 'post' then
    select lq || public.post_snippet(title) || rq into what from public.posts where id = p_target;
  end if;

  -- 답글 -> 부모 댓글 작성자 (061: 그분이 나를 차단했으면 알리지 않는다)
  if p_is_reply and p_parent_author is not null and p_parent_author is distinct from me
     and not exists (select 1 from public.user_blocks ub where ub.blocker_id = p_parent_author and ub.blocked_id = me) then
    select * into n from public.notifications
     where user_id = p_parent_author and kind = 'comment_reply' and read_at is null
       and ((p_kind = 'post' and post_id = p_target)
            or (p_kind = 'doc' and counter_id = p_target and post_id is null and build_id is null))
     order by created_at limit 1 for update;
    if found then
      if p_kind = 'post' then
        select count(*) into cnt from public.post_comments r join public.post_comments pc on pc.id = r.parent_id
         where r.post_id = p_target and pc.author_id = p_parent_author and r.author_id is distinct from p_parent_author
           and r.status = 'visible' and r.deleted_at is null and r.created_at >= n.created_at
           and not exists (select 1 from public.user_blocks ub where ub.blocker_id = p_parent_author and ub.blocked_id = r.author_id);
      else
        select count(*) into cnt from public.doc_comments r join public.doc_comments pc on pc.id = r.parent_id
         where r.counter_id = p_target and pc.author_id = p_parent_author and r.author_id is distinct from p_parent_author
           and r.status = 'visible' and r.deleted_at is null and r.created_at >= n.created_at
           and not exists (select 1 from public.user_blocks ub where ub.blocker_id = p_parent_author and ub.blocked_id = r.author_id);
      end if;
      update public.notifications
         set message = case when p_kind = 'doc' then format('상대법 문서에 쓴 내 댓글에 새 답글 %s개가 달렸습니다.', greatest(cnt, 2))
                            else format('%s에 쓴 내 댓글에 새 답글 %s개가 달렸습니다.', what, greatest(cnt, 2)) end
       where id = n.id;
    else
      insert into public.notifications (user_id, kind, message, post_id, counter_id)
      values (p_parent_author, 'comment_reply',
              case when p_kind = 'doc' then '상대법 문서에 쓴 내 댓글에 새 답글이 달렸습니다.'
                   else format('%s에 쓴 내 댓글에 새 답글이 달렸습니다.', what) end,
              case when p_kind = 'post' then p_target end, case when p_kind = 'doc' then p_target end);
    end if;
  end if;

  -- 글 주인, 문서는 상대법을 처음 제안한 분 (답글의 부모 작성자와 같은 사람이면 위 알림 하나로. 061: 그분이 나를 차단했으면 알리지 않는다)
  if p_owner is null or p_owner = me or (p_is_reply and p_owner is not distinct from p_parent_author)
     or exists (select 1 from public.user_blocks ub where ub.blocker_id = p_owner and ub.blocked_id = me) then
    return;
  end if;
  if p_kind = 'post' then
    select * into n from public.notifications
     where user_id = p_owner and kind = 'post_comment' and post_id = p_target and read_at is null
     order by created_at limit 1 for update;
    if found then
      select count(*) into cnt from public.post_comments r
       where r.post_id = p_target and r.author_id is distinct from p_owner and r.status = 'visible' and r.deleted_at is null and r.created_at >= n.created_at
         and not exists (select 1 from public.user_blocks ub where ub.blocker_id = p_owner and ub.blocked_id = r.author_id);
      update public.notifications set message = format('내 글 %s에 새 댓글 %s개가 달렸습니다.', what, greatest(cnt, 2)) where id = n.id;
    else
      insert into public.notifications (user_id, kind, message, post_id)
      values (p_owner, 'post_comment', format('내 글 %s에 새 댓글이 달렸습니다.', what), p_target);
    end if;
  else
    select * into n from public.notifications
     where user_id = p_owner and kind = 'doc_comment' and counter_id = p_target and read_at is null
     order by created_at limit 1 for update;
    if found then
      select count(*) into cnt from public.doc_comments r
       where r.counter_id = p_target and r.author_id is distinct from p_owner and r.status = 'visible' and r.deleted_at is null and r.created_at >= n.created_at
         and not exists (select 1 from public.user_blocks ub where ub.blocker_id = p_owner and ub.blocked_id = r.author_id);
      update public.notifications set message = format('내가 제안한 상대법 문서에 새 댓글 %s개가 달렸습니다.', greatest(cnt, 2)) where id = n.id;
    else
      insert into public.notifications (user_id, kind, message, counter_id)
      values (p_owner, 'doc_comment', '내가 제안한 상대법 문서에 새 댓글이 달렸습니다.', p_target);
    end if;
  end if;
end;
$function$;

-- ---------------------------------------------------------------------
-- 4. 장인 "오늘 새 팔로워 N명": 장인이 차단한 팔로워는 세지 않는다 (나머지는 052 그대로)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.new_follower_digest()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  win constant interval := interval '25 hours';
  keep constant interval := interval '30 days';
  n_notified integer := 0;
  n_counted integer := 0;
  n_pruned integer := 0;
begin
  -- 두 번 겹쳐 돌지 않게
  if not pg_try_advisory_xact_lock(hashtext('new_follower_digest')) then
    return jsonb_build_object('notified', 0, 'counted', 0, 'pruned', 0, 'skipped', true);
  end if;
  delete from public.new_follower_counted where counted_at < now() - keep;
  get diagnostics n_pruned = row_count;
  with fresh as (
    -- 지금도 팔로우 중 + 지난 25시간 안에 팔로우 + 받는 사람이 지금 인증된 장인 + (061) 장인이 차단하지 않은 팔로워
    select f.influencer_id, f.follower_id
      from public.influencer_follows f
      join public.profiles a on a.id = f.influencer_id and a.influencer is not null
     where f.created_at > now() - win
       and f.follower_id <> f.influencer_id
       and not exists (select 1 from public.user_blocks ub where ub.blocker_id = f.influencer_id and ub.blocked_id = f.follower_id)
  ), mark as (
    -- 이미 센 짝은 on conflict로 빠진다 = 새로 센 사람만 남는다
    insert into public.new_follower_counted (influencer_id, follower_id)
    select influencer_id, follower_id from fresh
    on conflict (influencer_id, follower_id) do nothing
    returning influencer_id
  ), ins as (
    insert into public.notifications (user_id, kind, message)
    select m.influencer_id, 'new_followers', format('오늘 새 팔로워 %s명이 생겼습니다.', count(*))
      from mark m
     group by m.influencer_id
    returning 1
  )
  select (select count(*) from mark), (select count(*) from ins) into n_counted, n_notified;
  return jsonb_build_object('notified', n_notified, 'counted', n_counted, 'pruned', n_pruned);
end;
$function$;

commit;
