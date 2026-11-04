-- =====================================================================
-- 028: 핵심 템트리 아이템 종류 + 자주 쓰는 아이템 (2026-11-04, SPEC 5장 빌드 입력)
-- 1. 아이템 가격표(item_prices)에 종류(kind)를 더한다: legendary 전설 · epic 서사(덤불 조끼 같은 중간 재료) · boots 신발
--    · basic 기본템 · consumable 소모품 · trinket 장신구 · support 서포터 퀘스트템.
--    지금 줄은 16.21~16.22 Data Dragon 기준 값으로 채운다. 운영자 [아이템 가격 갱신]이 가격과 함께 종류도 보낸다
--    (set_item_prices에 p_kinds — 화면 src/lib/itemKinds.js와 같은 기준).
-- 2. 핵심 템트리 검사(check_core_items): 가격표에 있는 전설·서사·신발만, 전설은 1개 이상.
--    - 막는 때: 빌드를 새로 등록할 때(승인 대기로 들어올 때), 빌드의 핵심 템트리를 바꿀 때(수정·다시 제출·고쳐서 승인),
--      새 카운터 제안의 빌드를 넣거나 그 핵심 템트리를 바꿀 때, 운영자가 제안의 빌드를 고쳐서 승인할 때.
--    - 이미 공개·등록된 예전 빌드는 그대로 둔다 (그대로 승인·숨겼다가 다시 공개해도 막지 않음) — 022 강타 막기와 같은 방식.
-- 3. 자주 쓰는 아이템(frequent_items): 빌드 입력의 아이템 고르기 목록에 먼저 보이는 아이템 (나머지는 [더보기]).
--    칸은 core(핵심 템트리) / starting(시작 아이템). 읽기는 누구나, 추가·빼기는 운영자 함수로만.
--    넣을 수 있는 것: core = 전설·서사·신발, starting = 가격표에 있고 시작템 골드 상한(xp_rules.starting_gold_max) 이하.
--    처음 목록: 핵심 19개(전설 11 · 서사 6 · 신발 2), 시작 9개.
-- 027_notifications_page.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 가격표에 종류
-- ---------------------------------------------------------------------
alter table public.item_prices add column kind text
  check (kind in ('legendary', 'epic', 'boots', 'basic', 'consumable', 'trinket', 'support'));
comment on column public.item_prices.kind is
  '아이템 종류 (028): legendary 전설 · epic 서사 · boots 신발 · basic 기본템 · consumable 소모품 · trinket 장신구 · support 서포터템. 핵심 템트리는 legendary·epic·boots만';

