-- =====================================================================
-- 064(장인 인증 신청 사진) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 064를 실행한 뒤 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~11번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요.
--   - 12~15번: 실행 전 check_application_photo_before.sql의 7~10번에 적어 둔 값과 같아야 한다.
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '신청 표 새 칸 / 새 검사 / 사진이 붙은 신청 수' as what,
    (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'influencer_applications'
      and column_name in ('photo_path', 'photo_updated_at'))
      || ' / ' || (select count(*) from pg_constraint where conrelid = 'public.influencer_applications'::regclass
                    and conname in ('influencer_applications_photo_pair', 'influencer_applications_photo_pending'))
      || ' / ' || (select count(*) from public.influencer_applications where photo_path is not null) as now_value,
    '2 / 2 / 0' as ok_value, '064 직후 (아직 아무도 신청 사진을 올리지 않음)' as memo
  union all select 2, '신청 표: 로그인 사람 쓰기 권한 없음 (update / insert)',
    has_table_privilege('authenticated', 'public.influencer_applications', 'update')::text
      || ' / ' || has_table_privilege('authenticated', 'public.influencer_applications', 'insert')::text,
    'false / false', '읽기는 원래대로 본인·운영자만 (RLS)'
  union all select 3, '트리거 (신청이 끝나면 비우기 / 옛 사진 대기열)',
    (select count(*) filter (where tgname = 'influencer_applications_photo_end') || ' / '
            || count(*) filter (where tgname = 'influencer_applications_photo_changed')
       from pg_trigger where not tgisinternal and tgrelid = 'public.influencer_applications'::regclass),
    '1 / 1', null
  union all select 4, 'Storage 규칙 (올리기 / 보기 / 지우기) + 보기 규칙에 운영자 심사 조건',
    (select string_agg(cmd, ' / ' order by case cmd when 'INSERT' then 1 when 'SELECT' then 2 else 3 end)
       from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'profile-photos%')
      || ' + ' || coalesce((select (qual like '%profile_photo_reviewable%')::text from pg_policies
                             where schemaname = 'storage' and tablename = 'objects' and policyname = 'profile-photos 보기'), '없음'),
    'INSERT / SELECT / DELETE + true', '고치기(UPDATE) 규칙은 없어야 함'
  union all select 5, '로그인 사람이 부를 수 있음 (신청 사진 정하기 / 지우기 / 새 승인 / 옛 승인)',
    has_function_privilege('authenticated', 'public.set_application_photo(text)', 'execute')::text
      || ' / ' || has_function_privilege('authenticated', 'public.clear_application_photo()', 'execute')::text
      || ' / ' || has_function_privilege('authenticated', 'public.approve_influencer(bigint,text,text,boolean)', 'execute')::text
      || ' / ' || has_function_privilege('authenticated', 'public.approve_influencer(bigint,text)', 'execute')::text,
    'true / true / true / true', '승인은 안에서 운영자인지 다시 검사한다'
  union all select 6, '비로그인은 못 부름 (정하기 / 지우기 / 새 승인)',
    has_function_privilege('anon', 'public.set_application_photo(text)', 'execute')::text
      || ' / ' || has_function_privilege('anon', 'public.clear_application_photo()', 'execute')::text
      || ' / ' || has_function_privilege('anon', 'public.approve_influencer(bigint,text,text,boolean)', 'execute')::text,
    'false / false / false', null
  union all select 7, '안쪽·트리거 함수는 아무도 못 부름 (부를 수 있는 수)',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('approve_influencer_unchecked', 'application_photo_clear_on_end', 'application_photo_after_change')
        and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))),
    '0', null
  union all select 8, '운영자 심사 보기 함수 (보기 규칙이 부름 - 비로그인 / 로그인 실행 가능)',
    has_function_privilege('anon', 'public.profile_photo_reviewable(text)', 'execute')::text
      || ' / ' || has_function_privilege('authenticated', 'public.profile_photo_reviewable(text)', 'execute')::text,
    'true / true', '운영자가 아니면 늘 false를 돌려준다'
  union all select 9, '정리 함수가 심사 중 신청 사진을 지우지 않음 (목록 / 완료) + service_role만',
    (select (p.prosrc like '%influencer_applications%')::text from pg_proc p where p.oid = 'public.profile_photo_cleanup_list(integer)'::regprocedure)
      || ' / ' || (select (p.prosrc like '%influencer_applications%')::text from pg_proc p where p.oid = 'public.profile_photo_cleanup_done(text[])'::regprocedure)
      || ' + ' || has_function_privilege('service_role', 'public.profile_photo_cleanup_list(integer)', 'execute')::text
      || ' / ' || has_function_privilege('authenticated', 'public.profile_photo_cleanup_list(integer)', 'execute')::text,
    'true / true + true / false', 'Edge Function은 다시 배포하지 않아도 된다'
  union all select 10, '올리기 이유·내 장인 상태·운영자 목록이 신청 사진을 앎',
    (select (p.prosrc like '%influencer_applications%')::text from pg_proc p where p.oid = 'public.profile_photo_upload_problem()'::regprocedure)
      || ' / ' || (select (p.prosrc like '%photo_ready%')::text from pg_proc p where p.oid = 'public.my_influencer_status()'::regprocedure)
      || ' / ' || (select (p.prosrc like '%photo_path%')::text from pg_proc p
                    where p.oid = 'public.admin_influencer_applications_unchecked(text,integer,integer)'::regprocedure),
    'true / true / true', null
  union all select 11, '새·바꾼 함수 search_path 고정 (빠진 수) / 공개 보기 함수는 그대로',
    (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname in ('set_application_photo', 'clear_application_photo', 'profile_photo_reviewable', 'application_photo_clear_on_end',
                          'application_photo_after_change', 'approve_influencer', 'approve_influencer_unchecked', 'my_influencer_status',
                          'admin_influencer_applications_unchecked', 'profile_photo_upload_problem', 'profile_photo_deletable',
                          'profile_photo_cleanup_list', 'profile_photo_cleanup_done')
        and coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=%')
      || ' / ' || (select (p.prosrc not like '%influencer_applications%')::text from pg_proc p where p.oid = 'public.profile_photo_visible(text)'::regprocedure),
    '0 / true', '누구나 보는 사진은 여전히 장인의 지금 사진뿐'
  union all select 12, '장인 인증 신청 수 (전체 / 심사 중)',
    (select count(*) || ' / ' || count(*) filter (where status = 'pending') from public.influencer_applications),
    '(실행 전 7번과 같음)', null
  union all select 13, '회원 수 (프로필 / 장인 / 사진 있는 장인)',
    (select count(*) || ' / ' || count(*) filter (where influencer is not null) || ' / ' || count(*) filter (where photo_path is not null) from public.profiles),
    '(실행 전 8번과 같음)', null
  union all select 14, '프로필 사진 파일 수 (profile-photos) / 지울 파일 대기열',
    (select count(*) from storage.objects where bucket_id = 'profile-photos') || ' / ' || (select count(*) from public.profile_photo_trash),
    '(실행 전 9번과 같음)', null
  union all select 15, '알림 수 / 처리 기록 수',
    (select count(*) from public.notifications) || ' / ' || (select count(*) from public.moderation_log),
    '(실행 전 10번과 같음)', null
) rows
order by ord;
