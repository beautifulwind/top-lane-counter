-- =====================================================================
-- 052(장인 새 팔로워 알림 - 하루 묶음) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 052를 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - [지금 값]이 [정상 값]과 모두 맞으면 052를 실행해도 된다. 하나라도 다르면 실행하지 말고 알려 주세요.
--   - 8~10번은 "적어 둘 값"이다. 052 실행 뒤 check_new_followers_after.sql의 같은 줄과 비교한다.
--   - 11번: 052 실행 뒤 첫 하루 묶음은 "지난 25시간 안의 팔로우"만 센다. 그보다 오래된 팔로우는 알림으로 쏟아지지 않는다.
-- 052가 만드는 표/칸이 아직 없어도 오류 없이 돌도록 to_regclass/information_schema만 쓴다.
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
  select 1 as ord, '051까지 실행됨 (글의 공지 칸 posts.is_notice)' as what,
    exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'posts' and column_name = 'is_notice')::text as now_value,
    'true' as ok_value, 'false면 051부터 실행' as memo
  union all select 2, '052 아직 안 함: 센 기록 표 new_follower_counted',
    (to_regclass('public.new_follower_counted') is not null)::text, 'false', 'true면 이미 실행한 것 - 다시 실행하지 말 것'
  union all select 3, '052 아직 안 함: 알림 종류 new_followers / 있던 종류 notice_posted',
    (select (def like '%new_followers%')::text || ' / ' || (def like '%notice_posted%')::text from con),
    'false / true', ''
  union all select 4, '052 아직 안 함: 푸시 설정 칸 new_followers / 있던 칸 notice',
    exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'push_settings' and column_name = 'new_followers')::text || ' / '
      || exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'push_settings' and column_name = 'notice')::text,
    'false / true', ''
  union all select 5, '052 아직 안 함: 함수 new_follower_digest / 트리거 new_follower_counted_on_influencer_end',
    exists (select 1 from fn where proname = 'new_follower_digest')::text || ' / '
      || exists (select 1 from pg_trigger where tgname = 'new_follower_counted_on_influencer_end')::text,
    'false / false', ''
  union all select 6, '지금 푸시 묶음 (새 팔로워 = 없음 / 공지 / 팔로우 새 빌드)',
    coalesce(public.push_group('new_followers'), '없음') || ' / ' || coalesce(public.push_group('notice_posted'), '없음')
      || ' / ' || coalesce(public.push_group('followed_build_created'), '없음'),
    '없음 / notice / follow_builds', ''
  union all select 7, '장인 인증 해제 때 팔로우 지우는 트리거(050) 있음', exists (select 1 from pg_trigger where tgname = 'follows_on_influencer_end')::text,
    'true', ''
  union all select 8, '적어 둘 값: 인증된 장인 수 / 팔로우 수',
    (select count(*)::text from public.profiles where influencer is not null) || ' / ' || (select count(*)::text from public.influencer_follows),
    '(이 값을 적어 둠)', '052는 팔로우를 바꾸지 않는다'
  union all select 9, '적어 둘 값: 알림 수', (select count(*)::text from public.notifications), '(이 값을 적어 둠)', '사이트 사용으로 늘 수 있음'
  union all select 10, '적어 둘 값: 푸시 설정 줄 수', (select count(*)::text from public.push_settings), '(이 값을 적어 둠)', ''
  union all select 11, '참고: 지난 25시간 안의 팔로우 수 (첫 하루 묶음에서 셀 수 있는 최대)',
    (select count(*)::text from public.influencer_follows where created_at > now() - interval '25 hours'), '(참고)', ''
  union all select 12, '설정값 수 (xp_rules)', (select count(*)::text from public.xp_rules), '63', '052는 설정값을 더하지 않는다'
  union all select 13, 'pg_cron 사용 가능 / 051 일정 notice-notify / 052 일정 new-follower-digest',
    case when to_regclass('cron.job') is null then 'pg_cron 없음'
         else 'true / ' || (xpath('/row/c/text()', query_to_xml(
                'select (select count(*) from cron.job where jobname = ''notice-notify'')::text || '' / ''
                     || (select count(*) from cron.job where jobname = ''new-follower-digest'')::text as c', false, true, '')))[1]::text end,
    'true / 1 / 0', 'notice-notify가 0이면 051 일정 등록부터'
) x
order by ord;
