-- =====================================================================
-- 050: 장인 팔로우 + 팔로우한 장인의 빌드 모아 보기 - DB (2026-11-12, SPEC 6-36)
--   화면 문구는 "장인", 코드/DB 이름은 influencer 그대로. 화면은 다음 차례("화면 진행해" 뒤).
--
-- 1. 팔로우 표 influencer_follows (팔로우한 사람, 장인, 팔로우한 때 + 알림 묶기용 칸)
--    - 로그인한 모든 사용자(정식 회원과 게스트)가 팔로우할 수 있다. 비로그인은 함수 실행 권한이 없다.
--    - 대상은 지금 인증된 장인(profiles.influencer)만. 자기 자신은 안 된다(표 검사로도 막음). 인원 제한 없음.
--    - 너무 잦은 호출만 막는다: 팔로우/팔로우 취소를 합쳐 1분에 30번(follow_rate 표, 고정 1분 창).
--      설정값(xp_rules)은 늘리지 않는다(63 그대로) - 숫자는 이 파일의 함수 안에 있다.
--    - 표를 직접 읽거나 쓸 수 없다(RLS 켬, 정책 없음, 권한 회수). 모두 함수로만.
-- 2. 지워지는 때
--    - 장인 인증 해제(profiles.influencer가 비워지는 모든 길): 그 장인을 팔로우한 기록과 보낼 알림 대기 줄을 바로 지운다
--      (트리거 follows_on_influencer_end - 047의 링크 삭제와 같은 규칙). 다시 인증돼도 팔로우는 돌아오지 않는다.
--    - 회원 탈퇴 / 게스트 계정 정리(cleanup-guests) / 비회원 기록 지우기: 프로필이 지워지며 그 사람이 한 팔로우와
--      그 사람을 팔로우한 기록, 호출 횟수 줄이 함께 지워진다(on delete cascade).
-- 3. 알림 followed_build_created (새 종류, 푸시 묶음 follow_builds - 푸시 설정에서 따로 끄고 켬, 기본 켜짐)
--    - 팔로우한 장인이 "새 빌드를 만들 때"만(새 상대법의 첫 빌드 포함, 승인 제도를 다시 켜면 처음 공개될 때). 수정/숨김/다시 공개는 알림 없음.
--    - 장인 본인, 숨겨진 빌드(알림을 보내기 전에 숨겨지거나 지워진 빌드 포함), 장인이 아닌 작성자는 제외.
--    - 폭증 막기 설계:
--      (a) 빌드를 만들 때는 대기 줄(follow_notify_queue) 한 줄만 넣는다 - 팔로워가 많아도 빌드 등록이 느려지지 않는다.
--      (b) pg_cron 'follow-notify'가 1분마다 follow_notify_dispatch()를 불러 대기 줄을 팔로워에게 나눠 보낸다.
--          한 번에 최대 1000명 - 남으면 다음 분에 이어서(어디까지 보냈는지 대기 줄에 적어 둠). 휴대폰 알림 요청도 1분에 1000개를 넘지 않는다.
--      (c) 같은 장인이 짧은 시간에 여러 개를 만들면 묶는다: 그 팔로워에게 그 장인 알림을 보낸 지 3시간이 안 됐으면
--          새 알림을 만들지 않고 보낸 알림을 "새 빌드가 N개 올라왔습니다"로 고치고 다시 안 읽음으로 한다(휴대폰 알림은 다시 안 감).
--          그래서 한 팔로워는 한 장인에게서 3시간에 휴대폰 알림을 최대 1번 받는다.
--      (d) 대기 줄이 하루 넘게 남아 있으면(pg_cron을 늦게 켠 경우 등) 보내지 않고 버린다 - 밀린 알림이 한꺼번에 쏟아지지 않게.
--    - 읽기 정책/모두 읽음 처리: 이 둘이 따로 적어 둔 종류는 "운영자 모드를 끄면 가리는 운영진 알림"뿐이다.
--      새 종류는 받는 사람 본인의 알림이라 그 목록에 넣지 않는다 = 운영자 모드와 관계없이 늘 보이고, 모두 읽음에 함께 읽음 처리된다
--      (DB 검사가 둘 다 확인). 알림 종류 검사(notifications_kind_check)와 푸시 묶음(push_group/push_wanted)에는 넣었다.
-- 4. 함수 (바깥 함수가 로그인/운영자를 확인하고, _unchecked 안쪽 함수가 일을 한다. 안쪽 함수는 아무도 직접 못 부름)
--    비로그인도:  search_influencers(검색어, 쪽)       인증된 장인 닉네임 부분 일치(한 글자 이상), 20개씩
--                 influencer_builds(장인 id 글자, 쪽)  그 장인이 처음 만든 공개 빌드, 최근 수정순, 20개씩 (장인 아니면 null)
--                 influencer_follower_count(장인 id 글자) 팔로워 수 (장인 아니면 null)
--    로그인(게스트 포함): follow_influencer(장인) / unfollow_influencer(장인) -> {following, follower_count}
--                 influencer_followers(장인, 쪽)  팔로워 목록(닉네임, 팔로우한 날), 20개씩
--                 my_following(쪽)               내가 팔로우한 장인, 20개씩
--                 followed_builds(쪽)            내가 팔로우한 장인들의 공개 빌드, 최근 수정순, 20개씩
--                 follow_status(장인 id 목록)    {"id": true/false} - 빌드 목록의 [+] 버튼 상태 (한 번에 100명까지)
--    운영자 전용(운영자 모드 꺼짐 거부): admin_influencer_list(쪽, 크기) 닉네임/유형/직접 지정 여부/인증일/팔로워 수
--    비로그인용 함수는 이메일/라이엇 닉네임/역할을 돌려주지 않는다(id/닉네임/장인 유형/수/빌드 카드만).
-- 5. 푸시 설정 push_settings에 칸 follow_builds(기본 켜짐) - 본인이 바꿀 수 있게 update 권한도.
--
-- 새 설정값 없음(63 그대로). 처리 기록 종류 없음. pg_cron 일정 1개(아래 등록 SQL). Edge Function 재배포: 이번에는 필요 없음
--   (지금 web-push는 모르는 종류를 제목 "탑신병자" + 알림 목록으로 보낸다. 빌드로 바로 가게 하는 것은 화면 단계에서 web-push를 고치고 재배포).
--
-- >> pg_cron 일정 등록 (실행 뒤 따로 한 번):
--     select cron.schedule('follow-notify', '* * * * *', $$select public.follow_notify_dispatch()$$);
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다. 050이 만든 것만 지우고 049 상태로 돌아간다.
--    (팔로우 기록과 이미 보낸 followed_build_created 알림도 지워진다. 사용자가 저장한 푸시 설정의 다른 칸은 그대로.)
--     begin;
--     do $r$ begin
--       if to_regclass('cron.job') is not null then
--         perform cron.unschedule(jobid) from cron.job where jobname = 'follow-notify';
--       end if;
--     end $r$;
--     drop trigger if exists builds_follow_notify on public.builds;
--     drop trigger if exists follows_on_influencer_end on public.profiles;
--     drop function if exists public.follow_queue_on_build();
--     drop function if exists public.follows_on_influencer_end();
--     drop function if exists public.follow_notify_dispatch(integer);
--     drop function if exists public.follow_throttle(uuid);
--     drop function if exists public.follow_build_card(bigint);
--     drop function if exists public.search_influencers(text, integer);
--     drop function if exists public.influencer_builds(text, integer);
--     drop function if exists public.influencer_follower_count(text);
--     drop function if exists public.follow_influencer(uuid);
--     drop function if exists public.follow_influencer_unchecked(uuid, uuid);
--     drop function if exists public.unfollow_influencer(uuid);
--     drop function if exists public.unfollow_influencer_unchecked(uuid, uuid);
--     drop function if exists public.influencer_followers(uuid, integer);
--     drop function if exists public.influencer_followers_unchecked(uuid, integer);
--     drop function if exists public.my_following(integer);
--     drop function if exists public.my_following_unchecked(uuid, integer);
--     drop function if exists public.followed_builds(integer);
--     drop function if exists public.followed_builds_unchecked(uuid, integer);
--     drop function if exists public.follow_status(uuid[]);
--     drop function if exists public.follow_status_unchecked(uuid, uuid[]);
--     drop function if exists public.admin_influencer_list(integer, integer);
--     drop function if exists public.admin_influencer_list_unchecked(integer, integer);
--     drop table if exists public.follow_notify_queue;
--     drop table if exists public.follow_rate;
--     drop table if exists public.influencer_follows;
--     delete from public.notifications where kind = 'followed_build_created';
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
--       'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed']));
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
--       end;
--     $f$;
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
--         else false
--       end
--       and exists (select 1 from public.push_subscriptions where user_id = p_user);
--     $f$;
--     alter table public.push_settings drop column follow_builds;
--     commit;
--   되돌린 뒤 다시 050을 실행해도 된다(처음부터 다시 만든다).
--
-- 하위 호환: 있던 표/함수의 이름/인자/반환은 그대로. 새 표 3개/새 함수/트리거 2개/알림 종류 1개/푸시 설정 칸 1개만 더한다.
--   push_group/push_wanted는 같은 이름/인자로 새 묶음만 더한다. 지금 배포된 화면과 그대로 동작한다
--   (팔로우 화면이 없으니 팔로우/알림도 생기지 않는다. 푸시 설정 저장은 있던 두 칸만 보내므로 새 칸은 기본값 그대로).
-- 순서: check_follow.sql(실행 전) -> 이 파일 실행 -> check_follow.sql(실행 후) -> pg_cron 일정 등록 -> check_follow.sql 마지막 줄 확인.
-- 049까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'influencer_applications' and column_name = 'direct') then
    raise exception '049가 아직 실행되지 않았습니다. 046~049를 먼저 실행해 주세요.';
  end if;
  if to_regclass('public.influencer_follows') is not null then
    raise exception '050을 이미 실행했습니다.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. 표 (모두 RLS 켬 + 정책 없음 + 권한 회수 = 로그인/비로그인 모두 직접 읽기/쓰기 불가, 함수로만)
