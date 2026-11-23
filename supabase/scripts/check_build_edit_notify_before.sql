-- =====================================================================
-- 067(빌드 수정 알림) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 067을 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~6번: [지금 값]이 [정상 값]과 모두 맞으면 067을 실행해도 된다. 하나라도 다르면 실행하지 말고 알려 주세요.
--   - 7~11번은 "적어 둘 값"이다. 067 실행 뒤 check_build_edit_notify_after.sql의 같은 이름 줄과 비교한다(같아야 한다 - 067은 기존 데이터를 바꾸지 않는다).
--     (그 사이 사이트에서 누가 빌드를 고치거나 추천하거나 알림이 생기면 달라질 수 있다 - 사람이 적은 시간에 이어서 실행해 주세요.)
--   - 알림(11번)은 "실행 직후 기준"이다: 067 뒤에는 누가 빌드를 고칠 때마다 새 알림(build_edited)이 생기는 것이 정상이라,
--     실행 뒤 표에는 "build_edited를 뺀 알림" 줄(바뀌면 안 됨)도 따로 있다.
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '066 실행됨 (빌드 저장 표 build_bookmarks 있음)' as what,
    coalesce(to_regclass('public.build_bookmarks')::text, '없음') as now_value, 'build_bookmarks' as ok_value, '없음이면 066부터 실행' as memo
  union all select 2, '067 아직 안 함 (짝 표 build_edit_notices 없음)',
    coalesce(to_regclass('public.build_edit_notices')::text, '없음'), '없음', '있으면 067을 이미 실행한 것 - 다시 실행하지 말고 알려 주세요'
  union all select 3, '067이 만들 칸·함수·트리거 이름이 비어 있음 (설정 칸 build_edits / 함수 3개 / 트리거)',
    (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'push_settings' and column_name = 'build_edits')
      || ' / ' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
                    and p.proname in ('notify_build_edit', 'build_edit_message', 'build_revisions_notify', 'build_edit_notices_rerender'))
      || ' / ' || (select count(*) from pg_trigger where tgname in ('build_revisions_notify', 'build_edit_notices_rerender')),
    '0 / 0 / 0', null
  union all select 4, '알림 종류 목록에 build_edited 없음 / 푸시 묶음 없음',
    (pg_get_constraintdef((select oid from pg_constraint where conrelid = 'public.notifications'::regclass and conname = 'notifications_kind_check')) like '%build_edited%')::text
      || ' / ' || coalesce(public.push_group('build_edited'), '없음'),
    'false / 없음', null
  union all select 5, '067이 쓰는 표·칸 (수정 기록 kind·editor_id / 기여자 last_at / 차단 / 알림 설정)',
    (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'build_revisions' and column_name in ('kind', 'editor_id', 'build_id'))
      || ' / ' || (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'build_editors' and column_name in ('user_id', 'last_at'))
      || ' / ' || coalesce(to_regclass('public.user_blocks')::text, '없음') || ' / ' || coalesce(to_regclass('public.push_settings')::text, '없음'),
    '3 / 2 / user_blocks / push_settings', null
  union all select 6, '운영자(admin) 수 / 감독관 수 (받는 사람 확인용)',
    (select count(*) filter (where role = 'admin') || ' / ' || count(*) filter (where role = 'moderator') from public.profiles),
    '1 / (몇 명이든)', '운영자는 1명뿐(profiles_one_operator)'
  union all select 7, '적어 둘 값: 빌드 (줄 수 / 가장 큰 id / 추천 수 합계 / 비추천 수 합계 / 내용 지문)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || coalesce(sum(up_count), 0) || ' / ' || coalesce(sum(down_count), 0)
       || ' / ' || md5(coalesce(string_agg(b::text, '|' order by b.id), '')) from public.builds b),
    '(이 값을 적어 둠)', '067 뒤 같아야 함'
  union all select 8, '적어 둘 값: 빌드 추천·비추천 (줄 수 / 추천 줄 / 비추천 줄 / 내용 지문)',
    (select count(*) || ' / ' || count(*) filter (where value = 1) || ' / ' || count(*) filter (where value = -1)
       || ' / ' || md5(coalesce(string_agg(v::text, '|' order by v.build_id, v.user_id::text), '')) from public.build_votes v),
    '(이 값을 적어 둠)', '067 뒤 같아야 함'
  union all select 9, '적어 둘 값: 빌드 수정 기록 (줄 수 / 가장 큰 id / 내용 지문)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || md5(coalesce(string_agg(r::text, '|' order by r.id), '')) from public.build_revisions r),
    '(이 값을 적어 둠)', '067 뒤 같아야 함'
  union all select 10, '적어 둘 값: 알림 설정 (줄 수 / 기존 칸 7개만 이름으로 직접 골라 비교: user_id·staff_new·my_results·follow_builds·notice·new_followers·updated_at / 내용 지문)',
    (select count(*) || ' / 비교 칸 ' || (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'push_settings' and column_name in ('user_id','staff_new','my_results','follow_builds','notice','new_followers','updated_at')) || '개 / ' || md5(coalesce(string_agg(concat_ws(',', s.user_id, s.staff_new, s.my_results, s.follow_builds, s.notice, s.new_followers, s.updated_at), '|' order by s.user_id::text), ''))
       from public.push_settings s),
    '(이 값을 적어 둠)', '067 뒤 같아야 함'
  union all select 11, '적어 둘 값: 알림 (줄 수 / 가장 큰 id / 내용 지문 - 읽음 표시는 빼고)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / '
       || md5(coalesce(string_agg(concat_ws(',', n.id, n.user_id, n.kind, n.message, n.created_at, n.proposal_id, n.build_id, n.post_id, n.counter_id), '|' order by n.id), ''))
       from public.notifications n),
    '(이 값을 적어 둠)', '067 실행 직후 같아야 함 (그 뒤에는 빌드 수정 알림만큼 늘어나는 것이 정상)'
) x
order by ord;
