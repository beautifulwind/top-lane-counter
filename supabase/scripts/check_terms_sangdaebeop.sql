-- =====================================================================
-- 041(용어 정리 "카운터" → "상대법") 확인 조회 (읽기만 — 아무것도 바꾸지 않는다).
-- 041 실행 "전"과 "후"에 한 번씩 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다.
-- [지금 값]이 [실행 전 정상]·[실행 후 정상]과 맞는지 본다.
--   - 1번이 실행 후에도 0이 아니면 그 함수 이름을 11번에서 확인한다 (대부분 주석이 아니라 문장이 남은 것).
--   - 3~5번(알림·처리 기록·경험치 내역)은 041이 건드리지 않으므로 실행 전과 같은 값이어야 한다. 실행 전 값을 적어 둔다.
--   - 041에는 따로 등록할 pg_cron 일정이 없다.
-- =====================================================================
select ord as "순서", item as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상"
from (
  select 1 as ord, '본문에 "카운터"가 남은 함수 수' as item,
    (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f' and prosrc like '%카운터%') as now_value,
    '1 이상 (옛 문구)' as before_ok, '0' as after_ok
  union all select 2, '본문에 "상대법"이 들어간 함수 수',
    (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f' and prosrc like '%상대법%'),
    '(적어 두기)', '실행 전보다 늘어남'
  union all select 3, '저장된 알림 중 "카운터"가 있는 것 (041은 안 건드림)',
    (select count(*)::text from public.notifications where message like '%카운터%'), '(적어 두기)', '실행 전과 같음'
  union all select 4, '처리 기록 중 "카운터"가 있는 것 (041은 안 건드림)',
    (select count(*)::text from public.moderation_log where note like '%카운터%'), '(적어 두기)', '실행 전과 같음'
  union all select 5, '경험치 내역 중 "카운터"가 있는 것 (041은 안 건드림)',
    (select count(*)::text from public.xp_events where reason like '%카운터%'), '(적어 두기)', '실행 전과 같음'
  union all select 6, '조사가 틀린 모양("상대법를·는·가·로·와")이 있는 함수 수',
    (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and prosrc ~ '상대법(를|는|가|로|와)([^가-힣]|$)'),
    '0', '0'
  union all select 7, '함수 개수 (041은 늘리거나 줄이지 않음)',
    (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f'), '(적어 두기)', '실행 전과 같음'
  union all select 8, '숨긴 상대법 재검토 요청 문장 예: request_revision',
    coalesce((select substring(prosrc from '''[^'']*재검토를 요청할 수 있습니다[^'']*''') from pg_proc where proname = 'request_revision' and pronamespace = 'public'::regnamespace), '없음'),
    '''숨긴 카운터만 …''', '''숨긴 상대법만 …'''
  union all select 9, '삭제 확인 문장 예: delete_counter',
    coalesce((select substring(prosrc from '''[^'']*삭제할 수 있습니다[^'']*''') from pg_proc where proname = 'delete_counter' and pronamespace = 'public'::regnamespace), '없음'),
    '''숨긴 카운터만 …''', '''숨긴 상대법만 …'''
  union all select 10, '새 문서 댓글 알림 문장 예: create_doc_comment',
    coalesce((select substring(prosrc from '''내가 제안한 [^'']*문서에 새 댓글이 달렸습니다\.''') from pg_proc where proname = 'create_doc_comment' and pronamespace = 'public'::regnamespace), '없음'),
    '''내가 제안한 카운터 문서에 …''', '''내가 제안한 상대법 문서에 …'''
  union all select 11, '아직 "카운터"가 남은 함수 이름 (없으면 빈칸)',
    coalesce((select string_agg(oid::regprocedure::text, ', ' order by 1) from pg_proc
              where pronamespace = 'public'::regnamespace and prokind = 'f' and prosrc like '%카운터%'), ''),
    '(옛 문구 함수들)', ''
) rows
order by ord;