update public.item_prices p set kind = v.kind
from (values
  ('1001', 'boots'), ('1004', 'basic'), ('1006', 'basic'), ('1011', 'epic'), ('1018', 'basic'), ('1026', 'basic'), ('1027', 'basic'), ('1028', 'basic'),
  ('1029', 'basic'), ('1031', 'epic'), ('1033', 'basic'), ('1036', 'basic'), ('1037', 'basic'), ('1038', 'basic'), ('1042', 'basic'), ('1043', 'epic'),
  ('1052', 'basic'), ('1053', 'epic'), ('1054', 'basic'), ('1055', 'basic'), ('1056', 'basic'), ('1057', 'epic'), ('1058', 'basic'), ('1082', 'basic'),
  ('1083', 'basic'), ('1086', 'basic'), ('1101', 'basic'), ('1102', 'basic'), ('1103', 'basic'), ('1120', 'basic'), ('2003', 'consumable'), ('2019', 'epic'),
  ('2020', 'epic'), ('2021', 'epic'), ('2022', 'basic'), ('2031', 'consumable'), ('2051', 'basic'), ('2055', 'consumable'), ('2065', 'legendary'), ('2138', 'consumable'),
  ('2139', 'consumable'), ('2140', 'consumable'), ('2141', 'consumable'), ('2420', 'epic'), ('2501', 'legendary'), ('2502', 'legendary'), ('2503', 'legendary'), ('2504', 'legendary'),
  ('2508', 'epic'), ('2510', 'legendary'), ('2512', 'legendary'), ('2517', 'legendary'), ('2520', 'legendary'), ('2522', 'legendary'), ('2523', 'legendary'), ('2524', 'legendary'),
  ('2525', 'legendary'), ('2526', 'legendary'), ('3003', 'legendary'), ('3004', 'legendary'), ('3006', 'boots'), ('3008', 'boots'), ('3009', 'boots'), ('3020', 'boots'),
  ('3024', 'epic'), ('3026', 'legendary'), ('3031', 'legendary'), ('3032', 'legendary'), ('3033', 'legendary'), ('3035', 'epic'), ('3036', 'legendary'), ('3041', 'legendary'),
  ('3044', 'epic'), ('3046', 'legendary'), ('3047', 'boots'), ('3050', 'legendary'), ('3051', 'epic'), ('3053', 'legendary'), ('3057', 'epic'), ('3065', 'legendary'),
  ('3066', 'epic'), ('3067', 'epic'), ('3068', 'legendary'), ('3070', 'basic'), ('3071', 'legendary'), ('3072', 'legendary'), ('3073', 'legendary'), ('3074', 'legendary'),
  ('3075', 'legendary'), ('3076', 'epic'), ('3077', 'epic'), ('3078', 'legendary'), ('3082', 'epic'), ('3083', 'legendary'), ('3084', 'legendary'), ('3085', 'legendary'),
  ('3086', 'epic'), ('3087', 'legendary'), ('3089', 'legendary'), ('3091', 'legendary'), ('3094', 'legendary'), ('3095', 'legendary'), ('3100', 'legendary'), ('3102', 'legendary'),
  ('3107', 'legendary'), ('3108', 'epic'), ('3109', 'legendary'), ('3110', 'legendary'), ('3111', 'boots'), ('3112', 'basic'), ('3113', 'epic'), ('3114', 'epic'),
  ('3115', 'legendary'), ('3116', 'legendary'), ('3118', 'legendary'), ('3119', 'legendary'), ('3123', 'epic'), ('3124', 'legendary'), ('3133', 'epic'), ('3134', 'epic'),
  ('3135', 'legendary'), ('3137', 'legendary'), ('3139', 'legendary'), ('3140', 'epic'), ('3142', 'legendary'), ('3143', 'legendary'), ('3144', 'epic'), ('3145', 'epic'),
  ('3146', 'legendary'), ('3147', 'epic'), ('3152', 'legendary'), ('3153', 'legendary'), ('3155', 'epic'), ('3156', 'legendary'), ('3157', 'legendary'), ('3158', 'boots'),
  ('3161', 'legendary'), ('3165', 'legendary'), ('3168', 'boots'), ('3170', 'boots'), ('3171', 'boots'), ('3172', 'boots'), ('3173', 'boots'), ('3174', 'boots'),
  ('3175', 'boots'), ('3177', 'basic'), ('3179', 'legendary'), ('3181', 'legendary'), ('3184', 'basic'), ('3190', 'legendary'), ('3211', 'epic'), ('3222', 'legendary'),
  ('3302', 'legendary'), ('3340', 'trinket'), ('3363', 'trinket'), ('3364', 'trinket'), ('3504', 'legendary'), ('3508', 'legendary'), ('3742', 'legendary'), ('3748', 'legendary'),
  ('3801', 'epic'), ('3802', 'epic'), ('3803', 'epic'), ('3814', 'legendary'), ('3865', 'support'), ('3869', 'support'), ('3870', 'support'), ('3871', 'support'),
  ('3876', 'support'), ('3877', 'support'), ('3916', 'epic'), ('4005', 'legendary'), ('4401', 'legendary'), ('4628', 'legendary'), ('4629', 'legendary'), ('4630', 'epic'),
  ('4632', 'epic'), ('4633', 'legendary'), ('4642', 'epic'), ('4645', 'legendary'), ('4646', 'support'), ('6333', 'legendary'), ('6609', 'legendary'), ('6610', 'legendary'),
  ('6616', 'legendary'), ('6617', 'legendary'), ('6620', 'legendary'), ('6621', 'legendary'), ('6631', 'legendary'), ('6653', 'legendary'), ('6655', 'legendary'), ('6657', 'legendary'),
  ('6660', 'epic'), ('6662', 'legendary'), ('6664', 'legendary'), ('6665', 'legendary'), ('6670', 'epic'), ('6672', 'legendary'), ('6673', 'legendary'), ('6675', 'legendary'),
  ('6676', 'legendary'), ('6690', 'epic'), ('6692', 'legendary'), ('6694', 'legendary'), ('6695', 'legendary'), ('6696', 'legendary'), ('6697', 'legendary'), ('6698', 'legendary'),
  ('6699', 'legendary'), ('8010', 'legendary'), ('8020', 'legendary')
) as v (id, kind)
where p.id = v.id;
-- 위 표에 없는 줄(운영자가 다른 패치로 갱신해 둔 경우)은 종류를 모른다 → [아이템 가격 갱신]을 한 번 누르면 채워진다

