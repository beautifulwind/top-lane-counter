-- =====================================================================
-- 071: 빌드 난이도 별점 칸 + 쓰기 함수 set_build_difficulty + 읽기 함수 build_difficulties (2026-11-24, SPEC 6-100, 1.3 패치 2-A) - "더하기만" 한다.
--
-- 1. builds에 칸 difficulty numeric(2,1) 하나 (null 허용, 기본값 없음 → 기존 빌드는 모두 null = 「별점 없음」).
--    제약 builds_difficulty_check: null이거나 0.5~5.0 사이의 0.5 단위(0.5, 1.0, 1.5, … 5.0)만.
--    기본값이 없는 칸 추가라 표를 다시 쓰지 않고(기존 행 그대로), 트리거도 돌지 않는다.
-- 2. set_build_difficulty(p_build bigint, p_difficulty numeric) → jsonb { build_id, difficulty } (로그인 사용자만, anon·public 없음)
--    - 그 빌드의 작성자(builds.author_id) 본인만. 빌드 상태와 관계없이(공개·대기·재검토·거절·숨김) 본인은 된다.
--      다른 사람은 빌드가 공개든 숨김이든 같은 문장으로 거절한다(숨긴 빌드가 있다는 것이 드러나지 않게 - 없는 빌드도 같은 문장).
--    - p_difficulty = null이면 비우기. 그 밖에는 0.5~5.0의 0.5 단위만(아니면 오류 - 반올림해서 받지 않는다).
--    - 068 규칙 그대로: 선언부 첫 줄 assert_can_write()(활동 제한 중이면 사유·풀리는 시각 문장, 다른 검사보다 먼저) →
--      board_writer()(로그인 + 닉네임). security definer + search_path ''.
--    - 바꾸는 것은 difficulty 칸 하나뿐: updated_at·updated_by·version·edited_at은 그대로(「최근 수정」 순서·수정 충돌 검사에 영향 없음),
--      수정 기록(build_revisions)을 남기지 않는다.
-- 2-1. build_difficulties(p_ids bigint[]) → jsonb { "<빌드 id>": 별점, … } (비로그인·로그인 모두, public 회수, stable, search_path '')
--    - 장인 프로필·/following·/lists처럼 빌드를 jsonb 함수(follow_build_card·my_saved_builds - 키가 고정)로 받는 화면이
--      받은 빌드 id들로 한 번 더 불러 별점을 붙인다(build_links·build_editor_counts처럼 { 빌드 id: 값 } 모양). 기존 함수는 고치지 않는다.
--    - 별점이 비어 있는(null) 빌드·볼 수 없는 빌드는 키를 넣지 않는다. 빈 배열·null이면 {}. 목록 안의 null id는 무시한다.
--    - 한 번에 id 200개까지(null을 뺀 개수). 넘으면 오류 「별점은 한 번에 200개까지 불러올 수 있습니다.」
--    - 보안: security invoker(부른 사람 권한). builds 읽기 규칙(RLS)이 그대로 적용된다 → 공개 빌드(빌드·상대법 모두 approved -
--      화면의 publicBuilds와 같은 조건)·내 빌드(상태 무관)·운영자(is_admin, 운영자 모드 켬)는 전부, 감독관은 RLS대로 처리할 수 있는
--      작성자의 숨긴 빌드까지. difficulty 칸은 표 단위 읽기 권한이라 표를 직접 읽어도 같은 범위가 보이므로, 이 함수가 그보다 넓게
--      보여 줄 길이 없다(security definer로 조건을 따로 적으면 RLS와 어긋날 위험만 생긴다).
-- 3. 알림이 생기지 않는 이유 (조사 결과): 빌드 수정 알림 build_edited는 067의 트리거 build_revisions_notify가
--    "build_revisions에 'edit'·'revert' 줄이 생길 때"만 만든다. 이 함수는 build_revisions에 줄을 넣지 않는다.
--    builds의 UPDATE 트리거 중 칸 지정 없이 도는 것은 builds_bump_version(재검토→대기 다시 보내기 때만 버전 +1)과
--    builds_start_gold(시작 아이템이 바뀌거나 승인될 때만 검사) 둘뿐이고, 나머지는 status·up_count·core_items 등 다른 칸에만 걸린다
--    (팔로우 알림 builds_follow_notify·운영진 알림·경험치도 status 등에만 걸림). 068 표 트리거 a_restriction_edit도 difficulty를 보지 않는다
--    (제한 검사는 함수 첫 줄이 한다). → 별점만 바꾸면 알림·푸시가 생기지 않는다(tests/build_difficulty_test.sql이 확인).
-- 4. 그대로인 것: 기존 함수(이름·인자·반환·본문) 전부, 기존 트리거·정책·칸 권한. 읽기 함수는 빌드를 jsonb_build_object로 칸을 골라
--    내보내므로(build_json·follow_build_card·my_saved_builds 등) 새 칸이 저절로 끼지 않는다 → 옛 앱 1.1·1.2 응답 모양 그대로.
--    표를 직접 읽는 화면은 칸을 골라 읽으므로(select 칸 목록) 역시 그대로. builds의 select 권한은 표 단위라
--    읽을 수 있는 빌드(공개·내 것·운영자)의 difficulty는 바로 읽힌다. 넣기 칸 권한(8칸)에는 들어가지 않는다 → 함수로만 바뀐다.
-- 5. 068 빠뜨림 방지 검사: 새 쓰기 함수라 첫 줄에 assert_can_write()가 있다 → 「검사가 든 함수」가 29개 → 30개
--    (일반 사용자가 부를 수 있는 쓰기 함수 100개 → 101개, 허용 목록 71개는 그대로). 허용 목록 표는 건드리지 않는다.
--    build_difficulties는 읽기 함수(stable)라 이 검사의 대상이 아니다(쓰기 함수 수는 101 그대로).
--
-- 실행 전 supabase/scripts/check_build_difficulty_before.sql, 실행 뒤 check_build_difficulty_after.sql
-- (함수 본문 지문은 줄바꿈 CR을 뺀 값으로 비교 - c5333b1과 같은 방식). 070까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- 화면(별점 입력·표시)은 이번에 없다 - 읽기 경로에 별점을 싣는 일은 다음 단계에서 따로 한다.
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 070 상태로 돌아간다.
--    !! 칸을 지우면 그때까지 입력된 별점이 모두 사라진다(되살릴 수 없음). 별점을 남기고 함수만 막으려면 아래 1)만 실행한다.
--     begin;
--     -- 1) 함수만 지움 (별점 데이터는 남는다. 화면이 함수를 부르면 「함수를 찾을 수 없음」 오류)
--     drop function if exists public.set_build_difficulty(bigint, numeric);
--     drop function if exists public.build_difficulties(bigint[]);
--     -- 2) 칸까지 지움 - 별점 데이터 삭제 (제약은 칸과 함께 지워진다)
--     alter table public.builds drop constraint if exists builds_difficulty_check;
--     alter table public.builds drop column if exists difficulty;
--     commit;
-- =====================================================================
begin;

