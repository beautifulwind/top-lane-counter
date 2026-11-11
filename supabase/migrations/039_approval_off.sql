-- =====================================================================
-- 039: 승인 제도 끄기 (상대법 = 빌드 묶음 2단계, SPEC 6-25)
--   - xp_rules.approval_on = 0 → 옛 길(새 카운터 제안·문서 수정 제안·승인 대기 빌드 등록)을 DB가 거부한다
--     (038 check_new_proposal·check_new_build: 「이제 승인 없이 바로 등록합니다. 화면을 새로고침해 주세요.」)
--     새 상대법·새 빌드·빌드 수정은 038의 create_matchup·create_build·edit_build로 바로 공개된다 (스위치와 상관없음).
--   - 038 ~ 039 사이에 옛 화면으로 승인된 빌드·문서 수정을 빌드 칸으로 한 번 더 옮긴다 (wiki_backfill_matchups, 다시 실행해도 같음)
--   - 제안 "검토 중" 표시(proposal_reviewing)를 비운다 (승인할 것이 없으므로)
--   - 표·함수·예전 기록(제안·처리 메모·문서 수정 기록)은 지우지 않는다. 다시 켜려면 approval_on을 1로, 화면 src/lib/features.js도 true로.
--
-- 실행 조건: 승인 대기·재검토 중인 제안과 빌드가 0건이어야 한다 (운영자 페이지에서 먼저 처리).
--   남아 있으면 아무것도 바꾸지 않고 몇 건 남았는지 알려 주며 멈춘다.
-- 순서: 운영자 페이지에서 대기 0건 → supabase/scripts/check_approval_off.sql로 "실행 전" 확인 → 이 파일 → 같은 확인 조회로 "실행 후" 확인
--       → 그다음 2b 화면 push (2b 화면은 승인 대기 목록을 보여 주지 않으므로 039보다 먼저 push하지 않는다).
-- 038까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다. 따로 실행할 SQL(pg_cron 등)은 없다.
-- =====================================================================

begin;

-- 확인하는 동안 새 제안·빌드가 끼어들지 않게 잠근다 (읽기·투표는 그대로, 잠깐이면 끝난다)
lock table public.edit_proposals, public.builds in share row exclusive mode;

do $$
declare
  np integer;
  nb integer;
begin
  if to_regprocedure('public.approval_on()') is null then
    raise exception '038이 아직 실행되지 않았습니다. 038_wiki_builds.sql을 먼저 실행해 주세요.';
  end if;
  select count(*) into np from public.edit_proposals where status in ('pending', 'revision_requested');
  select count(*) into nb from public.builds where status in ('pending', 'revision_requested');
  if np + nb > 0 then
    raise exception '승인 대기·재검토 중인 제안 %건, 빌드 %건이 남아 있습니다. 운영자 페이지에서 먼저 처리한 뒤 다시 실행해 주세요. (아무것도 바뀌지 않았습니다)', np, nb;
  end if;
end $$;

-- 1. 승인 제도 끄기
update public.xp_rules
   set value = 0,
       note = '승인 제도 켜짐(1)/꺼짐(0) — 꺼지면 옛 제안·빌드 승인 대기 등록을 DB가 거부 (038, 039에서 0으로 끔. 다시 켜면 화면 src/lib/features.js도 함께)'
 where key = 'approval_on';

-- 2. 038 뒤 옛 화면으로 승인된 것까지 빌드 칸으로 (이미 옮긴 것은 그대로)
select public.wiki_backfill_matchups();

-- 3. "검토 중" 표시 비우기
delete from public.proposal_reviewing;

commit;
