-- =====================================================================
-- 051(공지 + 공지 알림) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 051을 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - [지금 값]이 [정상 값]과 모두 맞으면 051을 실행해도 된다. 하나라도 다르면 실행하지 말고 알려 주세요.
--   - 8~10번(가입자 수/알림 수/글 수)은 "적어 둘 값"이다. 051 실행 뒤 check_notice_after.sql의 같은 줄과 비교한다.
-- 051이 만드는 표/칸이 아직 없어도 오류 없이 돌도록 to_regclass/information_schema만 쓴다.
-- =====================================================================
with fn as (
  select p.oid, p.proname, p.prosrc
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
),
con as (
  select pg_get_constraintdef(oid) as def from pg_constraint
  where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '050까지 실행됨 (장인 팔로우 표 influencer_follows)' as what,
    (to_regclass('public.influencer_follows') is not null)::text as now_value, 'true' as ok_value, 'false면 050부터 실행' as memo
  union all select 2, '051 아직 안 함: 글의 공지 칸 posts.is_notice',
    exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'posts' and column_name = 'is_notice')::text,
    'false', 'true면 이미 실행한 것 - 다시 실행하지 말 것'
  union all select 3, '051 아직 안 함: 공지 알림 대기 줄 표 notice_notify_queue',
    (to_regclass('public.notice_notify_queue') is not null)::text, 'false', ''
  union all select 4, '051 아직 안 함: 알림 종류 notice_posted / 있던 종류 followed_build_created',
    (select (def like '%notice_posted%')::text || ' / ' || (def like '%followed_build_created%')::text from con),
    'false / true', ''
  union all select 5, '051 아직 안 함: 푸시 설정 칸 notice / 있던 칸 follow_builds',
    exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'push_settings' and column_name = 'notice')::text || ' / '
      || exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'push_settings' and column_name = 'follow_builds')::text,
    'false / true', ''
  union all select 6, '051 아직 안 함: 함수 create_notice / notice_notify_dispatch',
    exists (select 1 from fn where proname = 'create_notice')::text || ' / ' || exists (select 1 from fn where proname = 'notice_notify_dispatch')::text,
    'false / false', ''
  union all select 7, '지금 푸시 묶음 (공지 = 없음 / 팔로우 새 빌드 / 장인 링크)',
    coalesce(public.push_group('notice_posted'), '없음') || ' / ' || coalesce(public.push_group('followed_build_created'), '없음')
      || ' / ' || coalesce(public.push_group('link_removed'), '없음'),
    '없음 / follow_builds / my_results', ''
  union all select 8, '적어 둘 값: 가입자 수 (정식 회원 + 게스트, 공지 알림을 받을 수 있는 계정)',
    (select count(*)::text from public.profiles) || ' (게스트 ' || (select count(*)::text from public.profiles where is_guest) || ')',
    '(이 값을 적어 둠)', '051은 계정을 바꾸지 않는다'
  union all select 9, '적어 둘 값: 알림 수', (select count(*)::text from public.notifications), '(이 값을 적어 둠)', '사이트 사용으로 늘 수 있음'
  union all select 10, '적어 둘 값: 글 수 (지운 글 제외)', (select count(*)::text from public.posts where deleted_at is null),
    '(이 값을 적어 둠)', '사이트 사용으로 늘 수 있음'
  union all select 11, '운영자 계정 수 (공지를 쓸 수 있는 계정)', (select count(*)::text from public.profiles where role = 'admin'), '1', ''
  union all select 12, '설정값 수 (xp_rules)', (select count(*)::text from public.xp_rules), '63', '051은 설정값을 더하지 않는다'
  union all select 13, 'pg_cron 사용 가능 / 050 일정 follow-notify / 051 일정 notice-notify',
    case when to_regclass('cron.job') is null then 'pg_cron 없음'
         else 'true / ' || (xpath('/row/c/text()', query_to_xml(
                'select (select count(*) from cron.job where jobname = ''follow-notify'')::text || '' / ''
                     || (select count(*) from cron.job where jobname = ''notice-notify'')::text as c', false, true, '')))[1]::text end,
    'true / 1 / 0', 'pg_cron 없음이면 Database > Extensions에서 pg_cron을 켠다'
) x
order by ord;