-- ---------------------------------------------------------------------
create table public.influencer_follows (
  follower_id       uuid not null references public.profiles (id) on delete cascade,  -- 팔로우한 사람 (탈퇴/게스트 정리 때 함께 지워짐)
  influencer_id     uuid not null references public.profiles (id) on delete cascade,  -- 장인 (해제되면 트리거가 지움)
  created_at        timestamptz not null default now(),                                -- 팔로우한 때
  last_notified_at  timestamptz,                                                       -- 이 장인 알림을 새로 만든 때 (3시간 묶기 기준)
  notify_count      integer not null default 0 check (notify_count >= 0),              -- 그 알림에 묶인 새 빌드 수
  notification_id   bigint references public.notifications (id) on delete set null,   -- 그 알림 (지워지면 비워짐 -> 다음엔 새 알림)
  primary key (follower_id, influencer_id),
  constraint influencer_follows_not_self check (follower_id <> influencer_id)
);
create index influencer_follows_influencer on public.influencer_follows (influencer_id, created_at desc, follower_id);
create index influencer_follows_follower on public.influencer_follows (follower_id, created_at desc, influencer_id);
comment on table public.influencer_follows is
  '장인 팔로우 (050). 로그인한 사용자(게스트 포함) -> 인증된 장인. 직접 읽기/쓰기 불가, 함수로만. 해제되면 트리거가, 탈퇴/게스트 정리는 cascade가 지움';
