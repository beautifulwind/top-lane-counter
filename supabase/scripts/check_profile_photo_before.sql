-- =====================================================================
-- 062(장인 프로필 사진) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 062를 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~6번: [지금 값]이 [정상 값]과 모두 맞으면 062를 실행해도 된다. 하나라도 다르면 실행하지 말고 알려 주세요.
--   - 7~10번은 "적어 둘 값"이다. 062 실행 뒤 check_profile_photo_after.sql의 같은 이름 줄과 비교한다(같아야 한다).
--     (그 사이 사이트에서 누가 활동하면 달라질 수 있다 - 사람이 적은 시간에 이어서 실행해 주세요.)
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '061 실행됨 (차단 표 user_blocks 있음)' as what,
    coalesce(to_regclass('public.user_blocks')::text, '없음') as now_value, 'user_blocks' as ok_value, '없음이면 061부터 실행' as memo
  union all select 2, '프로필 사진 칸 profiles.photo_path가 아직 없음',
    (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name in ('photo_path', 'photo_updated_at')),
    '0', '0이 아니면 062를 이미 실행한 것 - 다시 실행하지 말 것'
  union all select 3, '062가 만들 표(profile_photo_reports·profile_photo_trash·profile_photo_changes)가 이미 있는 수',
    (select count(*)::text from unnest(array['public.profile_photo_reports', 'public.profile_photo_trash', 'public.profile_photo_changes']) t where to_regclass(t) is not null),
    '0', null
  union all select 4, '062가 만들 함수가 이미 있는 수',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('set_profile_photo', 'clear_profile_photo', 'remove_profile_photo', 'report_profile_photo',
        'admin_profile_photo_reports', 'dismiss_profile_photo_reports', 'profile_photo_upload_problem', 'profile_photo_visible',
        'profile_photo_deletable', 'profile_photo_cleanup_list', 'profile_photo_cleanup_done')), '0', null
  union all select 5, '버킷 profile-photos와 그 Storage 규칙이 아직 없음 (버킷 수 / 규칙 수)',
    (select count(*) from storage.buckets where id = 'profile-photos') || ' / '
      || (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'profile-photos%'),
    '0 / 0', '버킷이 이미 있으면(대시보드에서 만든 경우) 062가 설정만 맞춘다 - 알려 주세요'
  union all select 6, '062가 바꿀 함수 모양 (public_profile / push_group)',
    (select string_agg(p.oid::regprocedure::text, ' / ' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('public_profile', 'push_group')),
    'public_profile(text) / push_group(text)', null
  union all select 7, '적어 둘 값: 회원 수 (프로필 / 장인)',
    (select count(*) || ' / ' || count(*) filter (where influencer is not null) from public.profiles),
    '(이 값을 적어 둠)', '062 뒤 같아야 함'
  union all select 8, '적어 둘 값: 알림 수 (전체 / link_removed / report_received)',
    (select count(*) || ' / ' || count(*) filter (where kind = 'link_removed') || ' / ' || count(*) filter (where kind = 'report_received') from public.notifications),
    '(이 값을 적어 둠)', '062 뒤 같아야 함 (062는 알림을 만들거나 지우지 않는다)'
  union all select 9, '적어 둘 값: 처리 기록 수',
    (select count(*)::text from public.moderation_log), '(이 값을 적어 둠)', '062 뒤 같아야 함'
  union all select 10, '적어 둘 값: 커뮤니티 사진 파일 수 (board-media) / 지울 파일 대기열',
    (select count(*) from storage.objects where bucket_id = 'board-media') || ' / ' || (select count(*) from public.storage_trash),
    '(이 값을 적어 둠)', '062 뒤 같아야 함 (매일 정리가 돌면 줄어들 수 있음)'
) rows
order by ord;