-- 다시 실행 방지: 이미 칸이나 함수가 있으면 아무것도 바꾸지 않고 멈춘다
do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'builds' and column_name = 'difficulty')
     or to_regprocedure('public.set_build_difficulty(bigint, numeric)') is not null
     or to_regprocedure('public.build_difficulties(bigint[])') is not null then
    raise exception '071을 이미 실행했습니다 (builds.difficulty 칸 또는 set_build_difficulty·build_difficulties 함수가 있음). 다시 실행하지 마세요. 아무것도 바뀌지 않았습니다.' using errcode = 'P0001';
  end if;
  if to_regprocedure('public.assert_can_write()') is null or to_regprocedure('public.influencer_directory(text, text, integer, integer)') is null then
    raise exception '068~070을 먼저 실행해 주세요 (assert_can_write 또는 influencer_directory 함수가 없음). 아무것도 바뀌지 않았습니다.' using errcode = 'P0001';
  end if;
end $$;

-- 1. 칸 + 제약 (기본값 없음 → 기존 행은 null 그대로, 표를 다시 쓰지 않음)
alter table public.builds add column difficulty numeric(2,1);
alter table public.builds add constraint builds_difficulty_check
  check (difficulty is null or (difficulty between 0.5 and 5.0 and difficulty * 2 = trunc(difficulty * 2)));
