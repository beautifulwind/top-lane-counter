-- =====================================================================
-- 024: 게시판 이름 "노가리방" → "자유게시판" 중 DB 부분 (주소 /board는 그대로)
-- 1. 경험치 설명(xp_rules.note): 023의 사진 숫자 설명 등 "노가리방"이 들어간 줄
-- 2. 이미 쌓인 글자: 알림(notifications.message), 경험치 내역 이유(xp_events.reason)에 "노가리방"이 있으면 바꾼다
--    (지금 DB 함수가 만드는 알림·경험치 문구에는 게시판 이름이 없다 — 혹시 남아 있으면 3에서 알려 준다)
-- 3. 표 설명(comment on): 023 board_attachments, 018 reports
-- 4. 확인: public 함수 본문에 "노가리방"이 남아 있으면 NOTICE로 이름을 알려 준다 (고치지는 않음)
-- 023_board_media.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다. 여러 번 실행해도 결과는 같다.
-- =====================================================================

begin;

-- 1. 경험치 설명
update public.xp_rules set note = replace(note, '노가리방', '자유게시판') where note like '%노가리방%';

-- 2. 이미 쌓인 글자
update public.notifications set message = replace(message, '노가리방', '자유게시판') where message like '%노가리방%';
update public.xp_events set reason = replace(reason, '노가리방', '자유게시판') where reason like '%노가리방%';

-- 3. 표 설명
comment on table public.board_attachments is '자유게시판 글·댓글에 붙은 사진·GIF (023). 쓰기는 글·댓글 함수로만, 읽기는 글·댓글 읽기 규칙을 따른다';
comment on table public.reports is '자유게시판 글·댓글과 문서 댓글 신고 — 운영자만 본다. 숨기면 resolved, 기각하면 dismissed';

-- 4. 확인
do $$
declare
  f text;
begin
  for f in
    select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosrc like '%노가리방%'
  loop
    raise notice '함수 본문에 "노가리방"이 남아 있어요: %', f;
  end loop;
end;
$$;

commit;

-- 확인 (실행 뒤, 모두 0이면 끝):
-- select (select count(*) from public.xp_rules where note like '%노가리방%') as rules,
--        (select count(*) from public.notifications where message like '%노가리방%') as notices,
--        (select count(*) from public.xp_events where reason like '%노가리방%') as xp;
