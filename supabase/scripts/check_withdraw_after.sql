-- =====================================================================
-- 055(회원 탈퇴 정리) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 055를 실행한 뒤 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~12번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요.
--   - 13~14번: 한 번 정리가 끝나 남은 대상이 0이어야 한다 (check_withdraw_before.sql 6~7번이 정리된 것).
--   - 15~19번: check_withdraw_before.sql의 9~13번에 적어 둔 값과 비교한다.
-- (SQL Editor는 로그인한 회원이 아니라서 탈퇴를 직접 해 보는 검사는 못 한다 - 표/함수 정의/권한/개수만 본다.
--  탈퇴를 처음부터 끝까지 해 보는 검사는 로컬 supabase/tests/withdraw_test.sql)
-- 055를 아직 실행하지 않았어도 오류 없이 돌도록, 새 표/함수를 읽는 곳은 to_regclass/to_regprocedure/query_to_xml로 감쌌다.
-- =====================================================================
with fn as (
  select p.proname, p.prosrc, p.oid
  from pg_proc p where p.pronamespace = 'public'::regnamespace
),
con as (
  select c.conname, c.contype, c.confdeltype, pg_get_constraintdef(c.oid) as def
  from pg_constraint c
  where c.conrelid in ('public.build_votes'::regclass, 'public.post_votes'::regclass, 'public.influencer_applications'::regclass)
),
log_targets as (
  select m.target_kind from public.moderation_log m
   where m.target_nickname is distinct from '탈퇴한 이용자'
     and (   (m.target_kind = 'user' and m.target_id is not null
              and not exists (select 1 from public.profiles p where p.id::text = m.target_id))
          or (m.target_kind = 'influencer_application'
              and exists (select 1 from public.influencer_applications a where a.id::text = m.target_id and a.user_id is null))
          or (m.target_kind = 'link' and m.target_nickname is not null
              and not exists (select 1 from public.profiles p where p.nickname = m.target_nickname)
              and not exists (select 1 from public.nickname_changes c join public.profiles p on p.id = c.user_id
                               where m.target_nickname in (c.old_nickname, c.new_nickname))))
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '표 nickname_holds / RLS 켬 / 정책 수' as what,
    (to_regclass('public.nickname_holds') is not null)::text || ' / '
      || coalesce((select relrowsecurity::text from pg_class where oid = to_regclass('public.nickname_holds')), 'false') || ' / '
      || (select count(*)::text from pg_policies where schemaname = 'public' and tablename = 'nickname_holds') as now_value,
    'true / true / 0' as ok_value, '클라이언트는 읽기/쓰기 모두 불가' as memo
  union all select 2, '예약 표 직접 읽기: 비로그인 / 회원',
    case when to_regclass('public.nickname_holds') is null then '표 없음'
      else has_table_privilege('anon', 'public.nickname_holds', 'select')::text || ' / '
        || has_table_privilege('authenticated', 'public.nickname_holds', 'select')::text end,
    'false / false', ''
  union all select 3, '새 함수 / 트리거: withdraw_account_unchecked, withdraw_cleanup, moderation_note_scrub, withdraw_on_profile_delete / profiles_anonymize_on_delete',
    (select count(*)::text from fn where proname in ('withdraw_account_unchecked', 'withdraw_cleanup', 'moderation_note_scrub', 'withdraw_on_profile_delete')) || ' / '
      || exists (select 1 from pg_trigger where tgname = 'profiles_anonymize_on_delete' and tgrelid = 'public.profiles'::regclass)::text,
    '4 / true', ''
  union all select 4, '새 함수를 부를 수 있는 사람 (비로그인/회원 중 하나라도)',
    (select count(*)::text from fn where proname in ('withdraw_account_unchecked', 'withdraw_cleanup', 'moderation_note_scrub', 'withdraw_on_profile_delete')
        and (has_function_privilege('anon', oid, 'execute') or has_function_privilege('authenticated', oid, 'execute'))),
    '0', '아무도 직접 못 부름 (탈퇴 함수/트리거 안에서만)'
  union all select 5, '탈퇴 함수 권한: delete_my_account 회원 / kakao_unlinked 회원 / kakao_unlinked service_role',
    has_function_privilege('authenticated', 'public.delete_my_account(text)', 'execute')::text || ' / '
      || has_function_privilege('authenticated', 'public.kakao_unlinked(text)', 'execute')::text || ' / '
      || has_function_privilege('service_role', 'public.kakao_unlinked(text)', 'execute')::text,
    'true / false / true', '017/020과 같음 (Edge Function 재배포 필요 없음)'
  union all select 6, '세 탈퇴 함수가 공통 안쪽 함수를 부름 (auth.users를 직접 지우지 않음)',
    (select count(*)::text from fn where proname in ('delete_my_account', 'kakao_unlinked', 'cleanup_guest_accounts')
        and prosrc like '%withdraw_account_unchecked%' and prosrc not like '%delete from auth.users%'),
    '3', 'delete_my_account / kakao_unlinked / cleanup_guest_accounts'
  union all select 7, '추천 표 외래 키(탈퇴 때): 빌드 추천 / 글 추천',
    (select case confdeltype when 'c' then 'cascade' when 'n' then 'set null' else confdeltype::text end from con where conname = 'build_votes_user_id_fkey') || ' / '
      || (select case confdeltype when 'c' then 'cascade' when 'n' then 'set null' else confdeltype::text end from con where conname = 'post_votes_user_id_fkey'),
    'set null / set null', '탈퇴해도 추천은 익명으로 남아 수가 그대로'
  union all select 8, '추천 표 키: 빌드 기본 키 / 빌드 한 사람 한 표 / 글 기본 키 / 글 한 사람 한 표',
    (select def from con where conname = 'build_votes_pkey') || ' / ' || coalesce((select def from con where conname = 'build_votes_once'), '없음') || ' / '
      || (select def from con where conname = 'post_votes_pkey') || ' / ' || coalesce((select def from con where conname = 'post_votes_once'), '없음'),
    'PRIMARY KEY (id) / UNIQUE (build_id, user_id) / PRIMARY KEY (id) / UNIQUE (post_id, user_id)', ''
  union all select 9, '추천 수 트리거 apply_build_vote가 누른 사람만 바뀐 경우를 건너뜀',
    (select (prosrc like '%(055)%')::text from fn where proname = 'apply_build_vote'),
    'true', '남의 칭호 회수/알림이 생기지 않게'
  union all select 10, '빈칸 허용: 처리 기록 target_id / 장인 신청 nickname',
    (select is_nullable from information_schema.columns where table_schema = 'public' and table_name = 'moderation_log' and column_name = 'target_id') || ' / '
      || (select is_nullable from information_schema.columns where table_schema = 'public' and table_name = 'influencer_applications' and column_name = 'nickname'),
    'YES / YES', ''
  union all select 11, '신청 표 제약: 탈퇴 줄 규칙(user_id is null) 들어감 / 회원 신청은 닉네임 필수(influencer_applications_nickname_kept)',
    coalesce((select (def like '%user_id IS NULL%')::text from con where conname = 'influencer_applications_fields'), 'false') || ' / '
      || exists (select 1 from con where conname = 'influencer_applications_nickname_kept')::text,
    'true / true', ''
  union all select 12, '설정값 influencer_nickname_hold_days / 닉네임 검사·임시 닉네임·하루 작업이 예약 표를 봄',
    coalesce((select value::text from public.xp_rules where key = 'influencer_nickname_hold_days'), '없음') || ' / '
      || (select count(*)::text from fn where proname in ('check_nickname_key', 'influencer_temp_nickname', 'influencer_daily')
            and prosrc like '%nickname_holds%'),
    '30 / 3', '30일 뒤 정리는 기존 pg_cron influencer-daily (새 일정 없음)'
  union all select 13, '남은 정리 대상: 탈퇴한 회원의 장인 신청 기록 중 식별 칸이 남은 줄',
    (select count(*)::text from public.influencer_applications
      where user_id is null
        and (nickname is not null or old_nickname is not null or nickname_reverted is not null or channel_url is not null
             or channel_key is not null or opgg_url is not null or official_email is not null or riot_id is not null
             or riot_key is not null or review_note is not null or revoke_note is not null or reviewed_by is not null
             or status in ('pending', 'approved'))),
    '0', '실행 전 6번 줄 수만큼 정리됨'
  union all select 14, '남은 정리 대상: 탈퇴한 회원이 대상인 처리 기록 (회원 / 장인 신청 / 링크 / 합계)',
    (select count(*)::text from log_targets where target_kind = 'user') || ' / '
      || (select count(*)::text from log_targets where target_kind = 'influencer_application') || ' / '
      || (select count(*)::text from log_targets where target_kind = 'link') || ' / '
      || (select count(*)::text from log_targets),
    '0 / 0 / 0 / 0', '실행 전 7번 합계만큼 정리됨'
  union all select 15, '비교: 빌드 추천 줄 수 / 빌드 추천 수 합 / 비추천 수 합',
    (select count(*)::text from public.build_votes) || ' / '
      || (select coalesce(sum(up_count), 0)::text from public.builds) || ' / '
      || (select coalesce(sum(down_count), 0)::text from public.builds),
    '(실행 전 9번과 같음)', ''
  union all select 16, '비교: 글 추천 줄 수 / 글 추천 수 합',
    (select count(*)::text from public.post_votes) || ' / ' || (select coalesce(sum(up_count), 0)::text from public.posts),
    '(실행 전 10번과 같음)', ''
  union all select 17, '비교: 장인 신청 기록 줄 수 (전체 / user_id가 빈 줄)',
    (select count(*)::text from public.influencer_applications) || ' / '
      || (select count(*)::text from public.influencer_applications where user_id is null),
    '(실행 전 11번과 같음)', ''
  union all select 18, '비교: 처리 기록 줄 수 (전체 / 대상이 "탈퇴한 이용자"인 줄)',
    (select count(*)::text from public.moderation_log) || ' / '
      || (select count(*)::text from public.moderation_log where target_nickname = '탈퇴한 이용자'),
    '(전체는 실행 전 12번과 같음 / "탈퇴한 이용자"는 실행 전 12번 + 7번 합계)', ''
  union all select 19, '비교: 회원 수 (전체 / 인증된 장인) / 닉네임 예약 줄 수',
    (select count(*)::text from public.profiles) || ' / ' || (select count(*)::text from public.profiles where influencer is not null) || ' / '
      || case when to_regclass('public.nickname_holds') is null then '표 없음'
           else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.nickname_holds', false, true, '')))[1]::text end,
    '(실행 전 13번과 같음) / 0', '예약은 055 뒤 장인이 탈퇴할 때만 생긴다'
) rows
order by ord;