comment on column public.builds.difficulty is '빌드 난이도 별점 (071). 0.5~5.0, 0.5 단위. null = 별점 없음. 작성자 본인만 set_build_difficulty로 바꾼다';

-- 2. 쓰기 함수
create function public.set_build_difficulty(p_build bigint, p_difficulty numeric)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  _can_write constant boolean := public.assert_can_write();  -- 068 활동 제한: 다른 검사보다 먼저 (제한 중이면 사유·풀리는 시각 문장)
  me uuid := public.board_writer();  -- 로그인 + 닉네임
  b_author uuid;
  cur numeric;
begin
  -- 허용 값: null(비우기) 또는 0.5~5.0의 0.5 단위. 반올림해서 받지 않는다(0.3·5.5·0.25 등은 오류)
  if p_difficulty is not null
     and (p_difficulty < 0.5 or p_difficulty > 5.0 or p_difficulty * 2 <> trunc(p_difficulty * 2)) then
    raise exception '난이도는 0.5부터 5.0까지 0.5 단위로 골라 주세요.' using errcode = '22023';
  end if;
  select b.author_id, b.difficulty into b_author, cur from public.builds b where b.id = p_build for update;
  -- 없는 빌드·남의 빌드(공개·숨김 모두)는 같은 문장 - 숨긴 빌드가 있다는 것이 드러나지 않게
  if not found or b_author is distinct from me then
    raise exception '내가 만든 빌드에만 난이도를 정할 수 있습니다.' using errcode = '42501';
  end if;
  -- difficulty 칸 하나만 바꾼다 (수정 시각·버전·수정 기록 그대로 → 빌드 수정 알림 없음)
  if cur is distinct from p_difficulty then
    update public.builds set difficulty = p_difficulty where id = p_build;
  end if;
  return jsonb_build_object('build_id', p_build, 'difficulty', p_difficulty::numeric(2,1));
end;
$$;
comment on function public.set_build_difficulty(bigint, numeric) is
  '빌드 난이도 별점 정하기·비우기 (071). 작성자 본인만, 0.5~5.0의 0.5 단위 또는 null. 수정 기록·알림 없음';

revoke execute on function public.set_build_difficulty(bigint, numeric) from public, anon;
grant execute on function public.set_build_difficulty(bigint, numeric) to authenticated;

-- 3. 읽기 함수 - security invoker: builds 읽기 규칙(RLS)이 그대로 걸려 표를 직접 읽을 때보다 넓게 보일 수 없다
create function public.build_difficulties(p_ids bigint[])
returns jsonb language plpgsql stable security invoker set search_path = ''
as $$
declare
  ids bigint[] := array_remove(coalesce(p_ids, '{}'::bigint[]), null);  -- null id는 무시
begin
  if cardinality(ids) > 200 then
    raise exception '별점은 한 번에 200개까지 불러올 수 있습니다.' using errcode = '22023';
  end if;
  if cardinality(ids) = 0 then
    return '{}'::jsonb;
  end if;
  return (
    select coalesce(jsonb_object_agg(b.id::text, b.difficulty), '{}'::jsonb)
      from public.builds b
     where b.id = any (ids) and b.difficulty is not null  -- 볼 수 없는 빌드는 RLS가 뺀다, 비어 있는 별점은 키 없음
  );
end;
$$;
comment on function public.build_difficulties(bigint[]) is
  '빌드 난이도 별점 묶음 읽기 (071): { 빌드 id: 별점 }. 별점 없음·볼 수 없는 빌드는 키 없음. 200개까지. security invoker - builds RLS 그대로';

revoke execute on function public.build_difficulties(bigint[]) from public;
grant execute on function public.build_difficulties(bigint[]) to anon, authenticated;

commit;