alter table public.influencer_follows enable row level security;
revoke all on public.influencer_follows from anon, authenticated;

create table public.follow_rate (
  user_id       uuid primary key references public.profiles (id) on delete cascade,
  window_start  timestamptz not null default now(),
  n             integer not null default 0 check (n >= 0)
);
comment on table public.follow_rate is '팔로우/팔로우 취소 호출 횟수 (050). 1분 창에 30번까지. 직접 읽기/쓰기 불가';
alter table public.follow_rate enable row level security;
revoke all on public.follow_rate from anon, authenticated;

create table public.follow_notify_queue (
  id              bigint generated always as identity primary key,
  build_id        bigint not null references public.builds (id) on delete cascade,
  influencer_id   uuid not null references public.profiles (id) on delete cascade,
  after_follower  uuid,                                   -- 여기까지(이 팔로워 id까지) 보냄. 비어 있으면 처음부터
  created_at      timestamptz not null default now()
);
create unique index follow_notify_queue_build on public.follow_notify_queue (build_id);
comment on table public.follow_notify_queue is
  '팔로우한 장인의 새 빌드 알림 대기 줄 (050). follow_notify_dispatch(pg_cron follow-notify)가 1분마다 1000명씩 보낸다. 직접 읽기/쓰기 불가';
alter table public.follow_notify_queue enable row level security;
revoke all on public.follow_notify_queue from anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. 알림 종류 / 푸시 묶음 / 푸시 설정 칸
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
  'followed_build_created'  -- 050
]));

alter table public.push_settings add column follow_builds boolean not null default true;
comment on column public.push_settings.follow_builds is '팔로우한 장인의 새 빌드 휴대폰 알림 (050). 기본 켜짐';
grant update (follow_builds) on public.push_settings to authenticated;  -- 본인 줄만 (RLS 그대로)

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
  end;
$$;
comment on function public.push_group(text) is
  '푸시로 보내는 알림 종류의 묶음: staff_new(운영진) / my_results(내 결과) / follow_builds(팔로우한 장인의 새 빌드, 050) / null(푸시 안 함)';

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
    else false
  end
  and exists (select 1 from public.push_subscriptions where user_id = p_user);
$$;

