-- =====================================================================
-- 056: 핵심 템트리 규칙 완화 (2026-11-13, SPEC 6-43)
--
-- 바뀌는 것 (핵심 템트리만)
-- 1. 종류 제한 없음: check_core_items(028)가 아이템 가격표(item_prices)에 있는 아이템이면 종류와 상관없이 받는다
--    (전설, 서사, 신발, 기본템(도란의 방패, 여신의 눈물 등), 소모품, 장신구, 서포터 퀘스트템).
--    "전설 아이템 1개 이상" 규칙도 없앤다. 가격표에 없는 아이템(지금 상점에 없는 아이템)은 지금처럼 막는다.
--    이 함수를 부르는 곳은 그대로: 빌드 트리거 check_build_core, 제안 트리거 check_proposal_core, 위키 빌드 wiki_insert_build(038).
-- 2. 칸 수 3~6개 -> 1~10개, 같은 아이템 중복 허용(횟수 제한 없음, 전체 10칸까지):
--    clean_build(018 정의가 최신, 그 뒤 말투만 고쳐짐) 안의 핵심 템트리 호출만 check_build_ids(core, '핵심 템트리', 1, 10, false)로.
--    clean_build를 부르는 곳(빌드 등록 check_new_build, 제안/다시 제출/고치기 check_new_proposal, edit_build(043), 운영자 고쳐서 승인 등)은
--    모두 이 함수를 거쳐서 함께 바뀐다. 008의 빌드 트리거 안 check_build_ids 호출은 018에서 clean_build로 바뀌어 지금은 없다.
--    set_build_fields / wiki_insert_build(038) / edit_build, revert_build_unchecked(043) / follow_build_card(050)는
--    core_items를 그대로 옮기거나 보여 주기만 해서 바꾸지 않는다.
--
-- 그대로인 것: 시작 아이템(1~4개, 중복 가능, 골드 합계 상한), 소환사 주문, 룬, 선마 규칙. check_build_ids 함수 자체.
-- 표/데이터는 바꾸지 않는다 (이미 저장된 빌드, 제안, 수정 기록 그대로). 새 표/알림/pg_cron 없음. Edge Function 재배포 없음.
-- 실행 전 supabase/scripts/check_core_items_before.sql, 실행 뒤 check_core_items_after.sql.
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다. 055 상태로 돌아간다.
--    데이터는 바꾸지 않는다. 056 뒤에 등록된 빌드(7~10칸, 중복, 기본템 등)는 그대로 남아 보이지만,
--    그 빌드를 고치거나 다시 제출할 때는 예전 규칙(3~6개, 중복 불가, 전설/서사/신발, 전설 1개 이상)에 맞춰야 한다.
--     begin;
--     create or replace function public.check_core_items(arr text[])
--      returns void language plpgsql stable security definer set search_path = ''
--     as $$
--     begin
--       if arr is null then
--         return;
--       end if;
--       if exists (
--         select 1 from unnest(arr) x
--         where not exists (select 1 from public.item_prices p where p.id = x and p.kind is not null)
--       ) then
--         raise exception '종류를 모르는 핵심 템트리 아이템이 있습니다. 지금 상점에 없는 아이템이거나, 운영자가 아이템 가격표를 갱신해야 합니다.'
--           using errcode = '23514';
--       end if;
--       if exists (
--         select 1 from unnest(arr) x join public.item_prices p on p.id = x
--         where p.kind not in ('legendary', 'epic', 'boots')
--       ) then
--         raise exception E'핵심 템트리에는 전설\u00B7서사\u00B7신발 아이템만 넣을 수 있습니다.' using errcode = '23514';
--       end if;
--       if not exists (select 1 from unnest(arr) x join public.item_prices p on p.id = x where p.kind = 'legendary') then
--         raise exception '핵심 템트리에 전설 아이템을 1개 이상 넣어 주세요.' using errcode = '23514';
--       end if;
--     end;
--     $$;
--     create or replace function public.clean_build(b jsonb)
--      returns jsonb language plpgsql immutable set search_path = ''
--     as $$
--     declare
--       runes jsonb;
--       spells text[];
--       starting text[];
--       core text[];
--       skill text;
--       patch text;
--     begin
--       if jsonb_typeof(b) is distinct from 'object' then
--         raise exception E'빌드(룬\u00B7주문\u00B7아이템\u00B7스킬)를 채워 주세요.' using errcode = '23514';
--       end if;
--       runes := public.clean_build_runes(b -> 'runes');
--
--       spells := public.text_array(b -> 'summoner_spells', '소환사 주문');
--       if cardinality(spells) <> 2 or exists (select 1 from unnest(spells) s where s !~ '^Summoner[A-Za-z]{1,30}$') then
--         raise exception '소환사 주문을 2개 골라 주세요.' using errcode = '23514';
--       end if;
--       if spells[1] = spells[2] then
--         raise exception '같은 소환사 주문을 두 번 고를 수 없습니다.' using errcode = '23514';
--       end if;
--
--       starting := public.text_array(b -> 'starting_items', '시작 아이템');
--       core := public.text_array(b -> 'core_items', '핵심 템트리');
--       perform public.check_build_ids(starting, '시작 아이템', 1, 4, false);
--       perform public.check_build_ids(core, '핵심 템트리', 3, 6, true);
--
--       skill := b ->> 'max_skill';
--       if jsonb_typeof(b -> 'max_skill') is distinct from 'string' or skill not in ('Q', 'W', 'E') then
--         raise exception E'선마(첫 번째로 마스터할 스킬)를 Q\u00B7W\u00B7E 중에서 골라 주세요.' using errcode = '23514';
--       end if;
--
--       patch := b ->> 'patch';
--       if jsonb_typeof(b -> 'patch') is distinct from 'string' or patch !~ '^[0-9]{1,3}\.[0-9]{1,3}(\.[0-9]{1,3})?$' then
--         raise exception '패치 버전 형식이 잘못됐습니다.' using errcode = '23514';
--       end if;
--
--       return jsonb_build_object(
--         'runes', runes, 'summoner_spells', to_jsonb(spells), 'starting_items', to_jsonb(starting), 'core_items', to_jsonb(core),
--         'max_skill', skill, 'patch', patch
--       );
--     end;
--     $$;
--     commit;
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 핵심 템트리 종류: 가격표에 있으면 모두 허용 (전설 1개 이상 규칙 없음)
-- ---------------------------------------------------------------------
create or replace function public.check_core_items(arr text[])
returns void language plpgsql stable security definer set search_path = ''
as $$
begin
  if arr is null then
    return;
  end if;
  if exists (
    select 1 from unnest(arr) x
    where not exists (select 1 from public.item_prices p where p.id = x and p.kind is not null)
  ) then
    raise exception '종류를 모르는 핵심 템트리 아이템이 있습니다. 지금 상점에 없는 아이템이거나, 운영자가 아이템 가격표를 갱신해야 합니다.'
      using errcode = '23514';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. 빌드 내용 검사: 핵심 템트리만 1~10개, 중복 허용 (나머지는 018 정의 그대로)
