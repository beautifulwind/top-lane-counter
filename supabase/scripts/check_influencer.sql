-- =====================================================================
-- 046(장인 인증 1단계 DB) 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 046 실행 "전"과 "후", 그리고 pg_cron 일정 등록 뒤에 한 번씩 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
-- [지금 값]이 [실행 전 정상]/[실행 후 정상]과 맞는지 본다.
--   - 1번(닉네임 열쇠 중복)은 실행 "전"에 반드시 0이어야 한다. 0이 아니면 메모 칸의 닉네임들 중 한쪽에 닉네임 변경을 부탁하고 다시 확인한다
--     (046도 맨 앞에서 같은 검사를 하고, 겹치면 아무것도 바꾸지 않고 멈춘다).
--   - 2번(장인 흉내 닉네임)은 이미 있는 닉네임이라 046이 바꾸지 않는다. 나오면 그 회원에게 닉네임 변경을 부탁한다(새로 정하는 것만 막힘).
--   - 3~9번(기준값)은 실행 전 값을 적어 두었다가 실행 후 값과 같은지 본다. 경험치 합계(예: 125)/칭호 수/프로필 수 등 - 046은 기존 데이터를 바꾸지 않는다.
--   - 실행 뒤 false/0이 "실행 후 정상"과 다르면 바로 알려 주세요.
-- (SQL Editor는 운영자 계정이 아니라서 함수를 직접 부르는 검사는 못 한다 - 함수 정의/권한/설정값만 본다)
-- =====================================================================
with prof as (
  select id, nickname,
         replace(replace(
           translate(
             regexp_replace(
               lower(translate(normalize(nickname, NFKC), E'\u0410\u0412\u0415\u041A\u041C\u041D\u041E\u0420\u0421\u0422\u0425\u0406\u0408\u0405\u0391\u0392\u0395\u0396\u0397\u0399\u039A\u039C\u039D\u039F\u03A1\u03A4\u03A5\u03A7', 'ABEKMHOPCTXIJSABEZHIKMNOPTYX')),
               '[\s\u00A0\u00AD\u034F\u115F\u1160\u17B4\u17B5\u180E\u2000-\u200F\u2028-\u202F\u205F-\u206F\u3000\u3164\uFEFF\uFFA0\u0300-\u036F_.\u00B7\u30FB\u2027\u2022\u318D-]', '', 'g'),
             E'\u0430\u0435\u043E\u0440\u0441\u0443\u0445\u0458\u0455\u0501\u04BB\u03BF\u03B1\u03BD\u03C1\u03C4\u03BA\u03C5\u0261\u0456\u03B9\u0131i1|0', 'aeopcyxjsdhoavptkugllllllo'),
           'rn', 'm'), 'vv', 'w') as k
  from public.profiles where nickname is not null
),
dup as (
  select k, string_agg(nickname, ' / ' order by nickname) as names from prof group by k having count(*) > 1
),
mimic as (
  select nickname from public.profiles
   where nickname ~ '^\s*장인[\s_|\u00B7.:/~-]'
      or regexp_replace(nickname, '\s', '', 'g') ~ '[\[\(\uFF08\u3010\u300C\u300E<\u3008\u300A\u3014{]장인[\]\)\uFF09\u3011\u300D\u300F>\u3009\u300B\u3015}]'
),
col as (
  select column_name from information_schema.columns where table_schema = 'public' and table_name = 'profiles'
),
fn as (
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
pol as (
  select coalesce(qual, '') as q from pg_policies
  where schemaname = 'public' and tablename = 'notifications' and policyname = 'notifications: 본인 읽기'
),
new_kinds (k) as (
  values ('influencer_applied'), ('influencer_received'), ('influencer_expiring'), ('influencer_approved'), ('influencer_rejected'),
         ('influencer_expired'), ('influencer_revoked'), ('nickname_reset_soon'), ('nickname_reset'), ('link_removed')
)
select ord as "순서", what as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상", memo as "메모"
from (
  select 1 as ord, E'닉네임 열쇠 중복 (비슷한 닉네임끼리 \u2014 실행 전 0이어야 함)' as what,
    (select count(*)::text from dup) as now_value, '0' as before_ok, '0' as after_ok,
    coalesce((select string_agg('[' || names || ']', ' ') from dup), '') as memo
  union all select 2, E'장인 흉내 닉네임 ([장인]\u00B7(장인)\u00B7"장인 "으로 시작, 대략) \u2014 있으면 변경 부탁',
    (select count(*)::text from mimic), '0 권장', '0 권장', coalesce((select string_agg(nickname, ' / ') from mimic), '')
  union all select 3, '기준값: 경험치 합계 (프로필 xp 합 / 경험치 기록 합)',
    (select coalesce(sum(xp), 0)::text from public.profiles) || ' / ' || (select coalesce(sum(amount), 0)::text from public.xp_events),
    '-', '실행 전과 같음 (예: 125)', '046은 경험치를 바꾸지 않는다'
  union all select 4, '기준값: 레벨 합계 / 칭호 수',
    (select coalesce(sum(level), 0)::text from public.profiles) || ' / ' || (select count(*)::text from public.user_titles), '-', '실행 전과 같음', ''
  union all select 5, '기준값: 프로필 수 / 닉네임 정한 수 / 운영자 / 감독관 / 비회원',
    (select count(*)::text from public.profiles) || ' / ' || (select count(nickname)::text from public.profiles) || ' / '
      || (select count(*)::text from public.profiles where role = 'admin') || ' / ' || (select count(*)::text from public.profiles where role = 'moderator')
      || ' / ' || (select count(*)::text from public.profiles where is_guest), '-', '실행 전과 같음', ''
  union all select 6, '기준값: 닉네임 변경 기록 수', (select count(*)::text from public.nickname_changes), '-', '실행 전과 같음', '이전 기록은 kind = user로 채워짐'
  union all select 7, '기준값: 알림 수 (장인 알림 종류 제외)',
    (select count(*)::text from public.notifications where kind not in (select k from new_kinds)), '-', '실행 전과 같음', ''
  union all select 8, '기준값: 처리 기록 수 / 공개 빌드 수 / 공개 상대법 수',
    (select count(*)::text from public.moderation_log) || ' / ' || (select count(*)::text from public.builds where status = 'approved')
      || ' / ' || (select count(*)::text from public.counters where status = 'approved'), '-', '실행 전과 같음 (처리 기록은 장인 심사만큼 늘어남)', ''
  union all select 9, '기준값: 설정값 수 (xp_rules)', (select count(*)::text from public.xp_rules), '-', '실행 전 + 10', 'influencer_* 설정 10개'
  union all select 10, '신청 표 influencer_applications (있음 / RLS 켜짐 / 읽기 정책 수)',
    case when to_regclass('public.influencer_applications') is null then '없음'
         else 'true / ' || (select relrowsecurity::text from pg_class where oid = to_regclass('public.influencer_applications'))
              || ' / ' || (select count(*)::text from pg_policies where schemaname = 'public' and tablename = 'influencer_applications') end,
    '없음', 'true / true / 1', E'읽기는 본인\u00B7운영자만 (감독관 제외)'
  union all select 11, '신청 표에 로그인 사용자 쓰기 권한 (false여야 함)',
    case when to_regclass('public.influencer_applications') is null then '-'
         else (has_table_privilege('authenticated', 'public.influencer_applications', 'insert')
               or has_table_privilege('authenticated', 'public.influencer_applications', 'update')
               or has_table_privilege('anon', 'public.influencer_applications', 'select'))::text end, '-', 'false', ''
  union all select 12, E'프로필 새 칸 (influencer\u00B7influencer_at\u00B7nickname_state\u00B7nickname_reset_at\u00B7nickname_key)',
    (select count(*)::text from col where column_name in ('influencer', 'influencer_at', 'nickname_state', 'nickname_reset_at', 'nickname_key')), '0', '5', ''
  union all select 13, '프로필 장인 칸을 회원이 직접 고칠 수 있나 (false여야 함)',
    case when exists (select 1 from col where column_name = 'influencer')
         then (has_column_privilege('authenticated', 'public.profiles', 'influencer', 'update')
               or has_column_privilege('authenticated', 'public.profiles', 'nickname_state', 'update'))::text else '-' end, '-', 'false', ''
  union all select 14, '닉네임 인덱스: 예전 lower(nickname) / 새 열쇠 보통 / 새 열쇠 인증 대기',
    (select count(*)::text from pg_indexes where schemaname = 'public' and indexname = 'profiles_nickname_unique') || ' / '
      || (select count(*)::text from pg_indexes where schemaname = 'public' and indexname = 'profiles_nickname_key_unique') || ' / '
      || (select count(*)::text from pg_indexes where schemaname = 'public' and indexname = 'profiles_nickname_key_pending'),
    '1 / 0 / 0', '0 / 1 / 1', '되돌리는 법은 046 파일 맨 위 설명'
  union all select 15, '트리거: 비슷한 닉네임 검사 / 신청 개인정보 지우기',
    (select count(*)::text from pg_trigger where tgname = 'profiles_nickname_key' and not tgisinternal) || ' / '
      || (select count(*)::text from pg_trigger where tgname = 'influencer_applications_clear_private' and not tgisinternal), '0 / 0', '1 / 1', ''
  union all select 16, E'닉네임 열쇠 계산이 이 조회와 같음 (다른 수 \u2014 0이어야 함)',
    case when exists (select 1 from col where column_name = 'nickname_key')
         then (select count(*)::text from prof
                where prof.k is distinct from (xpath('/row/c/text()', query_to_xml(format('select public.nickname_key(%L) as c', prof.nickname), false, true, '')))[1]::text)
         else '-' end,
    '-', '0', ''
  union all select 17, '알림 종류: 장인 10종 / 예전 종류도 그대로',
    (select count(*)::text from new_kinds where (select def from kindcheck) like '%''' || k || '''%') || ' / '
      || (select (def like '%report_received%' and def like '%error_reported%' and def like '%post_created%' and def like '%inquiry_received%'
                  and def like '%doc_comment_deleted%' and def like '%counter_restored%')::text from kindcheck),
    '0 / true', '10 / true', ''
  union all select 18, '운영자 모드를 끄면 장인 신청 알림 가림 (읽기 정책 / 모두 읽음)',
    (select (q like '%influencer_applied%')::text from pol) || ' / '
      || coalesce((select (prosrc like '%influencer_applied%')::text from fn where proname = 'mark_all_notifications_read'), '-'),
    'false / false', 'true / true', ''
  union all select 19, '푸시 묶음: 신청(운영자) / 결과(신청자) / 임시 닉네임 / 링크 삭제 / 새 신고(그대로)',
    coalesce(public.push_group('influencer_applied'), '안 보냄') || ' / ' || coalesce(public.push_group('influencer_rejected'), '안 보냄')
      || ' / ' || coalesce(public.push_group('nickname_reset'), '안 보냄') || ' / ' || coalesce(public.push_group('link_removed'), '안 보냄')
      || ' / ' || coalesce(public.push_group('report_received'), '안 보냄'),
    '안 보냄 / 안 보냄 / 안 보냄 / 안 보냄 / staff_new', 'staff_new / my_results / my_results / my_results / staff_new', ''
  union all select 20, E'처리 기록 종류 (승인\u00B7반려\u00B7만료일 늘리기\u00B7해제\u00B7닉네임 바꾸기)',
    (select (def like '%approve_influencer%' and def like '%reject_influencer%' and def like '%extend_influencer%'
             and def like '%revoke_influencer%' and def like '%rename_member%')::text from actcheck), 'false', 'true', ''
  union all select 21, '처리 대기 건수에 장인 신청 키 (influencers)',
    coalesce((select (prosrc like '%''influencers''%')::text from fn where proname = 'admin_pending_counts'), '-'), 'false', 'true', ''
  union all select 22, E'사람 json에 장인 칸 (기여자\u00B7수정 기록\u00B7자유게시판\u00B7신고\u00B7회원 목록\u00B7검색\u00B7정보 \u2014 7개 함수)',
    (select count(*)::text from fn where proname in ('build_contributors', 'admin_build_revisions_unchecked', 'board_page', 'open_reports_for_moderator',
       'admin_member_list_unchecked', 'admin_search_members', 'admin_member_info') and prosrc like '%''influencer''%'), '0', '7', ''
  union all select 23, E'로그인 사용자가 부를 수 있는 새 함수 (신청\u00B7취소\u00B7내 상태\u00B7운영자 7개 \u2014 운영자인지는 함수 안에서)',
    (select count(*)::text from fn where proname in ('apply_influencer', 'cancel_influencer_application', 'my_influencer_status',
       'admin_influencer_applications', 'approve_influencer', 'reject_influencer', 'extend_influencer_application', 'revoke_influencer',
       'admin_set_nickname', 'admin_new_members') and has_function_privilege('authenticated', oid, 'execute')), '0', '10', ''
  union all select 24, E'안쪽 함수를 로그인 사용자\u00B7비로그인이 부를 수 있나 (0이어야 함)',
    (select count(*)::text from fn where proname in ('influencer_daily', 'influencer_close', 'system_set_nickname', 'influencer_temp_nickname',
       'approve_influencer_unchecked', 'reject_influencer_unchecked', 'admin_new_members_unchecked', 'admin_influencer_applications_unchecked',
       'revoke_influencer_unchecked', 'admin_set_nickname_unchecked', 'extend_influencer_application_unchecked', 'influencer_next_apply_at')
       and (has_function_privilege('authenticated', oid, 'execute') or has_function_privilege('anon', oid, 'execute'))), '0', '0', ''
  union all select 25, E'비로그인이 신규 가입자\u00B7신청 함수를 부를 수 있나 (false여야 함)',
    coalesce((select bool_or(has_function_privilege('anon', oid, 'execute'))::text from fn
               where proname in ('admin_new_members', 'apply_influencer', 'admin_influencer_applications')), '-'), '-', 'false', ''
  union all select 26, '장인 빌드 라벨용 기여자 수 build_editor_counts (누구나)',
    coalesce((select has_function_privilege('anon', oid, 'execute')::text from fn where proname = 'build_editor_counts'), '없음'), '없음', 'true', ''
  union all select 27, '빌드 수정 잠금(edit_lock)은 만들지 않음 (builds에 칸 없음)',
    (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'builds' and column_name = 'edit_lock'), '0', '0', ''
  union all select 28, '설정값: 신청 만료 / 반려 뒤 / 180일 반려 횟수 / 금지 / 닉네임 유예 / 가입 뒤 최소 (일)',
    coalesce((select value::text from public.xp_rules where key = 'influencer_review_days'), '-') || ' / '
      || coalesce((select value::text from public.xp_rules where key = 'influencer_retry_days'), '-') || ' / '
      || coalesce((select value::text from public.xp_rules where key = 'influencer_reject_limit'), '-') || ' / '
      || coalesce((select value::text from public.xp_rules where key = 'influencer_ban_days'), '-') || ' / '
      || coalesce((select value::text from public.xp_rules where key = 'influencer_nickname_grace_days'), '-') || ' / '
      || coalesce((select value::text from public.xp_rules where key = 'influencer_min_account_days'), '-'),
    '- / - / - / - / - / -', '14 / 7 / 3 / 180 / 3 / 0', ''
  union all select 29, E'장인 신청 수 (처리 전 / 승인) \u00B7 장인 수 \u00B7 인증 대기\u00B7변경 예정 닉네임',
    case when to_regclass('public.influencer_applications') is null then '-'
         else (xpath('/row/c/text()', query_to_xml('select count(*) filter (where status = ''pending'') || '' / '' || count(*) filter (where status = ''approved'') as c from public.influencer_applications', false, true, '')))[1]::text end
      || E' \u00B7 ' || case when exists (select 1 from col where column_name = 'influencer')
                       then (xpath('/row/c/text()', query_to_xml(E'select count(influencer) || '' \u00B7 '' || count(nickname_state) as c from public.profiles', false, true, '')))[1]::text
                       else '-' end,
    E'- \u00B7 -', E'0 / 0 \u00B7 0 \u00B7 0 (실행 직후)', '신청 화면은 2단계라 그전에는 늘지 않는다'
  union all select 30, 'pg_cron 일정 influencer-daily (등록 뒤 1)',
    case when to_regclass('cron.job') is null then 'pg_cron 없음'
         else (xpath('/row/c/text()', query_to_xml('select count(*) as c from cron.job where jobname = ''influencer-daily''', false, true, '')))[1]::text end,
    '0', '1 (일정 등록 뒤)', '등록 SQL은 작업 보고에 따로'
) x
order by ord;
