-- =====================================================================
-- 042(회원 목록·회원 정보 조회 + 자유게시판 새 글 알림) 확인 조회 (읽기만 — 아무것도 바꾸지 않는다).
-- 042 실행 "전"과 "후"에 한 번씩 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
-- [지금 값]이 [실행 전 정상]·[실행 후 정상]과 맞는지 본다. (SQL Editor는 운영자 계정이 아니라서 함수를 직접 부르는 검사는 못 한다 — 아래 사이트 확인으로)
--   - 11번(기존 알림 수)·12번(프로필 수)은 실행 전 값을 적어 두었다가 실행 후 값과 같은지 본다 (042는 기존 데이터를 바꾸지 않는다).
--
-- 사이트에서 눈으로 확인할 것 (042 실행 + 새 코드 push 뒤, 2단계 화면이 나온 다음):
--  1) 운영자 계정 → [관리] → "회원 관리": 가입자 수, 최근 가입 순 목록, 닉네임 검색, 감독관 지정·해제
--  2) 회원을 누르면 열리는 회원 정보: 닉네임·가입일·역할·활동 수·경험치·칭호·쓴 글·댓글·고친 빌드·처리 이력. 이메일·로그인 ID는 없다.
--     운영자에게만 "지운 글·댓글" 구역이 보인다. 감독관 계정으로는 회원 관리 화면도 안 열린다.
--  3) 다른 계정으로 자유게시판에 새 글을 올리면 운영자 [알림]에 "새 글이 올라왔습니다." 가 생기고, 푸시를 켜 두었다면 폰에도 온다.
--     운영자 모드를 끄면 알림이 목록·빨간 점에서 빠지고 푸시도 안 온다. 운영자 본인이 쓴 글·댓글은 알림이 없다.
-- =====================================================================
with fn as (
  select p.oid, p.proname, p.prosrc, p.pronargs
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('admin_member_list', 'admin_member_list_unchecked', 'admin_member_detail', 'admin_member_detail_unchecked',
                      'admin_member_info', 'admin_deleted_writings', 'set_moderator', 'notify_admins_new_post',
                      'push_group', 'push_targets', 'mark_all_notifications_read')
),
kindcheck as (
  select pg_get_constraintdef(oid) as def from pg_constraint
  where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass
),
pol as (
  select coalesce(qual, '') as q from pg_policies
  where schemaname = 'public' and tablename = 'notifications' and policyname = 'notifications: 본인 읽기'
)
select ord as "순서", what as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상"
from (
  select 1 as ord, '041 실행됨 (042의 전제: 지운 글 조회 함수 admin_deleted_writings)' as what,
    (exists (select 1 from fn where proname = 'admin_deleted_writings'))::text as now_value, 'true' as before_ok, 'true' as after_ok
  union all select 2, '회원 관리 함수 4개 (목록·정보 각각 바깥 + 안쪽 _unchecked)',
    (select count(*)::text from fn where proname in ('admin_member_list', 'admin_member_list_unchecked', 'admin_member_detail', 'admin_member_detail_unchecked')), '0', '4'
  union all select 3, '바깥 두 함수가 운영자 검사(require_operator)를 먼저 하나',
    coalesce((select (count(*) filter (where prosrc like '%require_operator()%'))::text || ' / ' || count(*)::text from fn
      where proname in ('admin_member_list', 'admin_member_detail')), '-'), '0 / 0', '2 / 2'
  union all select 4, '안쪽 _unchecked를 누가 부를 수 있나 (false여야 함 — 로그인 사용자·비로그인 모두)',
    coalesce((select bool_or(has_function_privilege('authenticated', oid, 'execute') or has_function_privilege('anon', oid, 'execute'))::text from fn
      where proname in ('admin_member_list_unchecked', 'admin_member_detail_unchecked', 'notify_admins_new_post')), '함수 없음'), '함수 없음', 'false'
  union all select 5, '바깥 함수: 비로그인 실행(false) / 로그인 사용자 실행(true — 운영자인지는 함수 안에서 검사)',
    coalesce((select bool_or(has_function_privilege('anon', oid, 'execute'))::text || ' / ' || bool_and(has_function_privilege('authenticated', oid, 'execute'))::text from fn
      where proname in ('admin_member_list', 'admin_member_detail')), '함수 없음'), '함수 없음', 'false / true'
  union all select 6, '회원 정보·목록 함수가 이메일·로그인 ID 칸을 읽나 (false여야 함)',
    coalesce((select bool_or(prosrc ~* '(email|provider_id|identity_data|raw_user_meta_data|phone)')::text from fn
      where proname in ('admin_member_list', 'admin_member_list_unchecked', 'admin_member_detail', 'admin_member_detail_unchecked')), '함수 없음'), '함수 없음', 'false'
  union all select 7, '감독관 지정(set_moderator)·지운 글 조회(admin_deleted_writings)는 운영자 전용 그대로',
    coalesce((select (count(*) filter (where prosrc like '%require_operator()%'))::text || ' / ' || count(*)::text from fn
      where proname in ('set_moderator', 'admin_deleted_writings')), '-'), '2 / 2', '2 / 2'
  union all select 8, '알림 종류에 post_created 추가 (예전 종류도 그대로)',
    (select (def like '%post_created%')::text || ' / ' || (def like '%matchup_created%' and def like '%doc_comment_deleted%' and def like '%inquiry_received%')::text from kindcheck),
    'false / true', 'true / true'
  union all select 9, '운영자 모드를 끄면 새 글 알림도 가림 (읽기 정책 · 모두 읽음)',
    (select (q like '%post_created%')::text from pol) || ' / '
      || coalesce((select (prosrc like '%post_created%')::text from fn where proname = 'mark_all_notifications_read'), '-'),
    'false / false', 'true / true'
  union all select 10, '푸시 묶음: 새 글 = staff_new, 예전 것 그대로 (새 상대법 = staff_new, 승인 결과 = my_results)',
    coalesce((select coalesce(public.push_group('post_created'), '안 보냄') || ' / ' || coalesce(public.push_group('matchup_created'), '안 보냄')
              || ' / ' || coalesce(public.push_group('proposal_approved'), '안 보냄') from fn where proname = 'push_group'), '함수 없음'),
    '안 보냄 / staff_new / my_results', 'staff_new / staff_new / my_results'
  union all select 11, '기존 알림 수 (실행 전후 같아야 함)', (select count(*)::text from public.notifications), '-', '실행 전과 같음'
  union all select 12, '프로필 수 (사이트 "총 가입자"와 같아야 함)', (select count(*)::text from public.profiles), '-', '-'
  union all select 13, '푸시 알림 대상 기기가 있는 운영자 수 (새 글 푸시를 받을 사람. 0이면 푸시만 안 감)',
    (select count(distinct s.user_id)::text from public.push_subscriptions s join public.profiles p on p.id = s.user_id where p.role = 'admin'), '-', '-'
  union all select 14, '새 글 알림이 이미 생겼나 (실행 후 새 글이 올라올 때마다 늘어남)',
    case when exists (select 1 from kindcheck where def like '%post_created%')
         then (select count(*)::text from public.notifications where kind = 'post_created') else '종류 없음' end,
    '종류 없음', '0 이상'
  union all select 15, '새 글 알림 트리거(posts_notify_admins)',
    (select count(*)::text from pg_trigger where tgname = 'posts_notify_admins' and tgenabled <> 'D'), '0', '1'
) x
order by ord;
