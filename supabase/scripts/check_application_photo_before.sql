-- =====================================================================
-- 064(장인 인증 신청 사진) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 064를 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~6번: [지금 값]이 [정상 값]과 모두 맞으면 064를 실행해도 된다. 하나라도 다르면 실행하지 말고 알려 주세요.
--   - 7~10번은 "적어 둘 값"이다. 064 실행 뒤 check_application_photo_after.sql의 같은 이름 줄과 비교한다(같아야 한다).
--     (그 사이 사이트에서 누가 신청·사진 올리기를 하면 달라질 수 있다 - 사람이 적은 시간에 이어서 실행해 주세요.)
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '062 실행됨 (프로필 사진 대기열 profile_photo_trash 있음)' as what,
    coalesce(to_regclass('public.profile_photo_trash')::text, '없음') as now_value, 'profile_photo_trash' as ok_value, '없음이면 062부터 실행' as memo
  union all select 2, '063 실행됨 (팔로워 목록 함수에 비회원 검사 있음)',
    coalesce((select (p.prosrc like '%is_guest%')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname = 'influencer_followers'), '없음'),
    'true', 'false면 063부터 실행'
  union all select 3, '신청 사진 칸 influencer_applications.photo_path가 아직 없음',
    (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'influencer_applications'
      and column_name in ('photo_path', 'photo_updated_at')),
    '0', '0이 아니면 064를 이미 실행한 것 - 다시 실행하지 말 것'
  union all select 4, '064가 만들 함수가 이미 있는 수',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and (p.proname in ('set_application_photo', 'clear_application_photo', 'profile_photo_reviewable',
                                                    'application_photo_clear_on_end', 'application_photo_after_change')
                                      or (p.proname in ('approve_influencer', 'approve_influencer_unchecked') and p.pronargs = 4))),
    '0', null
  union all select 5, '064가 바꿀 함수 모양 (승인 / 승인 안쪽 / 내 장인 상태 / 운영자 신청 목록)',
    (select string_agg(p.oid::regprocedure::text, ' / ' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('approve_influencer', 'approve_influencer_unchecked', 'my_influencer_status',
                                                   'admin_influencer_applications_unchecked')),
    'admin_influencer_applications_unchecked(text,integer,integer) / approve_influencer(bigint,text) / approve_influencer_unchecked(bigint,text) / my_influencer_status()',
    null
  union all select 6, 'profile-photos Storage 규칙 수 / 보기 규칙에 운영자 심사 조건이 아직 없음',
    (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'profile-photos%') || ' / '
      || coalesce((select (qual like '%profile_photo_reviewable%')::text from pg_policies
                    where schemaname = 'storage' and tablename = 'objects' and policyname = 'profile-photos 보기'), '없음'),
    '3 / false', null
  union all select 7, '적어 둘 값: 장인 인증 신청 수 (전체 / 심사 중)',
    (select count(*) || ' / ' || count(*) filter (where status = 'pending') from public.influencer_applications),
    '(이 값을 적어 둠)', '064 뒤 같아야 함'
  union all select 8, '적어 둘 값: 회원 수 (프로필 / 장인 / 사진 있는 장인)',
    (select count(*) || ' / ' || count(*) filter (where influencer is not null) || ' / ' || count(*) filter (where photo_path is not null) from public.profiles),
    '(이 값을 적어 둠)', '064 뒤 같아야 함'
  union all select 9, '적어 둘 값: 프로필 사진 파일 수 (profile-photos) / 지울 파일 대기열',
    (select count(*) from storage.objects where bucket_id = 'profile-photos') || ' / ' || (select count(*) from public.profile_photo_trash),
    '(이 값을 적어 둠)', '064 뒤 같아야 함 (매일 정리가 돌면 줄어들 수 있음)'
  union all select 10, '적어 둘 값: 알림 수 / 처리 기록 수',
    (select count(*) from public.notifications) || ' / ' || (select count(*) from public.moderation_log),
    '(이 값을 적어 둠)', '064 뒤 같아야 함 (064는 알림·기록을 만들거나 지우지 않는다)'
) rows
order by ord;
