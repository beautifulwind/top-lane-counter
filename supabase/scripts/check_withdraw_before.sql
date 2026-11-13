-- =====================================================================
-- 055(회원 탈퇴 정리) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 055를 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~5번: [지금 값]이 [정상 값]과 모두 맞으면 055를 실행해도 된다. 하나라도 다르면 실행하지 말고 알려 주세요.
--   - 6~8번: 055가 "한 번 정리"로 바꿀 줄 수 (되돌릴 수 없는 익명화). 적어 두고 055 실행 결과 NOTICE와,
--     check_withdraw_after.sql의 같은 이름 줄(정리 뒤 0)과 비교한다.
--   - 9~13번: 적어 둘 값. 055는 이 값을 바꾸지 않는다 (실행 직후 check_withdraw_after.sql의 같은 이름 줄과 같아야 함.
--     그 사이 사이트에서 누가 추천하거나 탈퇴하면 달라질 수 있다 - 그때는 알려 주세요).
-- 055가 만드는 표/함수가 아직 없어도 오류 없이 돌도록 to_regclass/to_regprocedure/pg_constraint만 쓴다.
-- =====================================================================
with con as (
  select c.conname, c.confdeltype, pg_get_constraintdef(c.oid) as def
  from pg_constraint c
  where c.conrelid in ('public.build_votes'::regclass, 'public.post_votes'::regclass, 'public.influencer_applications'::regclass)
),
-- 055가 한 번 정리할 처리 기록 (055 파일과 같은 조건)
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
  select 1 as ord, '054까지 실행됨 (함수 public_title_info)' as what,
    (to_regprocedure('public.public_title_info()') is not null)::text as now_value,
    'true' as ok_value, 'false면 054부터 실행' as memo
  union all select 2, '055 아직 안 함: 표 nickname_holds / 함수 withdraw_account_unchecked / 설정값 influencer_nickname_hold_days',
    (to_regclass('public.nickname_holds') is not null)::text || ' / '
      || (to_regprocedure('public.withdraw_account_unchecked(uuid)') is not null)::text || ' / '
      || exists (select 1 from public.xp_rules where key = 'influencer_nickname_hold_days')::text,
    'false / false / false', 'true가 있으면 이미 실행한 것 - 다시 실행하지 말 것'
  union all select 3, '추천 표 외래 키(탈퇴 때): 빌드 추천 / 글 추천',
    (select case confdeltype when 'c' then 'cascade' when 'n' then 'set null' else confdeltype::text end from con where conname = 'build_votes_user_id_fkey') || ' / '
      || (select case confdeltype when 'c' then 'cascade' when 'n' then 'set null' else confdeltype::text end from con where conname = 'post_votes_user_id_fkey'),
    'cascade / cascade', '지금은 탈퇴하면 추천이 지워진다 (055 뒤 set null)'
  union all select 4, '추천 표 기본 키: 빌드 추천 / 글 추천',
    (select def from con where conname = 'build_votes_pkey') || ' / ' || (select def from con where conname = 'post_votes_pkey'),
    'PRIMARY KEY (build_id, user_id) / PRIMARY KEY (post_id, user_id)', '이름이 다르면 055가 멈춘다'
  union all select 5, '빈칸 허용: 처리 기록 target_id / 장인 신청 nickname / 신청 표 제약 influencer_applications_fields 있음',
    (select is_nullable from information_schema.columns where table_schema = 'public' and table_name = 'moderation_log' and column_name = 'target_id') || ' / '
      || (select is_nullable from information_schema.columns where table_schema = 'public' and table_name = 'influencer_applications' and column_name = 'nickname') || ' / '
      || exists (select 1 from con where conname = 'influencer_applications_fields')::text,
    'NO / NO / true', ''
  union all select 6, '한 번 정리 대상: 탈퇴한 회원의 장인 신청 기록 중 식별 칸이 남은 줄',
    (select count(*)::text from public.influencer_applications
      where user_id is null
        and (nickname is not null or old_nickname is not null or nickname_reverted is not null or channel_url is not null
             or channel_key is not null or opgg_url is not null or official_email is not null or riot_id is not null
             or riot_key is not null or review_note is not null or revoke_note is not null or reviewed_by is not null
             or status in ('pending', 'approved'))),
    '(이 값을 적어 둠)', '055가 희망/옛 닉네임, 채널/op.gg, 메모 등을 지움. 055 실행 NOTICE의 "장인 신청 기록" 줄 수와 같아야 함'
  union all select 7, '한 번 정리 대상: 탈퇴한 회원이 대상인 처리 기록 (회원 / 장인 신청 / 링크 / 합계)',
    (select count(*)::text from log_targets where target_kind = 'user') || ' / '
      || (select count(*)::text from log_targets where target_kind = 'influencer_application') || ' / '
      || (select count(*)::text from log_targets where target_kind = 'link') || ' / '
      || (select count(*)::text from log_targets),
    '(이 값을 적어 둠)', '055가 대상 칸을 비우고 "탈퇴한 이용자"로, 메모의 닉네임/링크 주소를 지움. NOTICE의 "처리 기록" 줄 수 = 합계'
  union all select 8, '참고: 그 처리 기록 중 닉네임 바꾸기(rename_member) 줄 (메모의 "옛 -> 새" 부분을 지움)',
    (select count(*)::text from public.moderation_log m
      where m.action = 'rename_member' and m.target_kind = 'user' and m.target_id is not null
        and m.target_nickname is distinct from '탈퇴한 이용자'
        and not exists (select 1 from public.profiles p where p.id::text = m.target_id)),
    '(이 값을 적어 둠)', '7번 회원 수에 들어 있음'
  union all select 9, '적어 둘 값: 빌드 추천 줄 수 / 빌드 추천 수 합 / 비추천 수 합',
    (select count(*)::text from public.build_votes) || ' / '
      || (select coalesce(sum(up_count), 0)::text from public.builds) || ' / '
      || (select coalesce(sum(down_count), 0)::text from public.builds),
    '(이 값을 적어 둠)', '055 뒤 같아야 함 (추천 줄은 지우지 않고 키만 바꿈)'
  union all select 10, '적어 둘 값: 글 추천 줄 수 / 글 추천 수 합',
    (select count(*)::text from public.post_votes) || ' / ' || (select coalesce(sum(up_count), 0)::text from public.posts),
    '(이 값을 적어 둠)', '055 뒤 같아야 함'
  union all select 11, '적어 둘 값: 장인 신청 기록 줄 수 (전체 / user_id가 빈 줄)',
    (select count(*)::text from public.influencer_applications) || ' / '
      || (select count(*)::text from public.influencer_applications where user_id is null),
    '(이 값을 적어 둠)', '055는 줄을 지우지 않는다(칸만 비움) - 055 뒤 같아야 함'
  union all select 12, '적어 둘 값: 처리 기록 줄 수 (전체 / 대상이 "탈퇴한 이용자"인 줄)',
    (select count(*)::text from public.moderation_log) || ' / '
      || (select count(*)::text from public.moderation_log where target_nickname = '탈퇴한 이용자'),
    '(이 값을 적어 둠)', '055 뒤 전체는 같고, "탈퇴한 이용자"는 7번 합계만큼 늘어야 함'
  union all select 13, '적어 둘 값: 회원 수 (전체 / 인증된 장인)',
    (select count(*)::text from public.profiles) || ' / ' || (select count(*)::text from public.profiles where influencer is not null),
    '(이 값을 적어 둠)', '055는 회원을 지우지 않는다'
) rows
order by ord;
