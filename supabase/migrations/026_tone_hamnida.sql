-- =====================================================================
-- 026: 말투 "~해요" → "~합니다" 중 DB 부분 (2026-11-04, SPEC 3장 "화면 공통 규칙")
-- 규칙: 설명·결과는 "~합니다/~습니다/~입니다", 부탁은 "~해 주세요" 그대로, 확인 질문은 "~하시겠습니까?"
-- 1. DB 함수 본문의 오류·알림 문구: 지금 DB에 있는 함수 본문을 아래 낱말 표로 고쳐 다시 만든다 (019·024·025와 같은 방식)
--    낱말 표는 지금 함수 본문에 있는 "~요" 낱말 전부 (부탁 "주세요" 등은 표에 없어서 그대로)
-- 2. 이미 쌓인 알림 글자: 고정 문구 부분만 바꾼다. 글 제목「…」과 운영자 메모(메모: 뒤)는 사람이 쓴 글이라 그대로.
--    (제안·빌드 처리 알림은 메모만 저장돼 있어서 바꾸지 않는다)
-- 025_vote_wording.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다. 여러 번 실행해도 결과는 같다.
-- =====================================================================

begin;

create temp table tone_map (old text primary key, new text not null) on commit drop;
insert into tone_map (old, new) values
    ('챔피언이에요', '챔피언입니다'),
    ('공개됐어요', '공개됐습니다'),
    ('내려갔어요', '내려갔습니다'),
    ('댓글이에요', '댓글입니다'),
    ('등록됐어요', '등록됐습니다'),
    ('바뀌었어요', '바뀌었습니다'),
    ('버전이에요', '버전입니다'),
    ('사진이에요', '사진입니다'),
    ('요청했어요', '요청했습니다'),
    ('잘못됐어요', '잘못됐습니다'),
    ('제안이에요', '제안입니다'),
    ('카운터예요', '카운터입니다'),
    ('회수됐어요', '회수됐습니다'),
    ('고쳤어요', '고쳤습니다'),
    ('글이에요', '글입니다'),
    ('깨졌어요', '깨졌습니다'),
    ('달렸어요', '달렸습니다'),
    ('못했어요', '못했습니다'),
    ('문서예요', '문서입니다'),
    ('보냈어요', '보냈습니다'),
    ('빌드예요', '빌드입니다'),
    ('상태예요', '상태입니다'),
    ('숨겼어요', '숨겼습니다'),
    ('아니에요', '아닙니다'),
    ('얻었어요', '얻었습니다'),
    ('올랐어요', '올랐습니다'),
    ('조사예요', '조사입니다'),
    ('종류예요', '종류입니다'),
    ('중이에요', '중입니다'),
    ('지났어요', '지났습니다'),
    ('필요해요', '필요합니다'),
    ('같아요', '같습니다'),
    ('달라요', '다릅니다'),
    ('않아요', '않습니다'),
    ('없어요', '없습니다'),
    ('있어요', '있습니다'),
    ('적어요', '적습니다'),
    ('커요', '큽니다'),
    ('해요', '합니다');

-- 1. 함수 본문 (긴 낱말부터 바꾼다 — 짧은 낱말이 긴 낱말 안에서 먼저 바뀌지 않게)
do $$
declare
  f record;
  m record;
  def text;
  fixed text;
  n integer := 0;
begin
  for f in
    select p.oid from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.prosrc ~ '[가-힣]요'
  loop
    def := pg_get_functiondef(f.oid);
    fixed := def;
    for m in select old, new from tone_map order by length(old) desc, old loop
      fixed := replace(fixed, m.old, m.new);
    end loop;
    if fixed <> def then
      execute fixed;
      n := n + 1;
    end if;
  end loop;
  raise notice '말투를 고친 함수: %개', n;
end;
$$;

-- 2. 이미 쌓인 알림 (고정 문구만, 처음 한 번만 바꾼다)
-- 숨김: "…」을 운영자가 숨겼어요. 메모:" / "…댓글을 운영자가 숨겼어요. 메모:" (제목 안 글자와 헷갈리지 않게 앞 글자까지 맞춘다)
update public.notifications set message = regexp_replace(message, '(」을 |댓글을 )운영자가 숨겼어요\. 메모: ', '\1운영자가 숨겼습니다. 메모: ')
 where kind in ('post_hidden', 'comment_hidden', 'doc_comment_hidden');
-- 다시 공개: "…」이 다시 공개됐어요. 메모:" / "…」)이 …" / "문서 댓글이 …"
update public.notifications set message = regexp_replace(message, '(」이 |」\)이 |문서 댓글이 )다시 공개됐어요\. 메모: ', '\1다시 공개됐습니다. 메모: ')
 where kind in ('post_restored', 'comment_restored', 'doc_comment_restored');
update public.notifications set message = regexp_replace(message, '달렸어요\.$', '달렸습니다.') where kind in ('post_comment', 'doc_comment') and message ~ '달렸어요\.$';
update public.notifications set message = regexp_replace(message, '^레벨이 올랐어요: ', '레벨이 올랐습니다: ') where kind = 'level_up';
update public.notifications set message = regexp_replace(message, '레벨이 내려갔어요: ', '레벨이 내려갔습니다: ') where kind = 'level_down';
update public.notifications
   set message = regexp_replace(message, ' 얻었어요\. \[마이페이지\]에서 대표 칭호로 고를 수 있어요\.$', ' 얻었습니다. [마이페이지]에서 대표 칭호로 고를 수 있습니다.')
 where kind = 'title_earned';
update public.notifications
   set message = regexp_replace(message, ' 회수됐어요\. \(승인 취소·삭제 등으로 조건이 깨졌어요\)$', ' 회수됐습니다. (승인 취소·삭제 등으로 조건이 깨졌습니다)')
 where kind = 'title_revoked';

-- 3. 확인: 함수에 "~어요/~에요/~예요/~할까요"가 남았으면 이름을 알려 준다 (부탁 "주세요"는 괜찮음)
do $$
declare
  f text;
begin
  for f in
    select p.oid::regprocedure::text from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prosrc ~ '(어요|에요|예요|아요|돼요|해요|까요|게요)'
  loop
    raise notice '함수 본문에 "~해요"체가 남아 있습니다: %', f;
  end loop;
end;
$$;

commit;

-- 확인 (실행 뒤, 모두 0이면 끝):
-- select (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and prosrc ~ '(어요|에요|예요|아요|돼요|해요|까요|게요)') as funcs,
--        (select count(*) from public.notifications
--          where kind in ('post_comment', 'doc_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored',
--                         'doc_comment_hidden', 'doc_comment_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked')
--            and split_part(message, ' 메모: ', 1) ~ '(어요|에요)[.:)]') as notices;