-- 운영자: 가격표를 통째로 바꾼다. p_prices = {"1055": 450, ...}, p_kinds = {"1055": "basic", ...} (같은 아이템들)
drop function public.set_item_prices(text, jsonb);
create function public.set_item_prices(p_patch text, p_prices jsonb, p_kinds jsonb)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  n integer;
begin
  perform public.require_operator();
  if p_patch is null or p_patch !~ '^[0-9]{1,3}\.[0-9]{1,3}(\.[0-9]{1,3})?$' then
    raise exception '패치 버전 형식이 잘못됐습니다.' using errcode = '23514';
  end if;
  if jsonb_typeof(p_prices) is distinct from 'object' or jsonb_typeof(p_kinds) is distinct from 'object' then
    raise exception '가격표 형식이 잘못됐습니다.' using errcode = '23514';
  end if;
  if exists (
    select 1 from jsonb_each(p_prices) e
    where e.key !~ '^[0-9]{1,6}$' or jsonb_typeof(e.value) <> 'number' or (e.value)::numeric < 0
       or (e.value)::numeric <> trunc((e.value)::numeric) or (e.value)::numeric > 100000
  ) then
    raise exception '가격표 형식이 잘못됐습니다.' using errcode = '23514';
  end if;
  -- 종류: 가격표의 아이템마다 하나씩, 정해진 값만
  if exists (
    select 1 from jsonb_object_keys(p_prices) k
    where jsonb_typeof(p_kinds -> k) is distinct from 'string'
       or (p_kinds ->> k) not in ('legendary', 'epic', 'boots', 'basic', 'consumable', 'trinket', 'support')
  ) or exists (select 1 from jsonb_object_keys(p_kinds) k where not (p_prices ? k)) then
    raise exception '아이템 종류 형식이 잘못됐습니다. 게임 데이터를 다시 불러와 주세요.' using errcode = '23514';
  end if;
  select count(*) into n from jsonb_object_keys(p_prices);
  if n < 50 then
    raise exception '아이템이 너무 적습니다 (%개). 게임 데이터를 다시 불러와 주세요.', n using errcode = '23514';
  end if;
  delete from public.item_prices where true;
  insert into public.item_prices (id, gold, kind, patch)
  select e.key, (e.value)::numeric::integer, p_kinds ->> e.key, p_patch from jsonb_each(p_prices) e;
  return n;
