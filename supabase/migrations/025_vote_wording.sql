-- =====================================================================
-- 025: 빌드 표 이름 "따봉" → "추천", "비추" → "비추천" 중 DB 부분 (2026-11-04)
-- 1. DB 함수 본문의 문구 (지금 DB에 있는 함수 본문을 그대로 고쳐 다시 만든다, 019와 같은 방식)
--    - block_guest_vote: "비회원은 따봉·비추를 누를 수 없어요" → "비회원은 추천·비추천을 누를 수 없어요"
--    - check_new_build:  "똑같은 빌드가 이미 공개돼 있어요. 따봉으로 응원해 주세요." → "… 추천으로 응원해 주세요."
--    - 그 밖에 함수 안 설명(주석)의 "따봉"·"비추"도 같이 바뀐다
-- 2. 경험치 설명(xp_rules.note): 따봉 받음, 따봉 상한, 장군
-- 3. 이미 쌓인 글자: 알림(notifications.message), 경험치 내역 이유(xp_events.reason)
-- 4. 표 설명(comment on): build_vote_log, build_vote_log.first_up
-- 024_board_rename.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다. 여러 번 실행해도 결과는 같다.
-- (자유게시판 글의 "추천"(post_votes)은 원래 이름 그대로)
-- =====================================================================

begin;

-- 1. 함수 본문: "비추"를 먼저 "비추천"으로 (이미 "비추천"인 곳은 건드리지 않게 잠시 바꿔 둔다), 그다음 "따봉" → "추천"
do $$
declare
  f record;
  def text;
  fixed text;
  n integer := 0;
begin
  for f in
    select p.oid from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
      and (p.prosrc like '%따봉%' or (p.prosrc like '%비추%' and replace(p.prosrc, '비추천', '') like '%비추%'))
  loop
    def := pg_get_functiondef(f.oid);
    fixed := replace(replace(replace(def, '비추천', '§비추천§'), '비추', '비추천'), '§비추천§', '비추천');
    fixed := replace(fixed, '따봉·비추천를', '추천·비추천을');
    fixed := replace(fixed, '따봉', '추천');
    if fixed <> def then
      execute fixed;
      n := n + 1;
    end if;
  end loop;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%따봉%') then
    raise exception '문구 정리가 덜 됐어요 (함수에 "따봉"이 남음).';
  end if;
  raise notice '문구를 고친 함수: %개', n;
end;
$$;

-- 2. 경험치 설명
update public.xp_rules set note = '내 빌드가 추천 받음 (같은 사람이 같은 빌드에 누른 것은 처음 1번만)' where key = 'vote';
update public.xp_rules set note = '추천 경험치 하루 상한 (한국 시간)' where key = 'vote_daily_cap';
update public.xp_rules set note = '장군: 공개 중인 내 빌드들의 추천 합계' where key = 'title_general';
update public.xp_rules set note = replace(note, '따봉', '추천') where note like '%따봉%';

-- 3. 이미 쌓인 글자 ("비추천"은 그대로 두고 "비추"만)
update public.notifications
   set message = replace(replace(replace(replace(message, '비추천', '§'), '비추', '비추천'), '§', '비추천'), '따봉', '추천')
 where message like '%따봉%' or replace(message, '비추천', '') like '%비추%';
update public.xp_events
   set reason = replace(replace(replace(replace(reason, '비추천', '§'), '비추', '비추천'), '§', '비추천'), '따봉', '추천')
 where reason like '%따봉%' or replace(reason, '비추천', '') like '%비추%';

-- 4. 표 설명
comment on table public.build_vote_log is '추천/비추천이 바뀔 때마다 한 줄 (vote_build만 쓴다). 6단계: 추천 받음 +2, 하루 상한, 부풀리기 판단';
comment on column public.build_vote_log.first_up is '이 사람이 이 빌드에 처음 누른 추천 (경험치 대상, 투표할 때 고정)';

commit;

-- 확인 (실행 뒤, 모두 0이면 끝):
-- select (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and prosrc like '%따봉%') as funcs,
--        (select count(*) from public.xp_rules where note like '%따봉%') as rules,
--        (select count(*) from public.notifications where message like '%따봉%') as notices,
--        (select count(*) from public.xp_events where reason like '%따봉%') as xp;
