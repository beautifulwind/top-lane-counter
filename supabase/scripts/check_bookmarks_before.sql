-- =====================================================================
-- 066(빌드 저장·북마크) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 066을 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~4번: [지금 값]이 [정상 값]과 모두 맞으면 066을 실행해도 된다. 하나라도 다르면 실행하지 말고 알려 주세요.
--   - 5~8번은 "적어 둘 값"이다. 066 실행 뒤 check_bookmarks_after.sql의 같은 이름 줄과 비교한다(같아야 한다 - 066은 기존 데이터를 바꾸지 않는다).
--     (그 사이 사이트에서 누가 빌드를 고치거나 추천하거나 알림이 생기면 달라질 수 있다 - 사람이 적은 시간에 이어서 실행해 주세요.)
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '065 실행됨 (빌드 스킬 순서 칸 builds.skill_sequence 있음)' as what,
    (exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'builds' and column_name = 'skill_sequence'))::text as now_value,
    'true' as ok_value, 'false면 065부터 실행' as memo
  union all select 2, '066 아직 안 함 (저장 표 build_bookmarks 없음)',
    coalesce(to_regclass('public.build_bookmarks')::text, '없음'), '없음', '있으면 066을 이미 실행한 것 - 다시 실행하지 말고 알려 주세요'
  union all select 3, '066이 만들 함수 이름이 비어 있음 (save_build·unsave_build·my_saved_builds·save_build_limit)',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('save_build', 'unsave_build', 'my_saved_builds', 'save_build_limit')),
    '0', null
  union all select 4, '066이 연결할 표 (프로필 / 빌드 / 상대법)',
    coalesce(to_regclass('public.profiles')::text, '없음') || ' / ' || coalesce(to_regclass('public.builds')::text, '없음')
      || ' / ' || coalesce(to_regclass('public.counters')::text, '없음'),
    'profiles / builds / counters', null
  union all select 5, '적어 둘 값: 빌드 (줄 수 / 가장 큰 id / 추천 수 합계 / 비추천 수 합계 / 내용 지문)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || coalesce(sum(up_count), 0) || ' / ' || coalesce(sum(down_count), 0)
       || ' / ' || md5(coalesce(string_agg(b::text, '|' order by b.id), '')) from public.builds b),
    '(이 값을 적어 둠)', '066 뒤 같아야 함'
  union all select 6, '적어 둘 값: 빌드 추천·비추천 (줄 수 / 추천 줄 / 비추천 줄 / 내용 지문)',
    (select count(*) || ' / ' || count(*) filter (where value = 1) || ' / ' || count(*) filter (where value = -1)
       || ' / ' || md5(coalesce(string_agg(v::text, '|' order by v.build_id, v.user_id::text), '')) from public.build_votes v),
    '(이 값을 적어 둠)', '066 뒤 같아야 함'
  union all select 7, '적어 둘 값: 빌드 수정 기록 (줄 수 / 가장 큰 id / 내용 지문)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || md5(coalesce(string_agg(r::text, '|' order by r.id), '')) from public.build_revisions r),
    '(이 값을 적어 둠)', '066 뒤 같아야 함'
  union all select 8, '적어 둘 값: 알림 (줄 수 / 가장 큰 id / 내용 지문 - 읽음 표시는 빼고)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / '
       || md5(coalesce(string_agg(concat_ws(',', n.id, n.user_id, n.kind, n.message, n.created_at, n.proposal_id, n.build_id, n.post_id, n.counter_id), '|' order by n.id), ''))
       from public.notifications n),
    '(이 값을 적어 둠)', '066 뒤 같아야 함'
) x
order by ord;
