-- =====================================================================
-- 051: 공지 + 공지 알림 (2026-11-13, SPEC 6-37)
--   공지는 따로 만든 게시판이 아니라 "탑신병자 커뮤니티 글(posts) 중 공지 표시가 붙은 글"이다.
--
-- 1. 공지 글: posts에 칸 is_notice(기본 false)
--    - 운영자(운영자 모드 켜짐, require_operator)만 create_notice(제목, 본문, 사진, 알림 보내기)로 올린다.
--      글쓰기 화면의 [공지로 올리기]를 켜면 [알림 보내기](기본 켬)가 나온다. 끄면 알림 없이 공지만 올라간다.
--    - 일반 글쓰기(create_post)는 그대로 - 공지 표시를 붙일 수 없다. 표를 직접 쓰는 권한은 015부터 없다.
--    - 고치기(edit_post)/숨기기/지우기/댓글/신고는 보통 글과 같다. 고쳐도 알림은 다시 가지 않는다.
--    - 목록(board_page): 줄마다 is_notice, 1쪽(검색 없음)에는 최근 공지 3개를 notices로 따로 준다(화면이 맨 위에 고정).
--    - 운영자 "새 글" 알림(post_created, 042)은 그대로 둔다: 운영자 계정은 하나뿐이고 쓴 사람 본인은 원래 받지 않는다.
-- 2. 알림 notice_posted (새 종류, 푸시 묶음 notice - 푸시 설정 "공지", 기본 켜짐)
--    - 받는 사람: 가입한 모든 계정(정식 회원 + 게스트, 운영진 포함). 공지를 쓴 운영자 본인은 빼고.
--      탈퇴/게스트 정리/비회원 기록 지우기로 프로필이 지워진 계정은 대상에 없다(보내는 순간 profiles에 있는 계정만).
--    - 문장: "새 공지가 올라왔습니다. (낫표)공지 제목(20자까지)(낫표)", post_id = 그 공지 -> 누르면 /board/공지 번호.
--      낫표(U+300C, U+300D)는 SQL Editor에 붙여 넣어도 깨지지 않게 E'' 코드 번호로 적었다.
--    - 폭증 막기 (050 follow-notify와 같은 방식):
--      (a) 공지를 올릴 때는 대기 줄(notice_notify_queue) 한 줄만 넣는다 - 가입자가 많아도 글 올리기가 느려지지 않는다.
--      (b) pg_cron 'notice-notify'가 1분마다 notice_notify_dispatch()로 한 번에 최대 1000명씩 넣는다.
--          가입자 id 순서로 이어서(어디까지 보냈는지 대기 줄에 적어 둠), 한 번의 insert ... select로 넣는다.
--          휴대폰 알림 요청도 1분에 최대 1000개.
--      (c) 보내기 전에 공지가 숨겨지거나 지워지면 남은 사람에게는 보내지 않는다(대기 줄 버림).
--      (d) 시작도 못 한 채 하루 넘게 남은 대기 줄은 버린다(pg_cron을 늦게 켠 경우 - 밀린 알림이 한꺼번에 가지 않게).
--    - 두 번 가지 않게: 대기 줄은 공지마다 한 줄(post_id unique) + 알림 표에 (user_id, post_id) 부분 유일 인덱스
--      notifications_notice_once(kind = 'notice_posted')로 같은 사람에게 같은 공지 알림은 한 개만 생긴다(겹쳐도 on conflict로 건너뜀).
--      공지를 고쳐도 대기 줄을 다시 넣지 않는다.
--    - 읽기 정책/모두 읽음 처리: 이 둘은 "운영자 모드를 끄면 가리는 운영진 알림"만 적어 둔다. 공지 알림은 받는 사람 본인의 알림이라
--      그 목록에 넣지 않는다 = 운영자 모드와 관계없이 보이고 모두 읽음에 함께 읽음 처리된다(DB 검사가 확인). 그래서 둘은 고치지 않는다.
-- 3. 푸시 설정 push_settings에 칸 notice(기본 켜짐) - 본인이 바꿀 수 있게 update 권한도. push_group/push_wanted에 묶음 notice.
--
-- 새 표 1개(notice_notify_queue: RLS 켬, 정책 없음, anon/authenticated 권한 회수 = 직접 읽기/쓰기 불가).
-- 새 설정값 없음(63 그대로). 처리 기록 종류 없음. pg_cron 일정 1개(아래 등록 SQL).
-- Edge Function web-push 재배포 필요(공지 알림을 "새 공지가 올라왔습니다" + 공지 제목, 누르면 그 공지로 보내도록 고쳤다).
--   재배포 전에도 알림은 간다(제목 "탑신병자" + 알림 문장, 누르면 알림 목록).
--
-- >> pg_cron 일정 등록 (실행 뒤 따로 한 번, 시간은 UTC 기준 - 매분이라 시차 없음):
--     select cron.schedule('notice-notify', '* * * * *', $$select public.notice_notify_dispatch()$$);
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다. 051이 만든 것만 지우고 050 상태로 돌아간다.
--    052를 실행했다면 052의 되돌리기를 먼저 실행한다(052가 push_group/push_wanted를 다시 만들기 때문).
--    (공지 표시와 이미 보낸 notice_posted 알림도 지워진다. 공지였던 글은 보통 글로 남는다. 푸시 설정의 다른 칸은 그대로.)
--     begin;
--     do $r$ begin
--       if to_regclass('cron.job') is not null then
--         perform cron.unschedule(jobid) from cron.job where jobname = 'notice-notify';
--       end if;
--     end $r$;
--     drop function if exists public.create_notice(text, text, text[], boolean);
--     drop function if exists public.notice_notify_dispatch(integer);
--     drop table if exists public.notice_notify_queue;
--     delete from public.notifications where kind = 'notice_posted';
--     drop index if exists public.notifications_notice_once;
--     alter table public.notifications drop constraint notifications_kind_check;
--     alter table public.notifications add constraint notifications_kind_check check (kind = any (array[
--       'revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
--       'build_hidden', 'build_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked',
--       'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored',
--       'doc_comment', 'doc_comment_hidden', 'doc_comment_restored', 'moderator_granted', 'moderator_revoked',
--       'inquiry_answered', 'proposal_submitted', 'build_submitted', 'inquiry_received', 'counter_restored',
--       'matchup_created', 'build_created', 'post_deleted', 'comment_deleted', 'doc_comment_deleted', 'post_created',
--       'error_reported', 'error_report_handled', 'report_received',
--       'influencer_applied', 'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
--       'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed',
--       'followed_build_created']));
--     create or replace function public.push_group(p_kind text)
--     returns text language sql immutable set search_path = ''
--     as $f$
--       select case
--         when p_kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created',
--                         'error_reported', 'report_received', 'influencer_applied') then 'staff_new'
--         when p_kind in ('proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
--                         'revision_request', 'counter_restored', 'build_restored',
--                         'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
--                         'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed') then 'my_results'
--         when p_kind in ('followed_build_created') then 'follow_builds'
--       end;
--     $f$;
--     comment on function public.push_group(text) is
--       '푸시로 보내는 알림 종류의 묶음: staff_new(운영진) / my_results(내 결과) / follow_builds(팔로우한 장인의 새 빌드, 050) / null(푸시 안 함)';
--     create or replace function public.push_wanted(p_user uuid, p_kind text)
--     returns boolean language sql stable security definer set search_path = ''
--     as $f$
--       select case public.push_group(p_kind)
--         when 'staff_new' then
--           exists (select 1 from public.profiles p
--                    where p.id = p_user and (p.role = 'moderator' or (p.role = 'admin' and p.operator_mode)))
--           and coalesce((select s.staff_new from public.push_settings s where s.user_id = p_user), true)
--         when 'my_results' then
--           coalesce((select s.my_results from public.push_settings s where s.user_id = p_user), true)
--         when 'follow_builds' then
--           coalesce((select s.follow_builds from public.push_settings s where s.user_id = p_user), true)
--         else false
--       end
--       and exists (select 1 from public.push_subscriptions where user_id = p_user);
--     $f$;
--     alter table public.push_settings drop column notice;
--     create or replace function public.board_page(p_q text default null, p_page integer default 1, p_size integer default 20)
--     returns jsonb language plpgsql stable set search_path = ''
--     as $f$
--     declare
--       q text := nullif(btrim(coalesce(p_q, '')), '');
--       pat text;
--       sz integer := least(greatest(coalesce(p_size, 20), 1), 50);
--       pg integer := greatest(coalesce(p_page, 1), 1);
--       total integer;
--       items jsonb;
--     begin
--       if q is not null then
--         pat := '%' || replace(replace(replace(left(q, 50), '\', '\\'), '%', '\%'), '_', '\_') || '%';
--       end if;
--       select count(*) into total from public.posts p
--       where p.deleted_at is null and (pat is null or p.title ilike pat or p.body ilike pat);
--       select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc, x.id desc), '[]'::jsonb) into items
--       from (
--         select p.id, p.title, p.status, false as deleted, p.comment_count, p.up_count,
--                p.created_at, p.edited_at,
--                (select count(*) from public.board_attachments a where a.post_id = p.id) as media_count,
--                (select jsonb_build_object('nickname', a.nickname, 'role', a.role, 'level', a.level, 'main_title', a.main_title, 'influencer', a.influencer, 'nickname_state', a.nickname_state)
--                 from public.profiles a where a.id = p.author_id) as author
--         from public.posts p
--         where p.deleted_at is null and (pat is null or p.title ilike pat or p.body ilike pat)
--         order by p.created_at desc, p.id desc
--         limit sz offset (pg - 1) * sz
--       ) x;
--       return jsonb_build_object('total', total, 'size', sz, 'rows', items);
--     end;
--     $f$;
--     drop index if exists public.posts_notice_idx;
--     alter table public.posts drop column is_notice;
--     commit;
--   되돌린 뒤 다시 051을 실행해도 된다(처음부터 다시 만든다).
--
-- 하위 호환: 있던 표/함수의 이름/인자/반환은 그대로(board_page는 돌려주는 값에 is_notice/notices만 더함).
--   새 표 1개/새 함수 2개/칸 2개/알림 종류 1개/부분 유일 인덱스 1개만 더한다. 지금 배포된 화면과 그대로 동작한다.
-- 순서: check_notice_before.sql -> 이 파일 실행 -> check_notice_after.sql -> pg_cron 일정 등록 -> check_notice_after.sql 마지막 줄 확인.
-- 050까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.influencer_follows') is null then
    raise exception '050이 아직 실행되지 않았습니다. 050을 먼저 실행해 주세요.';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'posts' and column_name = 'is_notice') then
    raise exception '051을 이미 실행했습니다.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. 공지 표시 칸 + 알림 대기 줄 (RLS 켬 + 정책 없음 + 권한 회수 = 직접 읽기/쓰기 불가, 함수로만)
