-- =====================================================================
-- 화면 이름 "내 활동" → "마이페이지" (주소 /me는 그대로)
-- - DB 함수의 오류·알림 문구에 있는 "[내 활동]"을 "[마이페이지]"로 (지금 DB에 있는 함수 본문을 그대로 고쳐 다시 만든다, 017과 같은 방식)
--   대상: check_new_proposal·check_new_build(재검토 요청 받은 제안·빌드가 있을 때), sync_rewards(칭호 알림)
-- - 이미 쌓인 알림 글자도 같이 바꾼다
-- 018_build_max_skill_start_gold.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

do $$
declare
  f record;
  def text;
  fixed text;
  n integer := 0;
begin
  for f in
    select p.oid from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.prosrc like '%내 활동%'
  loop
    def := pg_get_functiondef(f.oid);
    fixed := replace(def, '내 활동', '마이페이지');
    if fixed <> def then
      execute fixed;
      n := n + 1;
    end if;
  end loop;
  if exists (
    select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%내 활동%'
  ) then
    raise exception '문구 정리가 덜 됐어요 (함수에 "내 활동"이 남음).';
  end if;
  raise notice '문구를 고친 함수: %개', n;
end;
$$;

update public.notifications set message = replace(message, '내 활동', '마이페이지') where message like '%내 활동%';

commit;