-- ---------------------------------------------------------------------
create or replace function public.clean_build(b jsonb)
returns jsonb language plpgsql immutable set search_path = ''
as $$
declare
  runes jsonb;
  spells text[];
  starting text[];
  core text[];
  skill text;
  patch text;
begin
  if jsonb_typeof(b) is distinct from 'object' then
    raise exception E'빌드(룬\u00B7주문\u00B7아이템\u00B7스킬)를 채워 주세요.' using errcode = '23514';
  end if;
  runes := public.clean_build_runes(b -> 'runes');

  spells := public.text_array(b -> 'summoner_spells', '소환사 주문');
  if cardinality(spells) <> 2 or exists (select 1 from unnest(spells) s where s !~ '^Summoner[A-Za-z]{1,30}$') then
    raise exception '소환사 주문을 2개 골라 주세요.' using errcode = '23514';
  end if;
  if spells[1] = spells[2] then
    raise exception '같은 소환사 주문을 두 번 고를 수 없습니다.' using errcode = '23514';
  end if;

  starting := public.text_array(b -> 'starting_items', '시작 아이템');
  core := public.text_array(b -> 'core_items', '핵심 템트리');
  perform public.check_build_ids(starting, '시작 아이템', 1, 4, false);
  perform public.check_build_ids(core, '핵심 템트리', 1, 10, false);  -- 056: 1~10개, 같은 아이템 여러 번 가능

  skill := b ->> 'max_skill';
  if jsonb_typeof(b -> 'max_skill') is distinct from 'string' or skill not in ('Q', 'W', 'E') then
    raise exception E'선마(첫 번째로 마스터할 스킬)를 Q\u00B7W\u00B7E 중에서 골라 주세요.' using errcode = '23514';
  end if;

  patch := b ->> 'patch';
  if jsonb_typeof(b -> 'patch') is distinct from 'string' or patch !~ '^[0-9]{1,3}\.[0-9]{1,3}(\.[0-9]{1,3})?$' then
    raise exception '패치 버전 형식이 잘못됐습니다.' using errcode = '23514';
  end if;

  return jsonb_build_object(
    'runes', runes, 'summoner_spells', to_jsonb(spells), 'starting_items', to_jsonb(starting), 'core_items', to_jsonb(core),
    'max_skill', skill, 'patch', patch
  );
end;
$$;

commit;
