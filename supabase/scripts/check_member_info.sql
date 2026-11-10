-- =====================================================================
-- 036(운영자 회원 현황·검색 + 감독관 재검토 요청) 확인 조회 (읽기만 — 아무것도 바꾸지 않는다).
-- 036 실행 "전"과 "후"에 한 번씩 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다.
-- [지금 값]이 [실행 전 정상]·[실행 후 정상]과 맞는지 본다. (SQL Editor는 운영자 계정이 아니라서 함수를 직접 부르는 검사는 못 한다 — 아래 사이트 확인으로)
--
-- 사이트에서 눈으로 확인할 것 (036 실행 + 새 코드 push 뒤):
--  1) 운영자 계정 → [관리] → "회원" 칸: 총 가입자·정식 회원·비회원, 구글·카카오 수, 최근 7일 신규가 보인다
--  2) 닉네임 일부로 [검색] → 최대 10명 → [정보 보기]에 가입일·가입 방식·레벨·칭호·활동 수만 보이고 이메일·로그인 ID는 없다
--  3) 감독관 계정 → [관리]에 "회원" 칸이 없다.  운영자 모드를 끄면([계정 설정]) 운영자 계정도 /admin이 막힌다
--  4) 감독관 계정 → [관리] → 다른 회원의 대기 중 새 카운터 제안에 [재검토 요청] 버튼이 있다 → 메모를 쓰고 확정
--     → 제안자 [알림]에 재검토 요청 메모가 가고, 운영자 [관리]의 "처리 기록"에 "재검토 요청 · 감독관" 줄이 남는다
--     (본인·운영진 제안, 문서 수정 제안, 숨긴 카운터 제안에는 감독관에게 처리 버튼이 없다)
-- =====================================================================
with fn as (
  select p.oid, p.proname, p.prosrc, p.pronargs from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('admin_member_stats', 'admin_search_members', 'admin_member_info', 'request_proposal_revision', 'request_proposal_revision_unchecked')
), logdef as (
  select pg_get_constraintdef(oid) as def from pg_constraint
  where conname = 'moderation_log_action_check' and conrelid = 'public.moderation_log'::regclass
)
select ord as "순서", what as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상"
from (
  select 1 as ord, '035 실행됨 (036의 전제: 처리 기록 보관 함수)' as what,
    (exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'purge_old_moderation_log'))::text as now_value, 'true' as before_ok, 'true' as after_ok
  union all select 2, '회원 현황·검색·정보 함수 3개 (admin_member_stats, admin_search_members, admin_member_info)',
    (select count(*)::text from fn where proname in ('admin_member_stats', 'admin_search_members', 'admin_member_info')), '0', '3'
  union all select 3, '세 함수 모두 운영자 검사(require_operator)를 하나',
    coalesce((select (count(*) filter (where prosrc like '%require_operator()%'))::text || ' / ' || count(*)::text from fn
      where proname in ('admin_member_stats', 'admin_search_members', 'admin_member_info')), '-'), '0 / 0', '3 / 3'
  union all select 4, '비로그인(anon)이 세 함수를 부를 수 있나 (false여야 함)',
    coalesce((select bool_or(has_function_privilege('anon', oid, 'execute'))::text from fn
      where proname in ('admin_member_stats', 'admin_search_members', 'admin_member_info')), '함수 없음'), '함수 없음', 'false'
  union all select 5, '로그인 사용자가 세 함수를 부를 수 있나 (true — 운영자인지는 함수 안에서 검사)',
    coalesce((select bool_and(has_function_privilege('authenticated', oid, 'execute'))::text from fn
      where proname in ('admin_member_stats', 'admin_search_members', 'admin_member_info')), '함수 없음'), '함수 없음', 'true'
  union all select 6, '세 함수가 이메일·로그인 ID 칸을 읽나 (false여야 함)',
    coalesce((select bool_or(prosrc ~* '(email|provider_id|identity_data|raw_user_meta_data|phone)')::text from fn
      where proname in ('admin_member_stats', 'admin_search_members', 'admin_member_info')), '함수 없음'), '함수 없음', 'false'
  union all select 7, '검색 결과 상한 (10명)',
    coalesce((select (prosrc like '%limit 10%')::text from fn where proname = 'admin_search_members'), '함수 없음'), '함수 없음', 'true'
  union all select 8, '재검토 요청(바깥 함수)이 운영진 검사(require_staff)를 하나',
    coalesce((select (prosrc like '%require_staff()%' and prosrc not like '%require_operator()%')::text from fn where proname = 'request_proposal_revision' and pronargs = 3), '함수 없음'), 'false', 'true'
  union all select 9, '재검토 요청(안쪽 함수)이 감독관 범위 검사(require_review_allowed)를 하나',
    coalesce((select (prosrc like '%require_staff()%' and prosrc like '%require_review_allowed%')::text from fn where proname = 'request_proposal_revision_unchecked'), '함수 없음'), 'false', 'true'
  union all select 10, '감독관이 요청하면 처리자(revision_requested_by)를 비우고 처리 기록을 남기나',
    coalesce((select (prosrc like '%is_moderator()%' and prosrc like '%log_moderation(''request_revision''%')::text from fn where proname = 'request_proposal_revision_unchecked'), '함수 없음'), 'false', 'true'
  union all select 11, '처리 기록 종류에 request_revision 추가 (예전 종류도 그대로)',
    (select (def like '%request_revision%')::text || ' / ' || (def like '%approve_proposal%' and def like '%edit_proposal%' and def like '%move_inquiry%')::text from logdef), 'false / true', 'true / true'
  union all select 12, '재검토 요청 취소(cancel_proposal_revision)는 운영자 전용 그대로',
    coalesce((select (prosrc like '%require_operator()%')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'cancel_proposal_revision'), '함수 없음'), 'true', 'true'
  union all select 13, '기존 처리 기록 수 (실행 전후 같아야 함)', (select count(*)::text from public.moderation_log), '-', '실행 전과 같음'
  union all select 14, '프로필 수 (사이트 "총 가입자"와 같아야 함)', (select count(*)::text from public.profiles), '-', '-'
) x
order by ord;
