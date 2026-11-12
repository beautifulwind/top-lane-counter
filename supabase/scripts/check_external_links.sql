-- =====================================================================
-- 047(장인 외부 링크 + 공개 프로필) 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 047 실행 "전"과 "후"에 같은 파일을 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
-- [지금 값]이 [실행 전 정상]/[실행 후 정상]과 맞는지 본다.
--   - 1~5번(기준값)은 실행 전 값을 적어 두었다가 실행 후 값과 같은지 본다. 047은 기존 데이터를 바꾸지 않는다.
--     지금 기준값(2026-11-12): 경험치 129 / 129, 레벨 합계 / 칭호 수 8 / 3, 알림 24, 처리 기록 / 공개 빌드 / 공개 상대법 7 / 2 / 2, 설정값 62.
--     설정값만 047 뒤에 1 늘어난다(62 -> 63, influencer_profile_links_max). 새 알림 종류는 없다.
--   - 실행 뒤 값이 "실행 후 정상"과 다르면 바로 알려 주세요.
-- (SQL Editor는 운영자 계정이 아니라서 함수를 직접 부르는 검사는 못 한다 - 표/함수 정의/권한/설정값만 본다)
-- =====================================================================
with fn as (
  select p.oid, p.proname, p.prosrc
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
),
kindcheck as (
  select pg_get_constraintdef(oid) as def from pg_constraint
  where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass
),
actcheck as (
  select pg_get_constraintdef(oid) as def from pg_constraint
  where conname = 'moderation_log_action_check' and conrelid = 'public.moderation_log'::regclass
),
tkcheck as (
  select pg_get_constraintdef(oid) as def from pg_constraint
  where conname = 'moderation_log_target_kind_check' and conrelid = 'public.moderation_log'::regclass
),
tbl (t) as (values ('link_domains'), ('ext_links'), ('link_reports')),
user_fns (f) as (
  values ('set_profile_links'), ('set_build_link'), ('my_links'), ('report_link'), ('admin_link_reports'),
         ('dismiss_link_reports'), ('remove_link'), ('admin_add_link_domain'), ('admin_remove_link_domain')
),
inner_fns (f) as (
  values ('ext_link_parse'), ('ext_link_visible'), ('ext_link_json'), ('notify_staff_new_link_report'), ('ext_links_on_influencer_end'),
         ('admin_link_reports_unchecked'), ('dismiss_link_reports_unchecked'), ('remove_link_unchecked'),
         ('admin_add_link_domain_unchecked'), ('admin_remove_link_domain_unchecked')
)
select ord as "순서", what as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상", memo as "메모"
from (
  select 1 as ord, '기준값: 경험치 합계 (프로필 xp 합 / 경험치 기록 합)' as what,
    (select coalesce(sum(xp), 0)::text from public.profiles) || ' / ' || (select coalesce(sum(amount), 0)::text from public.xp_events) as now_value,
    '129 / 129' as before_ok, '실행 전과 같음' as after_ok, '047은 경험치를 바꾸지 않는다' as memo
  union all select 2, '기준값: 레벨 합계 / 칭호 수',
    (select coalesce(sum(level), 0)::text from public.profiles) || ' / ' || (select count(*)::text from public.user_titles), '8 / 3', '실행 전과 같음', ''
  union all select 3, '기준값: 알림 수', (select count(*)::text from public.notifications), '24', E'실행 전과 같음',
    E'실행 직후 기준. 그 뒤 사이트 사용으로 늘어날 수 있음'
  union all select 4, '기준값: 처리 기록 수 / 공개 빌드 수 / 공개 상대법 수',
    (select count(*)::text from public.moderation_log) || ' / ' || (select count(*)::text from public.builds where status = 'approved')
      || ' / ' || (select count(*)::text from public.counters where status = 'approved'), '7 / 2 / 2', '실행 전과 같음', ''
  union all select 5, '기준값: 설정값 수 (xp_rules)', (select count(*)::text from public.xp_rules), '62', '63 (실행 전 + 1)',
    'influencer_profile_links_max 1개'
  union all select 6, E'새 표 있음 (허용 사이트 / 링크 / 링크 신고)',
    (select string_agg(case when to_regclass('public.' || t) is null then '0' else '1' end, ' / ' order by
       case t when 'link_domains' then 1 when 'ext_links' then 2 else 3 end) from tbl),
    '0 / 0 / 0', '1 / 1 / 1', ''
  union all select 7, E'새 표 RLS 켜짐 (허용 사이트 / 링크 / 링크 신고)',
    (select string_agg(coalesce((select relrowsecurity::text from pg_class where oid = to_regclass('public.' || t)), '-'), ' / ' order by
       case t when 'link_domains' then 1 when 'ext_links' then 2 else 3 end) from tbl),
    '- / - / -', 'true / true / true', E'링크 표는 주인\u00B7운영자만, 신고 표는 운영자만 읽음'
  union all select 8, E'새 표에 로그인 사용자\u00B7비로그인 쓰기 권한 (false여야 함)',
    case when to_regclass('public.ext_links') is null then '-'
         else (select bool_or(has_table_privilege(r, 'public.' || t, pr))::text
                 from tbl, (values ('authenticated'), ('anon')) rr(r), (values ('insert'), ('update'), ('delete')) pp(pr)) end,
    '-', 'false', E'쓰기는 함수로만'
  union all select 9, E'비로그인이 링크 표\u00B7신고 표를 읽을 수 있나 (false여야 함)',
    case when to_regclass('public.ext_links') is null then '-'
         else (has_table_privilege('anon', 'public.ext_links', 'select') or has_table_privilege('anon', 'public.link_reports', 'select'))::text end,
    '-', 'false', E'허용 사이트 표만 누구나 읽음'
  union all select 10, E'허용 사이트 (수 / 목록)',
    case when to_regclass('public.link_domains') is null then '-'
         else (xpath('/row/c/text()', query_to_xml(
                 'select count(*) || '' / '' || string_agg(domain, '', '' order by domain) as c from public.link_domains', false, true, '')))[1]::text end,
    '-', '9 / afreecatv.com, chzzk.naver.com, instagram.com, sooplive.co.kr, twitch.tv, twitter.com, x.com, youtu.be, youtube.com', ''
  union all select 11, E'처리 기록 종류 (링크 삭제\u00B7사이트 더하기\u00B7사이트 빼기 / 대상 link\u00B7link_domain)',
    (select (def like '%remove_link%' and def like '%add_link_domain%' and def like '%remove_link_domain%')::text from actcheck) || ' / '
      || (select (def like '%''link''%' and def like '%link_domain%')::text from tkcheck),
    'false / false', 'true / true', E'046 종류(장인 심사 등)도 그대로'
  union all select 12, E'처리 기록 종류: 046까지의 종류가 그대로 있음',
    (select (def like '%approve_influencer%' and def like '%rename_member%' and def like '%dismiss_reports%' and def like '%revert%')::text from actcheck)
      || ' / ' || (select (def like '%influencer_application%' and def like '%wiki_report%')::text from tkcheck),
    'true / true', 'true / true', ''
  union all select 13, E'알림 종류: link_removed\u00B7report_received 있음 / 047이 더한 종류 수',
    (select (def like '%link_removed%' and def like '%report_received%')::text from kindcheck) || ' / 0',
    'true / 0', 'true / 0', E'알림 종류는 046\u00B7045 그대로 (새 종류 없음)'
  union all select 14, E'푸시 묶음: 링크 삭제 / 새 신고 (그대로)',
    coalesce(public.push_group('link_removed'), '안 보냄') || ' / ' || coalesce(public.push_group('report_received'), '안 보냄'),
    'my_results / staff_new', 'my_results / staff_new', ''
  union all select 15, E'트리거: 인증 해제 때 링크 지우기 / 링크 신고 알림',
    (select count(*)::text from pg_trigger where tgname = 'ext_links_on_influencer_end' and not tgisinternal) || ' / '
      || (select count(*)::text from pg_trigger where tgname = 'link_reports_notify_staff' and not tgisinternal),
    '0 / 0', '1 / 1', ''
  union all select 16, E'로그인 사용자가 부를 수 있는 새 함수 (장인 링크 3\u00B7신고 1\u00B7운영자 5 - 장인/운영자인지는 함수 안에서)',
    (select count(*)::text from fn join user_fns on f = proname where has_function_privilege('authenticated', oid, 'execute')), '0', '9', ''
  union all select 17, E'비로그인이 부를 수 있는 함수 (공개 프로필\u00B7빌드 링크 2개만)',
    (select count(*)::text from fn where proname in ('public_profile', 'build_links') and has_function_privilege('anon', oid, 'execute')) || ' / '
      || (select count(*)::text from fn join user_fns on f = proname where has_function_privilege('anon', oid, 'execute')),
    '0 / 0', '2 / 0', E'둘째 수 = 비로그인이 부를 수 있는 링크 쓰기\u00B7운영자 함수 (0이어야 함)'
  union all select 18, E'안쪽 함수를 로그인 사용자\u00B7비로그인이 부를 수 있나 (0이어야 함)',
    (select count(*)::text from fn join inner_fns on f = proname
      where has_function_privilege('authenticated', oid, 'execute') or has_function_privilege('anon', oid, 'execute')), '0', '0', ''
  union all select 19, E'운영자 함수가 운영자 확인을 함 (require_operator가 든 바깥 함수 수)',
    (select count(*)::text from fn where proname in ('admin_link_reports', 'dismiss_link_reports', 'remove_link', 'admin_add_link_domain',
       'admin_remove_link_domain') and prosrc like '%require_operator()%'), '0', '5', E'감독관은 링크를 처리하지 못함'
  union all select 20, E'공개 프로필이 돌려주는 칸에 이메일\u00B7라이엇 닉네임\u00B7신청 정보가 없음',
    coalesce((select (prosrc not like '%email%' and prosrc not like '%riot%' and prosrc not like '%influencer_applications%')::text
                from fn where proname = 'public_profile'), '-'), '-', 'true', E'id\u00B7닉네임\u00B7장인 유형\u00B7링크\u00B7최근 빌드만'
  union all select 21, E'설정값: 프로필 링크 수 한도',
    coalesce((select value::text from public.xp_rules where key = 'influencer_profile_links_max'), '-'), '-', '5', E'빌드 링크는 빌드마다 1개 (표 규칙)'
  union all select 22, E'링크 수 / 링크 신고 수',
    case when to_regclass('public.ext_links') is null then '-'
         else (xpath('/row/c/text()', query_to_xml(
                 'select (select count(*) from public.ext_links) || '' / '' || (select count(*) from public.link_reports) as c', false, true, '')))[1]::text end,
    '-', E'0 / 0 (실행 직후)', E'링크를 올리는 화면은 다음 차례라 그전에는 늘지 않는다'
  union all select 23, E'046 기능 그대로: 장인 수 / 처리 전 장인 신청 수',
    (select count(influencer)::text from public.profiles) || ' / '
      || (select count(*)::text from public.influencer_applications where status = 'pending'),
    '-', E'실행 전과 같음', E'047은 장인 표시\u00B7신청을 바꾸지 않는다'
  union all select 24, 'pg_cron 일정 (047은 필요 없음)',
    case when to_regclass('cron.job') is null then 'pg_cron 없음'
         else (xpath('/row/c/text()', query_to_xml('select count(*) as c from cron.job where jobname like ''%link%''', false, true, '')))[1]::text end,
    '0', '0', E'047은 새 일정이 없다'
) x
order by ord;
