-- =====================================================================
-- 081: 활동 제한 중에도 「내 챔피언」 해제 허용 - 해제 전용 쓰기 함수 unselect_my_champion (2026-11-25, SPEC 6-121, 1.3 패치)
--      새 함수 1개 + 허용 목록 1줄. 기존 함수(set_my_champion 포함)·표·정책·트리거·데이터는 바꾸지 않는다.
--
-- 왜: set_my_champion(080)은 첫 줄 assert_can_write() 때문에 활동 제한 중이면 등록뿐 아니라 해제도 TL423으로 거부한다.
--   해제는 남에게 보이는 활동이 아니라 내 저장 정보를 지우는 일이고, 팔로우 취소(unfollow_influencer)·빌드 저장 해제(unsave_build)도
--   제한 중에 허용한다(068 허용 목록). 개인정보처리방침도 「등록을 해제하면 바로 지운다」고 적었다.
--   set_my_champion 안에서 조건부로 검사하면 「쓰기 함수는 첫 줄 검사 또는 허용 목록」 규칙(068 빠뜨림 방지)에 어긋나므로,
--   save_build / unsave_build와 같은 방식으로 해제만 하는 함수를 따로 두고 허용 목록에 넣는다.
--
-- 새 쓰기 함수 unselect_my_champion(p_champion text) → { champion, selected: false, count, limit: 10 } (set_my_champion 해제와 같은 모양)
--   - assert_can_write 없음(허용 목록). 로그인만(비회원 가능), 비로그인·anon 불가. 언제나 부른 사람 본인 줄만 지운다(다른 사람 id 인자 없음).
--   - 형식(^[A-Za-z]{1,30}$)만 본다 - 목록에서 빠진 챔피언도 해제할 수 있게. 등록하지 않은 챔피언이면 그대로 성공(아무것도 안 지움).
--   - 같은 사람의 동시 등록과 겹쳐도 수가 맞게 set_my_champion과 같이 그 사람 profiles 줄을 잠근다.
-- 허용 목록(restriction_exemptions): ('function', 'unselect_my_champion(text)', '내 챔피언 해제 (등록은 막음)')
--
-- 함수 수: 쓰기 함수 104 / 첫 줄 검사 31 / 허용 목록 73 → 105 / 31 / 74. 읽기 함수 69 그대로.
-- 옛 화면(웹 이전 배포·앱 1.1·1.2)은 해제에 set_my_champion(…, false)을 그대로 쓴다 - 계속 동작하고 제한 중에는 전처럼 거부된다.
-- 새 웹은 해제에 이 함수를 쓰고, 이 함수가 없으면(081 전 DB) set_my_champion(…, false)으로 되돌아간다.
--
-- 실행 전 supabase/scripts/check_unselect_my_champion_before.sql, 실행 뒤 check_unselect_my_champion_after.sql.
-- 080까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다(두 번째는 맨 앞 확인에서 멈춘다).
--
-- >> 되돌리기 (rollback) - SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 080 상태로 돌아간다.
--    변경 전 상태: 이 함수와 허용 목록 1줄이 없었다. 081은 기존 함수·데이터를 고치지 않았으므로 "변경 전 본문"이 없다. 등록 데이터는 그대로.
--    되돌린 뒤 check_unselect_my_champion_before.sql 1번이 「있음 · 없음 · 없음」이면 정상.
--     begin;
--     drop function public.unselect_my_champion(text);
--     delete from public.restriction_exemptions where kind = 'function' and name = 'unselect_my_champion(text)';
--     commit;
-- =====================================================================
begin;

do $chk$
begin
  if to_regprocedure('public.set_my_champion(text, boolean)') is null or to_regclass('public.user_champions') is null then
    raise exception '080(내 챔피언)을 먼저 실행해야 합니다. 실행을 멈춥니다.';
  end if;
  if to_regprocedure('public.unselect_my_champion(text)') is not null
     or exists (select 1 from public.restriction_exemptions where kind = 'function' and name = 'unselect_my_champion(text)') then
    raise exception 'unselect_my_champion이 이미 있습니다(081을 이미 실행함). 실행을 멈춥니다.';
  end if;
end $chk$;

create function public.unselect_my_champion(p_champion text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  n integer;
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  if coalesce(p_champion, '') !~ '^[A-Za-z]{1,30}$' then
    raise exception '없는 챔피언입니다. 다시 골라 주세요.' using errcode = '22023';
  end if;
  perform 1 from public.profiles where id = me for update;
  delete from public.user_champions where user_id = me and champion = p_champion;
  select count(*) into n from public.user_champions where user_id = me;
  return jsonb_build_object('champion', p_champion, 'selected', false, 'count', n, 'limit', 10);
end;
$$;
comment on function public.unselect_my_champion(text) is
  '내 챔피언 해제 (081): 본인 등록 줄만 지움, 등록하지 않은 챔피언이면 그대로 성공. 로그인(비회원 가능). 활동 제한 중에도 됨(허용 목록) - 등록은 set_my_champion(검사)';

revoke execute on function public.unselect_my_champion(text) from public, anon;
grant execute on function public.unselect_my_champion(text) to authenticated;

insert into public.restriction_exemptions (kind, name, reason)
values ('function', 'unselect_my_champion(text)', '내 챔피언 해제 (등록은 막음)');

commit;