-- ---------------------------------------------------------------------
-- 3. 도우미 (아무도 직접 못 부름)
-- ---------------------------------------------------------------------
-- 빌드 카드 한 장 (공개 빌드 목록용). 이메일/라이엇/역할 없음. 작성자는 id/닉네임/장인 유형만
create function public.follow_build_card(p_build bigint)
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'id', b.id, 'counter_id', b.counter_id, 'seq', b.seq, 'name', b.name, 'patch', b.patch, 'summary', b.summary,
    'target_champion', c.target_champion, 'counter_champion', c.counter_champion,
    'runes', b.runes, 'summoner_spells', to_jsonb(b.summoner_spells), 'core_items', to_jsonb(b.core_items), 'max_skill', b.max_skill,
    'up_count', b.up_count, 'down_count', b.down_count,
    'created_at', b.created_at, 'updated_at', coalesce(b.updated_at, b.created_at),
    'editor_count', (select count(*) from public.build_editors e where e.build_id = b.id and e.user_id is distinct from b.author_id),
    'author', (select jsonb_build_object('id', p.id, 'nickname', p.nickname, 'influencer', p.influencer)
                 from public.profiles p where p.id = b.author_id),
    'link', (select public.ext_link_json(l.id) from public.ext_links l where l.build_id = b.id and public.ext_link_visible(l.id)))
    from public.builds b join public.counters c on c.id = b.counter_id
   where b.id = p_build;
$$;

