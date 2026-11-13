-- =====================================================================
-- 050(장인 팔로우) 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 050 실행 "전"과 "후"에 같은 파일을 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
-- [지금 값]이 [실행 전 정상]/[실행 후 정상]과 맞는지 본다.
--   - 1~5번(기준값): 경험치 129 / 129, 설정값 63은 고정값이다.
--     레벨 합계/칭호 수, 알림 수, 처리 기록/공개 빌드/공개 상대법 수는 사이트를 쓰면 늘 수 있으므로
--     "실행 전에 나온 값"을 적어 두고, 실행 후 값이 그것과 같은지 본다. 050은 기존 데이터를 바꾸지 않는다.
--   - 21번(pg_cron 일정)은 일정 등록 SQL을 따로 실행한 뒤에 1이 된다. 등록 뒤 이 파일을 한 번 더 실행해 확인한다.
--   - 실행 뒤 값이 "실행 후 정상"과 다르면 바로 알려 주세요.
-- (SQL Editor는 로그인한 회원이 아니라서 함수를 직접 부르는 검사는 못 한다 - 표/함수 정의/권한만 본다)
-- 050이 만드는 표/칸이 아직 없을 때(실행 전)도 오류 없이 돌도록, 그것을 읽는 곳은 to_regclass/query_to_xml로 감쌌다.
-- =====================================================================
with fn as (
  select p.oid, p.proname, p.prosrc
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
),
new_tabs as (
  select c.oid, c.relname, c.relrowsecurity
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname in ('influencer_follows', 'follow_rate', 'follow_notify_queue') and c.relkind = 'r'
),
con as (
  select conname, pg_get_constraintdef(oid) as def from pg_constraint
  where conrelid = 'public.notifications'::regclass
),
anon_fns as (
  select string_agg(proname, ', ' order by proname) as names from fn
  where has_function_privilege('anon', oid, 'execute')
    and (proname in ('search_influencers', 'influencer_builds', 'influencer_follower_count', 'follow_influencer', 'unfollow_influencer',
                     'influencer_followers', 'my_following', 'followed_builds', 'follow_status', 'admin_influencer_list',
                     'follow_notify_dispatch', 'follow_build_card', 'follow_throttle', 'follow_queue_on_build', 'follows_on_influencer_end')
         or proname like '%follow%unchecked' or proname = 'admin_influencer_list_unchecked')
),
auth_fns as (
  select string_agg(proname, ', ' order by proname) as names from fn
  where has_function_privilege('authenticated', oid, 'execute')
    and (proname in ('search_influencers', 'influencer_builds', 'influencer_follower_count', 'follow_influencer', 'unfollow_influencer',
                     'influencer_followers', 'my_following', 'followed_builds', 'follow_status', 'admin_influencer_list',
                     'follow_notify_dispatch', 'follow_build_card', 'follow_throttle', 'follow_queue_on_build', 'follows_on_influencer_end')
         or proname like '%follow%unchecked' or proname = 'admin_influencer_list_unchecked')
),
inner_fns as (
  select count(*) as n,
         bool_or(has_function_privilege('anon', oid, 'execute') or has_function_privilege('authenticated', oid, 'execute')) as callable
  from fn
  where proname like '%follow%unchecked' or proname in ('admin_influencer_list_unchecked', 'follow_notify_dispatch', 'follow_build_card',
                                                         'follow_throttle', 'follow_queue_on_build', 'follows_on_influencer_end')
)
select ord as "순서", what as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상", memo as "메모"
from (
  select 1 as ord, '기준값: 경험치 합계 (프로필 xp 합 / 경험치 기록 합)' as what,
    (select coalesce(sum(xp), 0)::text from public.profiles) || ' / ' || (select coalesce(sum(amount), 0)::text from public.xp_events) as now_value,
    '129 / 129' as before_ok, '129 / 129' as after_ok, '고정값' as memo
  union all select 2, '기준값: 레벨 합계 / 칭호 수',
    (select coalesce(sum(level), 0)::text from public.profiles) || ' / ' || (select count(*)::text from public.user_titles),
    '(이 값을 적어 둠)', '실행 전과 같음', '사이트 사용으로 늘 수 있음 - 실행 전 값과 비교'
  union all select 3, '기준값: 알림 수', (select count(*)::text from public.notifications),
    '(이 값을 적어 둠)', '실행 전과 같음', '사이트 사용으로 늘 수 있음 - 실행 전 값과 비교'
  union all select 4, '기준값: 처리 기록 수 / 공개 빌드 수 / 공개 상대법 수',
    (select count(*)::text from public.moderation_log) || ' / ' || (select count(*)::text from public.builds where status = 'approved')
      || ' / ' || (select count(*)::text from public.counters where status = 'approved'),
    '(이 값을 적어 둠)', '실행 전과 같음', '사이트 사용으로 늘 수 있음 - 실행 전 값과 비교'
  union all select 5, '기준값: 설정값 수 (xp_rules)', (select count(*)::text from public.xp_rules), '63', '63', '고정값. 050은 설정값을 더하지 않는다'
  union all select 6, '049까지 실행됨 (신청 표에 직접 지정 칸 direct)',
    exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'influencer_applications' and column_name = 'direct')::text,
    'true', 'true', 'false면 049부터 실행'
  union all select 7, '새 표 3개 (팔로우 / 호출 횟수 / 알림 대기 줄)', (select count(*)::text from new_tabs), '0', '3', ''
  union all select 8, '새 표 RLS 켜짐 수 / 새 표 정책 수',
    (select count(*) filter (where relrowsecurity)::text from new_tabs) || ' / '
      || (select count(*)::text from pg_policy where polrelid in (select oid from new_tabs)),
    '0 / 0', '3 / 0', '정책 없음 = 직접 읽기/쓰기 불가, 함수로만'
  union all select 9, '새 표를 로그인 사용자/비로그인이 직접 읽거나 쓸 수 있나',
    coalesce((select bool_or(has_table_privilege(r, t.oid, p))::text
                from new_tabs t, unnest(array['anon', 'authenticated']) r, unnest(array['select', 'insert', 'update', 'delete']) p), '표 없음'),
    '표 없음', 'false', ''
  union all select 10, '알림 종류: followed_build_created / link_removed (그대로)',
    (select (def like '%followed_build_created%')::text || ' / ' || (def like '%link_removed%')::text from con where conname = 'notifications_kind_check'),
    'false / true', 'true / true', ''
  union all select 11, '푸시 묶음: 새 빌드 알림 / 장인 링크 삭제(그대로) / 장인 신청(그대로)',
    coalesce(public.push_group('followed_build_created'), '없음') || ' / ' || coalesce(public.push_group('link_removed'), '없음')
      || ' / ' || coalesce(public.push_group('influencer_applied'), '없음'),
    '없음 / my_results / staff_new', 'follow_builds / my_results / staff_new', ''
  union all select 12, '푸시 설정 칸 follow_builds (기본 켜짐) / 본인이 바꿀 수 있나',
    coalesce((select column_default || ' / ' || has_column_privilege('authenticated', 'public.push_settings', 'follow_builds', 'update')::text
                from information_schema.columns
               where table_schema = 'public' and table_name = 'push_settings' and column_name = 'follow_builds'), '칸 없음'),
    '칸 없음', 'true / true', '설정 줄이 있는 사람은 모두 켜짐으로 시작'
  union all select 13, '푸시 보낼지 판단(push_wanted)이 follow_builds 칸을 봄',
    coalesce((select (prosrc like '%follow_builds%')::text from fn where proname = 'push_wanted'), '없음'), 'false', 'true', ''
  union all select 14, '비로그인이 부를 수 있는 050 함수', coalesce((select names from anon_fns), '없음'),
    '없음', 'influencer_builds, influencer_follower_count, search_influencers', '장인 검색 / 공개 빌드 / 팔로워 수만'
  union all select 15, '로그인 사용자(게스트 포함)가 부를 수 있는 050 함수', coalesce((select names from auth_fns), '없음'),
    '없음', 'admin_influencer_list, follow_influencer, follow_status, followed_builds, influencer_builds, influencer_follower_count, influencer_followers, my_following, search_influencers, unfollow_influencer',
    '운영자 장인 목록은 함수 안에서 운영자만'
  union all select 16, '안쪽 함수(_unchecked)/도우미/트리거 함수/알림 보내기 수 / 로그인 사용자/비로그인이 부를 수 있나',
    (select n::text || ' / ' || coalesce(callable::text, '-') from inner_fns), '0 / -', '12 / false', 'pg_cron만 알림 보내기를 부른다'
  union all select 17, '운영자 장인 목록 admin_influencer_list: 운영자 전용 확인(require_operator)',
    coalesce((select (prosrc like '%require_operator()%')::text from fn where proname = 'admin_influencer_list'), '없음'), '없음', 'true',
    '감독관 거부, 운영자 모드 꺼짐 거부'
  union all select 18, '트리거: 새 빌드 -> 대기 줄 / 장인 해제 -> 팔로우 삭제 / 링크 삭제(047, 그대로)',
    exists (select 1 from pg_trigger where tgname = 'builds_follow_notify')::text || ' / '
      || exists (select 1 from pg_trigger where tgname = 'follows_on_influencer_end')::text || ' / '
      || exists (select 1 from pg_trigger where tgname = 'ext_links_on_influencer_end')::text,
    'false / false / true', 'true / true / true', ''
  union all select 19, '읽기 정책 / 모두 읽음이 새 알림을 운영진 알림으로 가리지 않음',
    coalesce((select (pg_get_expr(polqual, polrelid) not like '%followed_build_created%')::text from pg_policy
               where polrelid = 'public.notifications'::regclass and polname = 'notifications: 본인 읽기'), '정책 없음') || ' / '
      || coalesce((select (prosrc not like '%followed_build_created%')::text from fn where proname = 'mark_all_notifications_read'), '없음'),
    'true / true', 'true / true', '받는 사람 본인 알림 = 운영자 모드와 관계없이 보이고 모두 읽음에 함께 처리'
  union all select 20, '팔로우 수 / 알림 대기 줄 수',
    case when to_regclass('public.influencer_follows') is null then '표 없음'
         else (xpath('/row/c/text()', query_to_xml(
                 'select (select count(*) from public.influencer_follows)::text || '' / '' || (select count(*) from public.follow_notify_queue)::text as c',
                 false, true, '')))[1]::text end,
    '표 없음', '0 / 0', '실행 직후 기준. 화면이 생기면 늘어남'
  union all select 21, 'pg_cron 일정 follow-notify (1분마다 알림 나눠 보내기)',
    case when to_regclass('cron.job') is null then 'pg_cron 없음'
         else (xpath('/row/c/text()', query_to_xml(
                 'select count(*) as c from cron.job where jobname = ''follow-notify''', false, true, '')))[1]::text end,
    '0', '0 (일정 등록 뒤 1)', '050 맨 위의 등록 SQL을 따로 실행하면 1'
) x
order by ord;