-- ---------------------------------------------------------------------
alter table public.posts add column is_notice boolean not null default false;
comment on column public.posts.is_notice is '공지 (051). 운영자가 create_notice로 올린 글만 true. 목록 1쪽 맨 위에 고정';
create index posts_notice_idx on public.posts (created_at desc, id desc) where is_notice and deleted_at is null;

create table public.notice_notify_queue (
  id          bigint generated always as identity primary key,
  post_id     bigint not null references public.posts (id) on delete cascade,
  after_user  uuid,                                   -- 여기까지(이 가입자 id까지) 보냄. 비어 있으면 아직 시작 전
  created_at  timestamptz not null default now()
);
create unique index notice_notify_queue_post on public.notice_notify_queue (post_id);  -- 공지마다 한 줄
comment on table public.notice_notify_queue is
  '공지 알림 대기 줄 (051). notice_notify_dispatch(pg_cron notice-notify)가 1분마다 1000명씩 보낸다. 직접 읽기/쓰기 불가';
alter table public.notice_notify_queue enable row level security;
revoke all on public.notice_notify_queue from anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. 알림 종류 / 같은 공지 알림은 한 사람에게 한 개 / 푸시 묶음 / 푸시 설정 칸
-- ---------------------------------------------------------------------
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind = any (array[
  'revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
  'build_hidden', 'build_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked',
  'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored',
  'doc_comment', 'doc_comment_hidden', 'doc_comment_restored', 'moderator_granted', 'moderator_revoked',
  'inquiry_answered', 'proposal_submitted', 'build_submitted', 'inquiry_received', 'counter_restored',
  'matchup_created', 'build_created', 'post_deleted', 'comment_deleted', 'doc_comment_deleted', 'post_created',
  'error_reported', 'error_report_handled', 'report_received',
  'influencer_applied', 'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
  'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed',
  'followed_build_created',
  'notice_posted'  -- 051
]));
create unique index notifications_notice_once on public.notifications (user_id, post_id) where kind = 'notice_posted';