-- 팔로우/팔로우 취소 호출 횟수: 1분 창에 30번까지 (둘을 합쳐 셈)
create function public.follow_throttle(p_me uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  r public.follow_rate;
  per_minute constant integer := 30;
begin
  insert into public.follow_rate (user_id) values (p_me) on conflict (user_id) do nothing;
  select * into r from public.follow_rate where user_id = p_me for update;
  if r.window_start <= now() - interval '1 minute' then
    update public.follow_rate set window_start = now(), n = 1 where user_id = p_me;
  elsif r.n >= per_minute then
    raise exception '팔로우를 너무 자주 눌렀습니다. 1분 뒤에 다시 해 주세요.' using errcode = '23514';
  else
    update public.follow_rate set n = n + 1 where user_id = p_me;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 누구나 (비로그인 포함): 장인 검색 / 장인의 공개 빌드 / 팔로워 수
-- ---------------------------------------------------------------------
-- 인증된 장인 닉네임 부분 일치 (대소문자 무시 + 비슷한 글자 열쇠 nickname_key). 같은 닉네임 먼저, 그다음 팔로워 많은 순. 20개씩
-- 돌려주는 값: { total, page, size, items: [{ id, nickname, influencer, follower_count, build_count }] }
create function public.search_influencers(p_query text, p_page integer default 1)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  q text := btrim(coalesce(p_query, ''));
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz constant integer := 20;
  pat text;
  k text;
  kpat text;
begin
  if q = '' then
    raise exception '검색어를 한 글자 이상 적어 주세요.' using errcode = '22023';
  end if;
  if char_length(q) > 20 then
    raise exception '검색어는 20자 이하로 적어 주세요.' using errcode = '22023';
  end if;
  pat := '%' || replace(replace(replace(lower(q), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  k := public.nickname_key(q);
  if coalesce(k, '') <> '' then
    kpat := '%' || replace(replace(replace(k, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  end if;
  return (
    with m as (
      select p.id, p.nickname, p.influencer,
             (lower(p.nickname) = lower(q)) as exact,
             (select count(*) from public.influencer_follows f where f.influencer_id = p.id) as followers
        from public.profiles p
       where p.influencer is not null and p.nickname is not null
         and (lower(p.nickname) like pat escape '\' or (kpat is not null and p.nickname_key like kpat escape '\'))
    )
    select jsonb_build_object(
      'total', (select count(*) from m),
      'page', pg, 'size', sz,
      'items', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', x.id, 'nickname', x.nickname, 'influencer', x.influencer, 'follower_count', x.followers,
                 'build_count', (select count(*) from public.builds b join public.counters c on c.id = b.counter_id
                                  where b.author_id = x.id and b.status = 'approved' and c.status = 'approved'))
               order by x.exact desc, x.followers desc, x.nickname, x.id)
          from (select * from m order by exact desc, followers desc, nickname, id limit sz offset (pg - 1) * sz) x
      ), '[]'::jsonb)));
end;
$$;

-- 장인이 처음 만든 공개 빌드 (숨김/삭제 제외, 상대법도 공개 중), 최근 수정순, 20개씩.
-- 장인이 아님/없는 id/id 모양이 틀림은 모두 null (public_profile과 같음).
-- 돌려주는 값: { influencer: { id, nickname, influencer }, follower_count, total, page, size, items: [빌드 카드] }
create function public.influencer_builds(p_user text, p_page integer default 1)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  uid uuid;
  p public.profiles%rowtype;
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz constant integer := 20;
begin
  if p_user is null or p_user !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  uid := p_user::uuid;
  select * into p from public.profiles where id = uid and influencer is not null and nickname is not null;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'influencer', jsonb_build_object('id', p.id, 'nickname', p.nickname, 'influencer', p.influencer),
    'follower_count', (select count(*) from public.influencer_follows f where f.influencer_id = p.id),
    'total', (select count(*) from public.builds b join public.counters c on c.id = b.counter_id
               where b.author_id = p.id and b.status = 'approved' and c.status = 'approved'),
    'page', pg, 'size', sz,
    'items', coalesce((
      select jsonb_agg(public.follow_build_card(x.id) order by x.t desc, x.id desc)
        from (select b.id, coalesce(b.updated_at, b.created_at) as t
                from public.builds b join public.counters c on c.id = b.counter_id
               where b.author_id = p.id and b.status = 'approved' and c.status = 'approved'
               order by coalesce(b.updated_at, b.created_at) desc, b.id desc
               limit sz offset (pg - 1) * sz) x
    ), '[]'::jsonb));
end;
$$;

-- 팔로워 수 (누구나). 장인이 아님/없는 id/id 모양이 틀림은 null
create function public.influencer_follower_count(p_user text)
returns integer language plpgsql stable security definer set search_path = ''
as $$
begin
  if p_user is null or p_user !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  if not exists (select 1 from public.profiles where id = p_user::uuid and influencer is not null) then
    return null;
  end if;
  return (select count(*) from public.influencer_follows where influencer_id = p_user::uuid);
end;
$$;

-- ---------------------------------------------------------------------
-- 5. 로그인한 사용자 (게스트 포함): 안쪽 함수(_unchecked, p_me = 부른 사람) + 바깥 함수(로그인 확인)
-- ---------------------------------------------------------------------
-- 팔로우. 돌려주는 값: { following: true, follower_count }. 이미 팔로우 중이면 그대로(오류 아님)
create function public.follow_influencer_unchecked(p_me uuid, p_user uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  if p_user is null or not exists (select 1 from public.profiles where id = p_user and influencer is not null) then
    raise exception '인증된 장인만 팔로우할 수 있습니다.' using errcode = 'P0002';
  end if;
  if p_user = p_me then
    raise exception '나 자신은 팔로우할 수 없습니다.' using errcode = '23514';
  end if;
  perform public.follow_throttle(p_me);
  insert into public.influencer_follows (follower_id, influencer_id) values (p_me, p_user)
  on conflict (follower_id, influencer_id) do nothing;
  return jsonb_build_object('following', true,
    'follower_count', (select count(*) from public.influencer_follows where influencer_id = p_user));
end;
$$;

create function public.follow_influencer(p_user uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  return public.follow_influencer_unchecked(me, p_user);
end;
$$;

-- 팔로우 취소. 돌려주는 값: { following: false, follower_count }. 팔로우하지 않았어도 그대로(오류 아님). 장인이 아니어도 지울 수 있다
create function public.unfollow_influencer_unchecked(p_me uuid, p_user uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  if p_user is null then
    raise exception '팔로우를 취소할 장인을 골라 주세요.' using errcode = '22023';
  end if;
  perform public.follow_throttle(p_me);
  delete from public.influencer_follows where follower_id = p_me and influencer_id = p_user;
  return jsonb_build_object('following', false,
    'follower_count', (select count(*) from public.influencer_follows where influencer_id = p_user));
end;
$$;

create function public.unfollow_influencer(p_user uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  return public.unfollow_influencer_unchecked(me, p_user);
end;
$$;

-- 팔로워 목록 (로그인한 사용자만 - 비로그인은 수만). 최근 팔로우 순, 20개씩. 닉네임을 아직 안 정한 사람은 nickname null
-- 돌려주는 값: { follower_count, total, page, size, items: [{ id, nickname, influencer, nickname_state, followed_at }] } - 역할/레벨 없음
create function public.influencer_followers_unchecked(p_user uuid, p_page integer)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz constant integer := 20;
  n bigint;
begin
  if p_user is null or not exists (select 1 from public.profiles where id = p_user and influencer is not null) then
    raise exception '인증된 장인을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  select count(*) into n from public.influencer_follows where influencer_id = p_user;
  return jsonb_build_object(
    'follower_count', n, 'total', n, 'page', pg, 'size', sz,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object('id', u.id, 'nickname', u.nickname, 'influencer', u.influencer,
                                          'nickname_state', u.nickname_state, 'followed_at', x.created_at)
                       order by x.created_at desc, x.follower_id)
        from (select f.follower_id, f.created_at from public.influencer_follows f
               where f.influencer_id = p_user
               order by f.created_at desc, f.follower_id
               limit sz offset (pg - 1) * sz) x
        join public.profiles u on u.id = x.follower_id
    ), '[]'::jsonb));
end;
$$;

create function public.influencer_followers(p_user uuid, p_page integer default 1)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception '로그인하면 팔로워 목록을 볼 수 있습니다.' using errcode = '42501';
  end if;
  return public.influencer_followers_unchecked(p_user, p_page);
end;
$$;

-- 내가 팔로우한 장인. 최근 팔로우 순, 20개씩
-- 돌려주는 값: { total, page, size, items: [{ id, nickname, influencer, followed_at, follower_count }] }
create function public.my_following_unchecked(p_me uuid, p_page integer)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz constant integer := 20;
begin
  return jsonb_build_object(
    'total', (select count(*) from public.influencer_follows where follower_id = p_me),
    'page', pg, 'size', sz,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object('id', u.id, 'nickname', u.nickname, 'influencer', u.influencer, 'followed_at', x.created_at,
                                          'follower_count', (select count(*) from public.influencer_follows g where g.influencer_id = u.id))
                       order by x.created_at desc, x.influencer_id)
        from (select f.influencer_id, f.created_at from public.influencer_follows f
               where f.follower_id = p_me
               order by f.created_at desc, f.influencer_id
               limit sz offset (pg - 1) * sz) x
        join public.profiles u on u.id = x.influencer_id
    ), '[]'::jsonb));
end;
$$;

create function public.my_following(p_page integer default 1)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  return public.my_following_unchecked(me, p_page);
end;
$$;

-- 내가 팔로우한 장인들이 처음 만든 공개 빌드 (숨김/삭제 제외), 최근 수정순, 20개씩
-- 돌려주는 값: { total, page, size, items: [빌드 카드] }
create function public.followed_builds_unchecked(p_me uuid, p_page integer)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz constant integer := 20;
begin
  return (
    with fb as (
      select b.id, coalesce(b.updated_at, b.created_at) as t
        from public.influencer_follows f
        join public.profiles a on a.id = f.influencer_id and a.influencer is not null
        join public.builds b on b.author_id = f.influencer_id and b.status = 'approved'
        join public.counters c on c.id = b.counter_id and c.status = 'approved'
       where f.follower_id = p_me
    )
    select jsonb_build_object(
      'total', (select count(*) from fb),
      'page', pg, 'size', sz,
      'items', coalesce((
        select jsonb_agg(public.follow_build_card(x.id) order by x.t desc, x.id desc)
          from (select * from fb order by t desc, id desc limit sz offset (pg - 1) * sz) x
      ), '[]'::jsonb)));
end;
$$;

create function public.followed_builds(p_page integer default 1)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  return public.followed_builds_unchecked(me, p_page);
end;
$$;

-- 빌드 목록의 [+] 버튼 상태: 장인 id 여러 개 -> {"id": 내가 팔로우 중인가}. 장인이 아니거나 없는 id는 false. 한 번에 100명까지
create function public.follow_status_unchecked(p_me uuid, p_users uuid[])
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  if coalesce(cardinality(p_users), 0) > 100 then
    raise exception '한 번에 100명까지 확인할 수 있습니다.' using errcode = '22023';
  end if;
  return coalesce((
    select jsonb_object_agg(u::text, exists (
             select 1 from public.influencer_follows f join public.profiles p on p.id = f.influencer_id and p.influencer is not null
              where f.follower_id = p_me and f.influencer_id = u))
      from (select distinct x as u from unnest(p_users) x where x is not null) s
  ), '{}'::jsonb);
end;
$$;

create function public.follow_status(p_users uuid[])
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  return public.follow_status_unchecked(me, p_users);
end;
$$;

-- ---------------------------------------------------------------------
-- 6. 운영자 전용: 장인 목록 (운영자 모드를 끄면 거부 - require_operator)
-- ---------------------------------------------------------------------
-- 최근 인증 순. 돌려주는 값: { total, page, size, items: [{ id, nickname, influencer, kind_label, direct, influencer_at, follower_count }] }
-- direct는 049 칸을 to_jsonb로 읽는다 (049를 되돌려 칸이 없어도 false로 동작)
create function public.admin_influencer_list_unchecked(p_page integer, p_size integer)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz integer := least(greatest(coalesce(p_size, 20), 1), 50);
begin
  return jsonb_build_object(
    'total', (select count(*) from public.profiles where influencer is not null),
    'page', pg, 'size', sz,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', x.id, 'nickname', x.nickname, 'influencer', x.influencer,
               'kind_label', public.influencer_kind_label(x.influencer),
               'direct', coalesce((select (to_jsonb(a) ->> 'direct')::boolean from public.influencer_applications a
                                    where a.user_id = x.id and a.status = 'approved' order by a.id desc limit 1), false),
               'influencer_at', x.influencer_at,
               'follower_count', (select count(*) from public.influencer_follows f where f.influencer_id = x.id))
             order by x.influencer_at desc, x.id)
        from (select p.id, p.nickname, p.influencer, p.influencer_at from public.profiles p
               where p.influencer is not null
               order by p.influencer_at desc, p.id
               limit sz offset (pg - 1) * sz) x
    ), '[]'::jsonb));
