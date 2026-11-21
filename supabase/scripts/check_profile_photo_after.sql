-- =====================================================================
-- 062(장인 프로필 사진) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 062를 실행한 뒤 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~13번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요.
--   - 14~17번: 실행 전 check_profile_photo_before.sql의 7~10번에 적어 둔 값과 같아야 한다.
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '버킷 profile-photos (비공개 / 파일당 바이트 / 형식)' as what,
    coalesce((select (case when public then '공개' else '비공개' end) || ' / ' || file_size_limit || ' / ' || array_to_string(allowed_mime_types, ',')
                from storage.buckets where id = 'profile-photos'), '없음') as now_value,
    '비공개 / 1048576 / image/webp,image/jpeg' as ok_value, null as memo
  union all select 2, 'Storage 규칙 (올리기 / 보기 / 지우기)',
    (select string_agg(cmd, ' / ' order by case cmd when 'INSERT' then 1 when 'SELECT' then 2 else 3 end)
       from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'profile-photos%'),
    'INSERT / SELECT / DELETE', '고치기(UPDATE) 규칙은 없어야 함'
  union all select 3, '프로필 칸 photo_path / photo_updated_at + 사진 수',
    (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name in ('photo_path', 'photo_updated_at'))
      || ' / ' || (select count(*) from public.profiles where photo_path is not null),
    '2 / 0', '062 직후 (아직 아무도 사진을 올리지 않음)'
  union all select 4, '사진 칸은 사용자가 직접 못 고침 (로그인 사람 update 권한)',
    (has_column_privilege('authenticated', 'public.profiles', 'photo_path', 'update'))::text, 'false', null
  union all select 5, '프로필 검사 3개 (짝 / 경로 모양 / 장인만)',
    (select count(*)::text from pg_constraint where conrelid = 'public.profiles'::regclass
      and conname in ('profiles_photo_pair', 'profiles_photo_path_shape', 'profiles_photo_influencer')), '3', null
  union all select 6, '새 표 3개 RLS 켜짐 + 로그인·비로그인 직접 권한 없음 (권한 있는 수)',
    (select count(*) filter (where c.relrowsecurity) from pg_class c
      where c.oid in ('public.profile_photo_reports'::regclass, 'public.profile_photo_trash'::regclass, 'public.profile_photo_changes'::regclass))
      || ' / ' || (select count(*) from unnest(array['public.profile_photo_reports', 'public.profile_photo_trash', 'public.profile_photo_changes']) tb,
                    unnest(array['select', 'insert', 'update', 'delete']) pr, unnest(array['anon', 'authenticated']) r
                   where has_table_privilege(r, tb, pr)),
    '3 / 0', null
  union all select 7, '트리거 (인증 해제 / 사진 바뀜 / 탈퇴 / 신고 알림)',
    (select count(*) filter (where tgname = 'profiles_photo_on_influencer_end') || ' / ' || count(*) filter (where tgname = 'profiles_photo_changed')
            || ' / ' || count(*) filter (where tgname = 'profiles_photo_on_delete') || ' / ' || count(*) filter (where tgname = 'profile_photo_reports_notify')
       from pg_trigger where not tgisinternal),
    '1 / 1 / 1 / 1', null
  union all select 8, '로그인 사람이 부를 수 있음 (정하기 / 지우기 / 신고 / 운영자 목록 / 운영자 삭제)',
    has_function_privilege('authenticated', 'public.set_profile_photo(text)', 'execute')::text
      || ' / ' || has_function_privilege('authenticated', 'public.clear_profile_photo()', 'execute')::text
      || ' / ' || has_function_privilege('authenticated', 'public.report_profile_photo(uuid,text,text)', 'execute')::text
      || ' / ' || has_function_privilege('authenticated', 'public.admin_profile_photo_reports(integer,integer)', 'execute')::text
      || ' / ' || has_function_privilege('authenticated', 'public.remove_profile_photo(uuid,text)', 'execute')::text,
    'true / true / true / true / true', '운영자 함수는 안에서 운영자인지 다시 검사한다'
  union all select 9, '비로그인은 못 부름 (정하기 / 신고 / 운영자 삭제)',
    has_function_privilege('anon', 'public.set_profile_photo(text)', 'execute')::text
      || ' / ' || has_function_privilege('anon', 'public.report_profile_photo(uuid,text,text)', 'execute')::text
      || ' / ' || has_function_privilege('anon', 'public.remove_profile_photo(uuid,text)', 'execute')::text,
    'false / false / false', null
  union all select 10, '정리 함수는 service_role만 (service_role / 로그인 사람)',
    has_function_privilege('service_role', 'public.profile_photo_cleanup_list(integer)', 'execute')::text
      || ' / ' || has_function_privilege('authenticated', 'public.profile_photo_cleanup_list(integer)', 'execute')::text,
    'true / false', 'Edge Function media-cleanup을 다시 배포해야 이 함수를 부른다'
  union all select 11, '알림 종류·처리 기록 종류·휴대폰 알림 묶음',
    (select (pg_get_constraintdef(oid) like '%profile_photo_removed%')::text from pg_constraint where conname = 'notifications_kind_check')
      || ' / ' || (select (pg_get_constraintdef(oid) like '%remove_profile_photo%')::text from pg_constraint where conname = 'moderation_log_action_check')
      || ' / ' || coalesce(public.push_group('profile_photo_removed'), '없음'),
    'true / true / my_results', null
  union all select 12, '공개 프로필에 사진 경로가 들어감 (public_profile)',
    (select (p.prosrc like '%photo_path%')::text from pg_proc p where p.oid = 'public.public_profile(text)'::regprocedure), 'true', null
  union all select 13, '설정값 profile_photo_daily_max + 새 함수 search_path 고정 (빠진 수)',
    coalesce((select value::text from public.xp_rules where key = 'profile_photo_daily_max'), '없음')
      || ' / ' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and (p.proname like '%profile_photo%' or p.proname in ('notify_staff_new_photo_report', 'public_profile', 'push_group'))
                      and coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=%'),
    '10 / 0', null
  union all select 14, '회원 수 (프로필 / 장인)',
    (select count(*) || ' / ' || count(*) filter (where influencer is not null) from public.profiles), '(실행 전 7번과 같음)', null
  union all select 15, '알림 수 (전체 / link_removed / report_received)',
    (select count(*) || ' / ' || count(*) filter (where kind = 'link_removed') || ' / ' || count(*) filter (where kind = 'report_received') from public.notifications),
    '(실행 전 8번과 같음)', null
  union all select 16, '처리 기록 수', (select count(*)::text from public.moderation_log), '(실행 전 9번과 같음)', null
  union all select 17, '커뮤니티 사진 파일 수 (board-media) / 지울 파일 대기열',
    (select count(*) from storage.objects where bucket_id = 'board-media') || ' / ' || (select count(*) from public.storage_trash),
    '(실행 전 10번과 같음)', null
) rows
order by ord;