alter table public.push_settings add column notice boolean not null default true;
comment on column public.push_settings.notice is '공지 휴대폰 알림 (051). 기본 켜짐';
grant update (notice) on public.push_settings to authenticated;  -- 본인 줄만 (RLS 그대로)

create or replace function public.push_group(p_kind text)
returns text language sql immutable set search_path = ''
as $$
  select case
    when p_kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created',
                    'error_reported', 'report_received', 'influencer_applied') then 'staff_new'
    when p_kind in ('proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
                    'revision_request', 'counter_restored', 'build_restored',
                    'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
                    'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed') then 'my_results'
    when p_kind in ('followed_build_created') then 'follow_builds'
    when p_kind in ('notice_posted') then 'notice'
  end;
$$;
comment on function public.push_group(text) is
  '푸시로 보내는 알림 종류의 묶음: staff_new(운영진) / my_results(내 결과) / follow_builds(팔로우한 장인의 새 빌드, 050) / notice(공지, 051) / null(푸시 안 함)';

create or replace function public.push_wanted(p_user uuid, p_kind text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select case public.push_group(p_kind)
    when 'staff_new' then
      exists (select 1 from public.profiles p
               where p.id = p_user and (p.role = 'moderator' or (p.role = 'admin' and p.operator_mode)))
      and coalesce((select s.staff_new from public.push_settings s where s.user_id = p_user), true)
    when 'my_results' then
      coalesce((select s.my_results from public.push_settings s where s.user_id = p_user), true)
    when 'follow_builds' then
      coalesce((select s.follow_builds from public.push_settings s where s.user_id = p_user), true)
    when 'notice' then
      coalesce((select s.notice from public.push_settings s where s.user_id = p_user), true)
    else false
  end
  and exists (select 1 from public.push_subscriptions where user_id = p_user);
$$;

-- ---------------------------------------------------------------------
-- 3. 공지 올리기 (운영자만, 운영자 모드 켜짐). 돌려주는 값: 새 글 id
--    제목/본문/사진/도배 간격 검사는 create_post와 같다. p_notify = false면 대기 줄을 넣지 않는다(알림 없음)
-- ---------------------------------------------------------------------
create function public.create_notice(p_title text, p_body text, p_media text[] default '{}', p_notify boolean default true)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  t text;
  b text;
  new_id bigint;
begin
  perform public.require_operator();
  t := public.board_text(p_title, '제목', 100);
  b := public.board_text_or_empty(p_body, '본문', 10000, cardinality(coalesce(p_media, '{}')) > 0);
  perform public.board_throttle(me, 'post');
  insert into public.posts (author_id, title, body, is_notice) values (me, t, b, true) returning id into new_id;
  perform public.media_set(new_id, null, me, p_media);
  if coalesce(p_notify, true) then
    insert into public.notice_notify_queue (post_id) values (new_id) on conflict (post_id) do nothing;
  end if;
  return new_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 목록: 줄마다 is_notice + 1쪽(검색 없음)에 최근 공지 3개(notices). 숨긴 공지는 RLS대로 운영진만 본다
-- ---------------------------------------------------------------------
create or replace function public.board_page(p_q text default null, p_page integer default 1, p_size integer default 20)
returns jsonb language plpgsql stable set search_path = ''
as $$
declare
  q text := nullif(btrim(coalesce(p_q, '')), '');
  pat text;
  sz integer := least(greatest(coalesce(p_size, 20), 1), 50);
  pg integer := greatest(coalesce(p_page, 1), 1);
  total integer;
  items jsonb;
  pinned jsonb := '[]'::jsonb;
begin
  if q is not null then
    pat := '%' || replace(replace(replace(left(q, 50), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  end if;
  select count(*) into total from public.posts p
  where p.deleted_at is null and (pat is null or p.title ilike pat or p.body ilike pat);

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc, x.id desc), '[]'::jsonb) into items
  from (
    select p.id, p.title, p.status, false as deleted, p.comment_count, p.up_count,
           p.created_at, p.edited_at, p.is_notice,
           (select count(*) from public.board_attachments a where a.post_id = p.id) as media_count,
           (select jsonb_build_object('nickname', a.nickname, 'role', a.role, 'level', a.level, 'main_title', a.main_title, 'influencer', a.influencer, 'nickname_state', a.nickname_state)
            from public.profiles a where a.id = p.author_id) as author
    from public.posts p
    where p.deleted_at is null and (pat is null or p.title ilike pat or p.body ilike pat)
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
      order by p.created_at desc, p.id desc
      limit 3
    ) x;
  end if;
  return jsonb_build_object('total', total, 'size', sz, 'rows', items, 'notices', pinned);
end;
$$;

-- ---------------------------------------------------------------------
-- 5. 공지 알림 나눠 보내기 (pg_cron notice-notify, 1분마다). 한 번에 최대 p_limit(기본 1000)명.
--    돌려주는 값: { sent: 새로 넣은 알림 수, skipped_dup: 이미 있어 건너뜀, dropped: 버린 대기 줄, left: 남은 대기 줄 }
-- ---------------------------------------------------------------------
create function public.notice_notify_dispatch(p_limit integer default 1000)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  budget integer := least(greatest(coalesce(p_limit, 1000), 1), 5000);
  stale_after constant interval := interval '1 day';
  e record;
  p record;
  msg text;
  took integer;
  inserted integer;
  last_u uuid;
  n_sent integer := 0;
  n_dup integer := 0;
  n_dropped integer := 0;
begin
  -- 두 번 겹쳐 돌지 않게 (앞의 실행이 끝나지 않았으면 이번 실행은 그냥 끝)
  if not pg_try_advisory_xact_lock(hashtext('notice_notify_dispatch')) then
    return jsonb_build_object('sent', 0, 'skipped_dup', 0, 'dropped', 0, 'left', -1, 'skipped', true);
  end if;
  for e in select * from public.notice_notify_queue order by id loop
    exit when budget <= 0;
    select pp.id, pp.title, pp.author_id into p
      from public.posts pp
     where pp.id = e.post_id and pp.is_notice and pp.status = 'visible' and pp.deleted_at is null;
    if not found or (e.after_user is null and e.created_at < now() - stale_after) then
      delete from public.notice_notify_queue where id = e.id;  -- 숨겨짐/지워짐/시작 전에 너무 오래됨 -> 보내지 않음
      n_dropped := n_dropped + 1;
      continue;
    end if;
    msg := format(E'새 공지가 올라왔습니다. \u300C%s\u300D', public.post_snippet(p.title));  -- 낫표 안에 제목
    with tgt as (
      select u.id from public.profiles u
       where u.id is distinct from p.author_id
         and (e.after_user is null or u.id > e.after_user)
       order by u.id
       limit budget
    ), ins as (
      insert into public.notifications (user_id, kind, message, post_id)
      select tgt.id, 'notice_posted', msg, p.id from tgt
      on conflict (user_id, post_id) where kind = 'notice_posted' do nothing
      returning 1
    )
    select (select count(*) from tgt), (select count(*) from ins), (select tgt.id from tgt order by tgt.id desc limit 1)
      into took, inserted, last_u;
    n_sent := n_sent + inserted;
    n_dup := n_dup + (took - inserted);
    if took < budget then
      delete from public.notice_notify_queue where id = e.id;  -- 이 공지는 다 보냄
    else
      update public.notice_notify_queue set after_user = last_u where id = e.id;  -- 다음 실행에서 이어서
    end if;
    budget := budget - took;
  end loop;
  return jsonb_build_object('sent', n_sent, 'skipped_dup', n_dup, 'dropped', n_dropped,
                            'left', (select count(*) from public.notice_notify_queue));
end;
$$;

-- ---------------------------------------------------------------------
-- 6. 권한
--   로그인(authenticated)만: create_notice (운영자인지는 함수 안에서)
--   아무도 직접 못 부름: notice_notify_dispatch (pg_cron만)
--   board_page / push_group / push_wanted는 create or replace라 있던 권한 그대로
-- ---------------------------------------------------------------------
revoke execute on function public.notice_notify_dispatch(integer) from public, anon, authenticated;
revoke execute on function public.create_notice(text, text, text[], boolean) from public, anon;
grant execute on function public.create_notice(text, text, text[], boolean) to authenticated;

commit;

-- 확인 (실행 뒤): supabase/scripts/check_notice_after.sql
-- pg_cron 일정 등록 (실행 뒤 따로 한 번):
--   select cron.schedule('notice-notify', '* * * * *', $$select public.notice_notify_dispatch()$$);