end;
$$;

create function public.admin_influencer_list(p_page integer default 1, p_size integer default 20)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  return public.admin_influencer_list_unchecked(p_page, p_size);
end;
$$;

-- ---------------------------------------------------------------------
-- 7. 새 빌드 -> 알림 대기 줄 (트리거) -> 1분마다 나눠 보내기 (pg_cron follow-notify)
-- ---------------------------------------------------------------------
-- 새 빌드(바로 공개) 또는 승인 대기에서 처음 공개될 때만. 수정/숨김/다시 공개(hidden -> approved)는 넣지 않는다.
-- 작성자가 지금 장인이고, 상대법이 공개 중이고, 팔로워가 있을 때만 한 줄
create function public.follow_queue_on_build()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.status <> 'approved' or new.author_id is null then
    return null;
  end if;
  if tg_op = 'UPDATE' and old.status is distinct from 'pending' then
    return null;
  end if;
  if exists (select 1 from public.profiles p where p.id = new.author_id and p.influencer is not null)
     and exists (select 1 from public.counters c where c.id = new.counter_id and c.status = 'approved')
     and exists (select 1 from public.influencer_follows f where f.influencer_id = new.author_id) then
    insert into public.follow_notify_queue (build_id, influencer_id) values (new.id, new.author_id)
    on conflict (build_id) do nothing;
  end if;
  return null;
