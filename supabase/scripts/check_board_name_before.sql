-- =====================================================================
-- 057(xp_rules 메모의 "자유게시판" -> "탑신병자 커뮤니티") 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 057을 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~6번: [지금 값]이 [정상 값]과 모두 맞으면 057을 실행해도 된다. 하나라도 다르면 실행하지 말고 알려 주세요.
--   - 7~9번은 "적어 둘 값"이다. 057 실행 뒤 check_board_name_after.sql의 같은 이름 줄과 비교한다.
--   - 11~21번: "자유게시판"이 들어 있는 줄의 key와 지금 문구 전체다. 되돌릴 때 쓰도록 이 결과를 복사해 두면 좋다.
-- =====================================================================
with keys(key) as (
  values ('post'), ('post_daily_cap'), ('comment'), ('comment_daily_cap'), ('post_interval'), ('comment_interval'),
         ('post_edit_minutes'), ('comment_edit_minutes'), ('media_post_max'), ('media_post_gif_max'), ('media_comment_max')
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, 'xp_rules 표의 메모 칸 이름 / 글자 형식' as what,
    (select string_agg(column_name || ' ' || data_type, ', ' order by ordinal_position)
       from information_schema.columns where table_schema = 'public' and table_name = 'xp_rules' and column_name = 'note') as now_value,
    'note text' as ok_value, '메모는 note 칸 하나' as memo
  union all select 2, 'note에 "자유게시판"이 들어 있는 줄 수',
    (select count(*)::text from public.xp_rules where note like '%자유게시판%'),
    '11', '11이 아니면 실행하지 말고 알려 주세요 (줄 목록은 11~21번)'
  union all select 3, '그 줄이 057의 11개 key와 같은지 (모자란 key 수 / 넘치는 key 수)',
    (select count(*)::text from keys k where not exists (select 1 from public.xp_rules r where r.key = k.key and r.note like '%자유게시판%'))
      || ' / '
      || (select count(*)::text from public.xp_rules r where r.note like '%자유게시판%' and r.key not in (select key from keys)),
    '0 / 0', '넘치는 key가 있으면 057이 그 줄은 안 바꾼다 - 알려 주세요'
  union all select 4, '그 줄에 이미 "탑신병자 커뮤니티"가 있는 줄 수',
    (select count(*)::text from public.xp_rules where key in (select key from keys) and note like '%탑신병자 커뮤니티%'),
    '0', '0이 아니면 되돌리기가 그 글자도 바꾼다'
  union all select 5, '조사가 어색해질 줄 수 ("자유게시판" 바로 뒤에 은/는/이/가/을/를/과/와/로/의/에/도/만 등이 붙은 줄)',
    (select count(*)::text from public.xp_rules
      where note ~ '자유게시판(은|는|이|가|을|를|과|와|으로|로|이나|이라|라|의|에|도|만|까지|부터|처럼)'),
    '0', '0이 아니면 그 줄은 057 뒤 조사를 손으로 고쳐야 한다'
  union all select 6, 'xp_rules 전체 줄 수',
    (select count(*)::text from public.xp_rules), '(이 값을 적어 둠)', '057은 줄을 넣거나 지우지 않는다'
  union all select 7, '적어 둘 값: 11개 key 밖 줄의 지문 (key, 숫자, 메모 전부)',
    coalesce((select md5(string_agg(key || '|' || value::text || '|' || note, E'\n' order by key))
                from public.xp_rules where key not in (select key from keys)), '없음'),
    '(이 값을 적어 둠)', '057 뒤 같아야 함 = 다른 줄은 안 바뀜'
  union all select 8, '적어 둘 값: 11개 key의 숫자(value) 지문',
    coalesce((select md5(string_agg(key || '|' || value::text, E'\n' order by key))
                from public.xp_rules where key in (select key from keys)), '없음'),
    '(이 값을 적어 둠)', '057 뒤 같아야 함 = 숫자는 안 바뀜'
  union all select 9, '057 뒤 11개 key 메모의 예상 지문 (지금 메모에서 "자유게시판"만 바꾼 것)',
    coalesce((select md5(string_agg(key || '|' || replace(note, '자유게시판', '탑신병자 커뮤니티'), E'\n' order by key))
                from public.xp_rules where key in (select key from keys)), '없음'),
    '(이 값을 적어 둠)', '057 뒤 check_board_name_after.sql 9번 줄의 지금 값과 같아야 함 = 글자 말고는 안 바뀜'
  union all
  select 10 + row_number() over (order by r.key), '자유게시판이 든 줄: ' || r.key, r.note, '(되돌릴 때 쓸 원래 문구)', ''
    from public.xp_rules r where r.note like '%자유게시판%'
) rows
order by ord;
