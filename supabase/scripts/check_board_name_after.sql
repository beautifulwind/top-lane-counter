-- =====================================================================
-- 057(xp_rules 메모의 "자유게시판" -> "탑신병자 커뮤니티") 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 057을 실행한 뒤 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~5번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요.
--   - 6~9번: 실행 전 check_board_name_before.sql의 6~9번에 적어 둔 값과 같아야 한다.
--     (그 사이 사이트에서 운영자가 xp_rules를 고쳤다면 달라질 수 있다 - 그때는 알려 주세요.)
--   - 11~21번: 바뀐 11줄의 key와 새 문구 전체다. before의 11~21번과 눈으로 비교할 수 있다.
-- =====================================================================
with keys(key) as (
  values ('post'), ('post_daily_cap'), ('comment'), ('comment_daily_cap'), ('post_interval'), ('comment_interval'),
         ('post_edit_minutes'), ('comment_edit_minutes'), ('media_post_max'), ('media_post_gif_max'), ('media_comment_max')
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, 'xp_rules 메모에 "자유게시판"이 남은 줄 수' as what,
    (select count(*)::text from public.xp_rules where note like '%자유게시판%') as now_value,
    '0' as ok_value, '0이 아니면 057이 안 돈 줄이 있다' as memo
  union all select 2, '11개 key 중 새 문구("탑신병자 커뮤니티")가 든 줄 수',
    (select count(*)::text from public.xp_rules where key in (select key from keys) and note like '%탑신병자 커뮤니티%'),
    '11', '실제 줄 수가 11이 아니었다면 before 2번 값과 같아야 한다'
  union all select 3, '11개 key가 모두 있고 메모가 비어 있지 않은 줄 수',
    (select count(*)::text from public.xp_rules where key in (select key from keys) and btrim(note) <> ''),
    '11', ''
  union all select 4, '새 문구 앞뒤가 어색한 곳 ("탑신병자 커뮤니티" 바로 뒤에 글자가 붙은 줄 수)',
    (select count(*)::text from public.xp_rules where note ~ '탑신병자 커뮤니티[가-힣]'),
    '0', '0이 아니면 그 줄의 조사를 확인'
  union all select 5, '참고: 11개 key 중 "게시판"이라는 글자가 든 줄 수',
    (select count(*)::text from public.xp_rules where key in (select key from keys) and note like '%게시판%'),
    '0', '057은 "자유게시판"만 바꾼다. 0이 아니면 옛 이름 "게시판"만 남은 줄이 있다는 뜻이라 알려 주세요'
  union all select 6, 'xp_rules 전체 줄 수',
    (select count(*)::text from public.xp_rules), '(before 6번 값)', '057은 줄을 넣거나 지우지 않는다'
  union all select 7, '11개 key 밖 줄의 지문 (key, 숫자, 메모 전부)',
    coalesce((select md5(string_agg(key || '|' || value::text || '|' || note, E'\n' order by key))
                from public.xp_rules where key not in (select key from keys)), '없음'),
    '(before 7번 값)', '같으면 다른 줄은 안 바뀜'
  union all select 8, '11개 key의 숫자(value) 지문',
    coalesce((select md5(string_agg(key || '|' || value::text, E'\n' order by key))
                from public.xp_rules where key in (select key from keys)), '없음'),
    '(before 8번 값)', '같으면 숫자는 안 바뀜'
  union all select 9, '11개 key 메모의 지금 지문',
    coalesce((select md5(string_agg(key || '|' || note, E'\n' order by key))
                from public.xp_rules where key in (select key from keys)), '없음'),
    '(before 9번 값)', '같으면 "자유게시판"만 바뀌고 다른 글자는 그대로'
  union all
  select 10 + row_number() over (order by r.key), '바뀐 줄: ' || r.key, r.note, '(before의 같은 key 줄과 비교)', ''
    from public.xp_rules r where r.key in (select key from keys)
) rows
order by ord;