end;
$$;
create trigger builds_follow_notify
  after insert or update of status on public.builds
  for each row execute function public.follow_queue_on_build();

-- 대기 줄을 팔로워에게 보낸다. 한 번에 최대 p_limit(기본 1000)명. 돌려주는 값: 개수만
--   new: 새 알림(휴대폰 알림 감) / merged: 3시간 안이라 보낸 알림을 고침(휴대폰 알림 안 감) / dropped: 버린 대기 줄 / left: 남은 대기 줄
create function public.follow_notify_dispatch(p_limit integer default 1000)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  budget integer := least(greatest(coalesce(p_limit, 1000), 1), 5000);
  merge_window constant interval := interval '3 hours';
  stale_after constant interval := interval '1 day';
  e record;
  f record;
  b record;
  nick text;
  nid bigint;
  took integer;
  cap integer;
  last_f uuid;
  n_new integer := 0;
  n_merged integer := 0;
  n_dropped integer := 0;
begin
  -- 두 번 겹쳐 돌지 않게 (앞의 실행이 끝나지 않았으면 이번 실행은 그냥 끝)
  if not pg_try_advisory_xact_lock(hashtext('follow_notify_dispatch')) then
    return jsonb_build_object('new', 0, 'merged', 0, 'dropped', 0, 'left', -1, 'skipped', true);
  end if;
  for e in select * from public.follow_notify_queue order by id loop
    exit when budget <= 0;
    select bb.id, bb.counter_id, bb.author_id, a.nickname into b
      from public.builds bb
      join public.counters c on c.id = bb.counter_id and c.status = 'approved'
      join public.profiles a on a.id = bb.author_id and a.influencer is not null
     where bb.id = e.build_id and bb.status = 'approved' and bb.author_id = e.influencer_id;
    if not found or e.created_at < now() - stale_after then
      delete from public.follow_notify_queue where id = e.id;  -- 숨겨짐/작성자가 장인이 아님/너무 오래됨 -> 보내지 않음
      n_dropped := n_dropped + 1;
      continue;
    end if;
    nick := b.nickname;
    cap := budget;
    took := 0;
    last_f := e.after_follower;
    for f in select ff.follower_id, ff.last_notified_at, ff.notify_count, ff.notification_id
               from public.influencer_follows ff
              where ff.influencer_id = e.influencer_id and ff.follower_id <> b.author_id
                and (e.after_follower is null or ff.follower_id > e.after_follower)
              order by ff.follower_id
              limit cap
              for update of ff loop
      if f.last_notified_at > now() - merge_window and f.notification_id is not null
         and exists (select 1 from public.notifications n where n.id = f.notification_id) then
        update public.notifications
           set message = format('팔로우한 장인 %s의 새 빌드가 %s개 올라왔습니다.', nick, f.notify_count + 1),
               build_id = b.id, counter_id = b.counter_id, read_at = null
         where id = f.notification_id;
        update public.influencer_follows set notify_count = notify_count + 1
         where follower_id = f.follower_id and influencer_id = e.influencer_id;
        n_merged := n_merged + 1;
      else
        insert into public.notifications (user_id, kind, message, counter_id, build_id)
        values (f.follower_id, 'followed_build_created', format('팔로우한 장인 %s의 새 빌드가 올라왔습니다.', nick), b.counter_id, b.id)
        returning id into nid;
        update public.influencer_follows set last_notified_at = now(), notify_count = 1, notification_id = nid
         where follower_id = f.follower_id and influencer_id = e.influencer_id;
        n_new := n_new + 1;
      end if;
      last_f := f.follower_id;
      took := took + 1;
    end loop;
    budget := budget - took;
    if took < cap then
      delete from public.follow_notify_queue where id = e.id;  -- 이 빌드는 다 보냄
    else
      update public.follow_notify_queue set after_follower = last_f where id = e.id;  -- 다음 실행에서 이어서
    end if;
  end loop;
  return jsonb_build_object('new', n_new, 'merged', n_merged, 'dropped', n_dropped,
                            'left', (select count(*) from public.follow_notify_queue));
