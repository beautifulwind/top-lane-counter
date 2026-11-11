-- =====================================================================
-- 041: 용어 정리 "카운터" → "상대법" 중 DB 부분 (2026-11-11)
-- 바꾸는 것: DB 함수 본문의 오류·알림 문구 속 "카운터" (화면에 그대로 보이는 문장)
--   예) '숨긴 카운터만 삭제할 수 있습니다' → '숨긴 상대법만 삭제할 수 있습니다'
--       '운영자가 숨긴 카운터라 지금은 제안할 수 없습니다' → '운영자가 숨긴 상대법이라 지금은 제안할 수 없습니다'
-- 바꾸지 않는 것 (규칙):
--   - 표·칸·함수 이름, 알림 종류(kind), 주소: 영문이라 대상이 아님 (counters, counter_champion, hide_counter, counter_restored …)
--   - 이미 저장된 알림(notifications)과 처리 기록(moderation_log·counter_status_log 등): 한 줄도 건드리지 않음
--   - 경험치 규칙 설명(xp_rules.note)·경험치 내역(xp_events.reason): 저장된 값이라 건드리지 않음
--     (xp_reason() 함수가 새로 만드는 이유 글자는 이 파일로 바뀜)
--   - 약관·방침 시행일: DB에 없음, 화면 문구만 (이 파일은 시행일과 무관)
-- 방식: 026 등과 같다. 지금 DB에 있는 함수 본문을 아래 낱말 표로 고쳐 create or replace 한다.
--   함수 본문에서 "카운터"가 들어간 문장은 조사가 붙은 모양만 있다 (를·가·는·로·라·와·입니다…) → 표가 조사까지 맞춰 바꾼다.
-- 039·040까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다. 여러 번 실행해도 결과는 같다.
-- 실행 전·후에 scripts/check_terms_sangdaebeop.sql 을 한 번씩 실행해 값을 비교한다.
-- =====================================================================

begin;

create temp table term_map (old text primary key, new text not null) on commit drop;
-- 받침 때문에 조사가 달라지는 것만 따로 둔다 (카운터 = 받침 없음, 상대법 = 받침 ㅂ)
insert into term_map (old, new) values
  ('카운터를', '상대법을'),
  ('카운터가', '상대법이'),
  ('카운터는', '상대법은'),
  ('카운터로', '상대법으로'),
  ('카운터라', '상대법이라'),
  ('카운터와', '상대법과'),
  ('카운터입니다', '상대법입니다'),
  ('카운터예요', '상대법이에요'),   -- 026 이전 말투가 남아 있을 때를 위한 안전장치
  ('카운터', '상대법');             -- 나머지 (의·에·만·도·띄어쓰기 등 조사 변화 없음)

do $$
declare
  f record;
  m record;
  def text;
  fixed text;
  n integer := 0;
begin
  for f in
    select p.oid, p.oid::regprocedure::text as sig from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.prosrc like '%카운터%'
    order by 2
  loop
    def := pg_get_functiondef(f.oid);
    fixed := def;
    -- 긴 낱말부터 (짧은 "카운터"가 먼저 바뀌어 조사 맞춤을 놓치지 않게)
    for m in select old, new from term_map order by length(old) desc, old loop
      fixed := replace(fixed, m.old, m.new);
    end loop;
    if fixed <> def then
      execute fixed;
      n := n + 1;
      raise notice '고친 함수: %', f.sig;
    end if;
  end loop;
  raise notice '상대법으로 고친 함수: %개', n;
end;
$$;

-- 확인: 함수 본문에 "카운터"가 남았으면 이름을 알려 주고, 조사가 틀린 모양("상대법를" 등)이 생기면 멈춘다
do $$
declare
  f text;
begin
  for f in
    select p.oid::regprocedure::text from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prosrc like '%카운터%'
  loop
    raise notice '함수 본문에 "카운터"가 남아 있습니다: %', f;
  end loop;
  if exists (
    select 1 from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prosrc ~ '상대법(를|는|가|로|와)([^가-힣]|$)'
  ) then
    raise exception '조사가 맞지 않는 "상대법" 문구가 생겼습니다. 아무것도 바꾸지 않고 멈춥니다.';
  end if;
end;
$$;

commit;