end;
$$;
revoke execute on function public.set_item_prices(text, jsonb, jsonb) from public, anon;
grant execute on function public.set_item_prices(text, jsonb, jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- 2. 핵심 템트리 검사
-- ---------------------------------------------------------------------
create function public.check_core_items(arr text[])
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
  if exists (
    select 1 from unnest(arr) x join public.item_prices p on p.id = x
    where p.kind not in ('legendary', 'epic', 'boots')
  ) then
    raise exception '핵심 템트리에는 전설·서사·신발 아이템만 넣을 수 있습니다.' using errcode = '23514';
  end if;
  if not exists (select 1 from unnest(arr) x join public.item_prices p on p.id = x where p.kind = 'legendary') then
    raise exception '핵심 템트리에 전설 아이템을 1개 이상 넣어 주세요.' using errcode = '23514';
  end if;
end;
$$;
-- 실행 권한은 그대로 둔다: 부른 사람 권한으로 도는 검사와 같은 이유 (check_start_gold와 같음)

-- 빌드: 유저가 새로 등록할 때(승인된 제안에서 바로 공개되는 빌드는 제안 단계에서 검사됨), 핵심 템트리가 바뀔 때
create function public.check_build_core()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if (tg_op = 'INSERT' and new.status <> 'approved')
     or (tg_op = 'UPDATE' and new.core_items is distinct from old.core_items) then
    perform public.check_core_items(new.core_items);
  end if;
  return new;
end;
$$;
create trigger builds_core_items before insert or update of core_items on public.builds
  for each row execute function public.check_build_core();

-- 새 카운터 제안: 빌드를 넣거나 그 핵심 템트리를 바꿀 때, 운영자가 빌드를 고쳐서 승인할 때(approved_build)
create function public.check_proposal_core()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if jsonb_typeof(new.build) = 'object'
     and (tg_op = 'INSERT' or (new.build -> 'core_items') is distinct from (old.build -> 'core_items')) then
    perform public.check_core_items(public.text_array(new.build -> 'core_items', '핵심 템트리'));
  end if;
  if tg_op = 'UPDATE' and jsonb_typeof(new.approved_build) = 'object'
     and (new.approved_build -> 'core_items') is distinct from (old.approved_build -> 'core_items')
     and (new.approved_build -> 'core_items') is distinct from (new.build -> 'core_items') then
    perform public.check_core_items(public.text_array(new.approved_build -> 'core_items', '핵심 템트리'));
  end if;
  return new;
end;
$$;
create trigger edit_proposals_core_items before insert or update of build, approved_build on public.edit_proposals
  for each row execute function public.check_proposal_core();

revoke execute on function public.check_build_core() from public, anon, authenticated;
revoke execute on function public.check_proposal_core() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. 자주 쓰는 아이템
-- ---------------------------------------------------------------------
create table public.frequent_items (
  slot       text not null check (slot in ('core', 'starting')),
  item_id    text not null check (item_id ~ '^[0-9]{1,6}$'),
  created_at timestamptz not null default now(),
  primary key (slot, item_id)
);
comment on table public.frequent_items is
  '빌드 입력 아이템 고르기에 먼저 보이는 아이템 (028). slot: core 핵심 템트리 / starting 시작 아이템. 운영자가 /admin에서 추가·빼기';

revoke all on public.frequent_items from anon, authenticated;
grant select on public.frequent_items to anon, authenticated;
alter table public.frequent_items enable row level security;
create policy "frequent_items: 누구나 읽기" on public.frequent_items for select using (true);

create function public.add_frequent_item(p_slot text, p_item text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  it public.item_prices;
  lim integer := public.xp_rule('starting_gold_max');
begin
  perform public.require_operator();
  if p_slot is null or p_slot not in ('core', 'starting') then
    raise exception '칸은 핵심 템트리(core)나 시작 아이템(starting)이어야 합니다.' using errcode = '23514';
  end if;
  select * into it from public.item_prices where id = p_item;
  if not found then
    raise exception '아이템 가격표에 없는 아이템입니다. 지금 상점에서 살 수 있는 아이템인지 확인해 주세요.' using errcode = '23514';
  end if;
  if p_slot = 'core' and it.kind is distinct from 'legendary' and it.kind is distinct from 'epic' and it.kind is distinct from 'boots' then
    raise exception '핵심 템트리에는 전설·서사·신발 아이템만 넣을 수 있습니다.' using errcode = '23514';
  end if;
  if p_slot = 'starting' and lim is not null and it.gold > lim then
    raise exception '시작 아이템은 %골드 이하만 넣을 수 있습니다.', lim using errcode = '23514';
  end if;
  if exists (select 1 from public.frequent_items where slot = p_slot and item_id = p_item) then
    raise exception '이미 자주 쓰는 아이템에 들어 있습니다.' using errcode = '23514';
  end if;
  insert into public.frequent_items (slot, item_id) values (p_slot, p_item);
end;
$$;

create function public.remove_frequent_item(p_slot text, p_item text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  delete from public.frequent_items where slot = p_slot and item_id = p_item;
  if not found then
    raise exception '자주 쓰는 아이템에 없는 아이템입니다.' using errcode = '23514';
  end if;
end;
$$;
revoke execute on function public.add_frequent_item(text, text) from public, anon;
revoke execute on function public.remove_frequent_item(text, text) from public, anon;
grant execute on function public.add_frequent_item(text, text) to authenticated;
grant execute on function public.remove_frequent_item(text, text) to authenticated;

-- 처음 목록 (보이는 순서는 화면이 정한다: 핵심은 비싼 순, 시작은 싼 순)
insert into public.frequent_items (slot, item_id, created_at)
select 'core', v.id, now() + (v.n || ' milliseconds')::interval from (values
  -- 전설: 칠흑의 양날 도끼, 스테락의 도전, 선체파괴자, 발걸음 분쇄기, 삼위일체, 거대한 히드라, 죽음의 무도, 가시 갑옷, 태양불꽃 방패, 정령의 형상, 얼어붙은 심장
  ('3071', 1), ('3053', 2), ('3181', 3), ('6631', 4), ('3078', 5), ('3748', 6), ('6333', 7), ('3075', 8), ('3068', 9), ('3065', 10), ('3110', 11),
  -- 서사: 덤불 조끼, 티아맷, 탐식의 망치, 점화석, 망령의 두건, 쇠사슬 조끼
  ('3076', 12), ('3077', 13), ('3044', 14), ('3067', 15), ('3211', 16), ('1031', 17),
  -- 신발: 판금 장화, 헤르메스의 발걸음
  ('3047', 18), ('3111', 19)
) as v (id, n)
union all
select 'starting', v.id, now() + (v.n || ' milliseconds')::interval from (values
  -- 도란의 검, 도란의 방패, 도란의 반지, 도란의 투구, 체력 물약, 충전형 물약, 여신의 눈물, 롱소드, 장화
  ('1055', 1), ('1054', 2), ('1056', 3), ('1120', 4), ('2003', 5), ('2031', 6), ('3070', 7), ('1036', 8), ('1001', 9)
) as v (id, n);

commit;