end;
$$;

-- ---------------------------------------------------------------------
-- 8. 장인 인증이 끝나면 팔로우를 바로 지운다 (해제 등 profiles.influencer가 비워지는 모든 길. 탈퇴/게스트 정리는 cascade)
-- ---------------------------------------------------------------------
create function public.follows_on_influencer_end()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.influencer_follows where influencer_id = new.id;
  delete from public.follow_notify_queue where influencer_id = new.id;
  return null;
end;
$$;
create trigger follows_on_influencer_end
  after update of influencer on public.profiles
  for each row when (old.influencer is not null and new.influencer is null)
  execute function public.follows_on_influencer_end();

-- ---------------------------------------------------------------------
-- 9. 권한
--   비로그인(anon)도: search_influencers, influencer_builds, influencer_follower_count
--   로그인(authenticated, 게스트 포함)만: follow_influencer, unfollow_influencer, influencer_followers, my_following,
--                                        followed_builds, follow_status, admin_influencer_list(운영자인지는 함수 안에서)
--   아무도 직접 못 부름: _unchecked 함수 전부, 도우미, 트리거 함수, follow_notify_dispatch(pg_cron만)
-- ---------------------------------------------------------------------
revoke execute on function public.follow_build_card(bigint) from public, anon, authenticated;
revoke execute on function public.follow_throttle(uuid) from public, anon, authenticated;
revoke execute on function public.follow_queue_on_build() from public, anon, authenticated;
revoke execute on function public.follow_notify_dispatch(integer) from public, anon, authenticated;
revoke execute on function public.follows_on_influencer_end() from public, anon, authenticated;
revoke execute on function public.follow_influencer_unchecked(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.unfollow_influencer_unchecked(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.influencer_followers_unchecked(uuid, integer) from public, anon, authenticated;
revoke execute on function public.my_following_unchecked(uuid, integer) from public, anon, authenticated;
revoke execute on function public.followed_builds_unchecked(uuid, integer) from public, anon, authenticated;
revoke execute on function public.follow_status_unchecked(uuid, uuid[]) from public, anon, authenticated;
revoke execute on function public.admin_influencer_list_unchecked(integer, integer) from public, anon, authenticated;

revoke execute on function public.follow_influencer(uuid) from public, anon;
revoke execute on function public.unfollow_influencer(uuid) from public, anon;
revoke execute on function public.influencer_followers(uuid, integer) from public, anon;
revoke execute on function public.my_following(integer) from public, anon;
revoke execute on function public.followed_builds(integer) from public, anon;
revoke execute on function public.follow_status(uuid[]) from public, anon;
revoke execute on function public.admin_influencer_list(integer, integer) from public, anon;
grant execute on function public.follow_influencer(uuid) to authenticated;
grant execute on function public.unfollow_influencer(uuid) to authenticated;
grant execute on function public.influencer_followers(uuid, integer) to authenticated;
grant execute on function public.my_following(integer) to authenticated;
grant execute on function public.followed_builds(integer) to authenticated;
grant execute on function public.follow_status(uuid[]) to authenticated;
grant execute on function public.admin_influencer_list(integer, integer) to authenticated;  -- 운영자인지는 함수 안에서

revoke execute on function public.search_influencers(text, integer) from public;
revoke execute on function public.influencer_builds(text, integer) from public;
revoke execute on function public.influencer_follower_count(text) from public;
grant execute on function public.search_influencers(text, integer) to anon, authenticated;
grant execute on function public.influencer_builds(text, integer) to anon, authenticated;
grant execute on function public.influencer_follower_count(text) to anon, authenticated;

commit;

-- 확인 (실행 뒤): supabase/scripts/check_follow.sql
-- pg_cron 일정 등록 (실행 뒤 따로 한 번):
--   select cron.schedule('follow-notify', '* * * * *', $$select public.follow_notify_dispatch()$$);
