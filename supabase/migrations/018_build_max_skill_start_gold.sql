-- =====================================================================
-- 묶음 C: 빌드 입력 바꾸기 + "게시판" → "노가리방" 설명 문구
-- 1. 시작 아이템 합계 상한: xp_rules.starting_gold_max (처음 500골드). 숫자만 바꾸면 화면·DB 둘 다 바로 적용.
--    - DB는 아이템 가격을 item_prices 표에서 본다 (Data Dragon 상점 아이템 전체, 패치 하나 기준).
--      운영자 화면 [아이템 가격 갱신]이 지금 패치 가격으로 통째로 바꾼다 (set_item_prices). 처음 값은 16.21.1.
--    - 가격표에 없는 아이템을 시작 아이템으로 고르면 막는다.
--    - 검사하는 때: 빌드를 새로 넣을 때(등록·새 카운터 승인으로 공개), 빌드 시작템을 바꿀 때(고치기·다시 제출·고쳐서 승인),
--      승인 대기 빌드를 승인할 때, 새 카운터 제안의 빌드를 넣거나 바꿀 때.
--      이미 공개된 빌드는 그대로 둔다 (숨겼다가 다시 공개해도 검사하지 않음).
-- 2. 스킬: "선마(첫 번째로 마스터할 스킬)" 하나만 (builds.max_skill = Q/W/E).
--    - 기존 빌드는 선마 순서의 첫 칸을 선마로 옮긴다 (Q›E›W → Q). 1·2·3레벨 스킬은 버린다.
--    - 원래 값은 builds_skill_backup_018 표에 남긴다 (아무도 못 읽음, 확인 뒤 drop table로 지워도 됨).
--    - 빌드를 담은 jsonb(새 카운터 제안의 build, 고쳐서 승인한 빌드의 original_build)도 같은 규칙으로 바꾼다.
-- 017_account.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 0. 숫자·설명 문구
-- ---------------------------------------------------------------------
insert into public.xp_rules (key, value, note) values
  ('starting_gold_max', 500, '빌드 시작 아이템 합계 최대 골드 (화면 고르기 목록과 DB 검사가 같이 씀)');
update public.xp_rules set note = replace(replace(note, '자유게시판', '노가리방'), '게시판', '노가리방') where note like '%게시판%';
comment on table public.reports is '노가리방 글·댓글과 문서 댓글 신고 — 운영자만 본다. 숨기면 resolved, 기각하면 dismissed';

-- ---------------------------------------------------------------------
-- 1. 아이템 가격표
-- ---------------------------------------------------------------------
create table public.item_prices (
  id         text primary key check (id ~ '^[0-9]{1,6}$'),
  gold       integer not null check (gold >= 0),
  patch      text not null,
  updated_at timestamptz not null default now()
);
comment on table public.item_prices is '소환사의 협곡 상점 아이템 가격 (Data Dragon gold.total). 운영자 [아이템 가격 갱신]으로 패치마다 통째로 바꾼다';

revoke all on public.item_prices from anon, authenticated;
grant select on public.item_prices to anon, authenticated;
alter table public.item_prices enable row level security;
create policy "item_prices: 누구나 읽기" on public.item_prices for select using (true);

insert into public.item_prices (id, gold, patch)
select v.id, v.gold, '16.21.1' from (values
  ('1001', 300), ('1004', 200), ('1006', 300), ('1011', 900), ('1018', 600), ('1026', 850), ('1027', 300), ('1028', 400), ('1029', 300), ('1031', 800),
  ('1033', 400), ('1036', 350), ('1037', 875), ('1038', 1300), ('1042', 250), ('1043', 700), ('1052', 400), ('1053', 900), ('1054', 450), ('1055', 450),
  ('1056', 400), ('1057', 850), ('1058', 1200), ('1082', 350), ('1083', 450), ('1086', 400), ('1101', 450), ('1102', 450), ('1103', 450), ('1120', 450),
  ('2003', 50), ('2019', 1100), ('2020', 1337), ('2021', 1150), ('2022', 250), ('2031', 150), ('2051', 950), ('2055', 75), ('2065', 2200), ('2138', 500),
  ('2139', 500), ('2140', 500), ('2141', 300), ('2420', 1600), ('2501', 3300), ('2502', 2800), ('2503', 2800), ('2504', 2900), ('2508', 900), ('2510', 3100),
  ('2512', 2650), ('2517', 3100), ('2520', 3000), ('2522', 2800), ('2523', 2800), ('2524', 2300), ('2525', 2600), ('2526', 2250), ('3003', 2900), ('3004', 2900),
  ('3006', 1100), ('3008', 1100), ('3009', 1000), ('3020', 1100), ('3024', 900), ('3026', 3200), ('3031', 3500), ('3032', 3000), ('3033', 3000), ('3035', 1450),
  ('3036', 3300), ('3041', 1500), ('3044', 1100), ('3046', 2650), ('3047', 1200), ('3050', 2200), ('3051', 1200), ('3053', 3200), ('3057', 900), ('3065', 2700),
  ('3066', 800), ('3067', 800), ('3068', 2800), ('3070', 400), ('3071', 3000), ('3072', 3400), ('3073', 3000), ('3074', 3300), ('3075', 2450), ('3076', 800),
  ('3077', 1200), ('3078', 3333), ('3082', 1000), ('3083', 3100), ('3084', 3000), ('3085', 2650), ('3086', 1200), ('3087', 3000), ('3089', 3500), ('3091', 2800),
  ('3094', 2650), ('3095', 3200), ('3100', 2900), ('3102', 3000), ('3107', 2300), ('3108', 850), ('3109', 2300), ('3110', 2500), ('3111', 1250), ('3112', 950),
  ('3113', 900), ('3114', 600), ('3115', 2900), ('3116', 2600), ('3118', 2700), ('3119', 2400), ('3123', 800), ('3124', 3000), ('3133', 1050), ('3134', 1000),
  ('3135', 3000), ('3137', 3000), ('3139', 3200), ('3140', 1300), ('3142', 2800), ('3143', 2700), ('3144', 600), ('3145', 1100), ('3146', 3000), ('3147', 1300),
  ('3152', 2650), ('3153', 3200), ('3155', 1300), ('3156', 3100), ('3157', 3250), ('3158', 900), ('3161', 3100), ('3165', 2850), ('3168', 1100), ('3170', 1000),
  ('3171', 900), ('3172', 1100), ('3173', 1250), ('3174', 1200), ('3175', 1100), ('3177', 950), ('3179', 2800), ('3181', 3000), ('3184', 950), ('3190', 2200),
  ('3211', 1250), ('3222', 2300), ('3302', 3000), ('3340', 0), ('3363', 0), ('3364', 0), ('3504', 2200), ('3508', 3050), ('3742', 2900), ('3748', 3300),
  ('3801', 800), ('3802', 1200), ('3803', 1300), ('3814', 3000), ('3865', 400), ('3869', 400), ('3870', 400), ('3871', 400), ('3876', 400), ('3877', 400),
  ('3916', 800), ('4005', 2400), ('4401', 2800), ('4628', 2700), ('4629', 3000), ('4630', 1100), ('4632', 1600), ('4633', 3100), ('4642', 900), ('4645', 3200),
  ('4646', 2800), ('6333', 3300), ('6609', 3000), ('6610', 3100), ('6616', 2250), ('6617', 2200), ('6620', 2200), ('6621', 2500), ('6631', 3300), ('6653', 3000),
  ('6655', 2750), ('6657', 2600), ('6660', 900), ('6662', 2900), ('6664', 2800), ('6665', 3200), ('6670', 1300), ('6672', 3000), ('6673', 3000), ('6675', 2650),
  ('6676', 3000), ('6690', 775), ('6692', 2900), ('6694', 3000), ('6695', 2500), ('6696', 2750), ('6697', 2800), ('6698', 2850), ('6699', 3000), ('8010', 2900),
  ('8020', 2650)
) as v (id, gold);

-- 운영자: 가격표를 통째로 바꾼다. p_prices = {"1055": 450, ...} (Data Dragon 상점 아이템 전체)
create function public.set_item_prices(p_patch text, p_prices jsonb)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  n integer;
begin
  perform public.require_operator();
  if p_patch is null or p_patch !~ '^[0-9]{1,3}\.[0-9]{1,3}(\.[0-9]{1,3})?$' then
    raise exception '패치 버전 형식이 잘못됐어요.' using errcode = '23514';
  end if;
  if jsonb_typeof(p_prices) is distinct from 'object' then
    raise exception '가격표 형식이 잘못됐어요.' using errcode = '23514';
  end if;
  if exists (
    select 1 from jsonb_each(p_prices) e
    where e.key !~ '^[0-9]{1,6}$' or jsonb_typeof(e.value) <> 'number' or (e.value)::numeric < 0
       or (e.value)::numeric <> trunc((e.value)::numeric) or (e.value)::numeric > 100000
  ) then
    raise exception '가격표 형식이 잘못됐어요.' using errcode = '23514';
  end if;
  select count(*) into n from jsonb_object_keys(p_prices);
  if n < 50 then
    raise exception '아이템이 너무 적어요 (%개). 게임 데이터를 다시 불러와 주세요.', n using errcode = '23514';
  end if;
  delete from public.item_prices where true;
  insert into public.item_prices (id, gold, patch)
  select e.key, (e.value)::numeric::integer, p_patch from jsonb_each(p_prices) e;
  return n;
end;
$$;
revoke execute on function public.set_item_prices(text, jsonb) from public, anon;
grant execute on function public.set_item_prices(text, jsonb) to authenticated;

-- 시작 아이템 합계 검사 (같은 아이템 여러 개면 개수만큼 더한다)
create function public.check_start_gold(arr text[])
returns void language plpgsql stable security definer set search_path = ''
as $$
declare
  lim integer := public.xp_rule('starting_gold_max');
  missing text;
  total integer;
begin
  if lim is null or arr is null then
    return;
  end if;
  select x into missing from unnest(arr) x
   where not exists (select 1 from public.item_prices p where p.id = x)
   limit 1;
  if missing is not null then
    raise exception '가격을 모르는 시작 아이템이 있어요. 운영자가 아이템 가격표를 갱신한 뒤에 고를 수 있어요.' using errcode = '23514';
  end if;
  select coalesce(sum(p.gold), 0) into total from unnest(arr) x join public.item_prices p on p.id = x;
  if total > lim then
    raise exception '시작 아이템은 합계 %골드까지 고를 수 있어요. (지금 %골드)', lim, total using errcode = '23514';
  end if;
end;
$$;
-- 실행 권한은 그대로 둔다: 부른 사람 권한으로 도는 검사(clean_build 등)와 같은 이유 (막으면 문구 대신 권한 오류)

-- ---------------------------------------------------------------------
-- 2. 선마 하나로: 기존 값 백업 → max_skill 채우기 → 예전 칸 지우기
-- ---------------------------------------------------------------------
create table public.builds_skill_backup_018 as
  select id, skill_order, early_skills, original_build from public.builds;
comment on table public.builds_skill_backup_018 is '018 이전 빌드 스킬 값 백업 (선마 순서·1·2·3레벨). 확인 뒤 지워도 됨';
revoke all on public.builds_skill_backup_018 from anon, authenticated;
alter table public.builds_skill_backup_018 enable row level security;

create table public.proposal_build_backup_018 as
  select id, build from public.edit_proposals where build is not null;
comment on table public.proposal_build_backup_018 is '018 이전 새 카운터 제안 빌드 백업. 확인 뒤 지워도 됨';
revoke all on public.proposal_build_backup_018 from anon, authenticated;
alter table public.proposal_build_backup_018 enable row level security;

-- 빌드 jsonb: skill_order·early_skills → max_skill (선마 순서 첫 칸)
create function pg_temp.to_max_skill(b jsonb)
returns jsonb language sql immutable
as $$
  select case
    when jsonb_typeof(b) is distinct from 'object' or not (b ? 'skill_order' or b ? 'early_skills') then b
    else (b - 'skill_order' - 'early_skills') || jsonb_build_object('max_skill', b -> 'skill_order' -> 0)
  end;
$$;

alter table public.builds add column max_skill text;
update public.builds
   set max_skill = skill_order ->> 0,
       original_build = pg_temp.to_max_skill(original_build);
alter table public.builds
  alter column max_skill set not null,
  add constraint builds_max_skill_check check (max_skill in ('Q', 'W', 'E')),
  drop column skill_order,
  drop column early_skills;
comment on column public.builds.max_skill is '선마: 첫 번째로 마스터할 스킬 (Q/W/E)';
grant insert (max_skill) on public.builds to authenticated;

update public.edit_proposals set build = pg_temp.to_max_skill(build) where build is not null;

-- ---------------------------------------------------------------------
-- 3. 빌드 모양을 쓰는 함수들 (선마 하나 + 시작템 합계)
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
    raise exception '빌드(룬·주문·아이템·스킬)를 채워 주세요.' using errcode = '23514';
  end if;
  runes := public.clean_build_runes(b -> 'runes');

  spells := public.text_array(b -> 'summoner_spells', '소환사 주문');
  if cardinality(spells) <> 2 or exists (select 1 from unnest(spells) s where s !~ '^Summoner[A-Za-z]{1,30}$') then
    raise exception '소환사 주문을 2개 골라 주세요.' using errcode = '23514';
  end if;
  if spells[1] = spells[2] then
    raise exception '같은 소환사 주문을 두 번 고를 수 없어요.' using errcode = '23514';
  end if;

  starting := public.text_array(b -> 'starting_items', '시작 아이템');
  core := public.text_array(b -> 'core_items', '핵심 템트리');
  perform public.check_build_ids(starting, '시작 아이템', 1, 4, false);
  perform public.check_build_ids(core, '핵심 템트리', 3, 6, true);

  skill := b ->> 'max_skill';
  if jsonb_typeof(b -> 'max_skill') is distinct from 'string' or skill not in ('Q', 'W', 'E') then
    raise exception '선마(첫 번째로 마스터할 스킬)를 Q·W·E 중에서 골라 주세요.' using errcode = '23514';
  end if;

  patch := b ->> 'patch';
  if jsonb_typeof(b -> 'patch') is distinct from 'string' or patch !~ '^[0-9]{1,3}\.[0-9]{1,3}(\.[0-9]{1,3})?$' then
    raise exception '패치 버전 형식이 잘못됐어요.' using errcode = '23514';
  end if;

  return jsonb_build_object(
    'runes', runes, 'summoner_spells', to_jsonb(spells), 'starting_items', to_jsonb(starting), 'core_items', to_jsonb(core),
    'max_skill', skill, 'patch', patch
  );
end;
$$;

create or replace function public.build_json(b public.builds)
returns jsonb language sql immutable set search_path = ''
as $$
  select jsonb_build_object(
    'runes', b.runes, 'summoner_spells', to_jsonb(b.summoner_spells), 'starting_items', to_jsonb(b.starting_items),
    'core_items', to_jsonb(b.core_items), 'max_skill', b.max_skill, 'patch', b.patch
  );
$$;

create or replace function public.set_build_fields(p_id bigint, b jsonb)
returns void language sql set search_path = ''
as $$
  update public.builds
     set runes = b -> 'runes',
         summoner_spells = array(select jsonb_array_elements_text(b -> 'summoner_spells')),
         starting_items = array(select jsonb_array_elements_text(b -> 'starting_items')),
         core_items = array(select jsonb_array_elements_text(b -> 'core_items')),
         max_skill = b ->> 'max_skill',
         patch = b ->> 'patch'
   where id = p_id;
$$;

create or replace function public.check_new_build()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  st text;
  c jsonb;
  mine text;
begin
  select status into st from public.counters where id = new.counter_id;
  if st is distinct from 'approved' then
    raise exception '빌드를 등록할 매치업을 찾지 못했어요.' using errcode = '23514';
  end if;

  c := public.clean_build(public.build_json(new));
  new.runes := c -> 'runes';
  new.summoner_spells := array(select jsonb_array_elements_text(c -> 'summoner_spells'));
  new.starting_items := array(select jsonb_array_elements_text(c -> 'starting_items'));
  new.core_items := array(select jsonb_array_elements_text(c -> 'core_items'));
  new.max_skill := c ->> 'max_skill';
  perform public.check_start_gold(new.starting_items);

  -- 유저가 직접 등록하는 빌드 (운영자 함수가 넣는 제안의 첫 빌드는 바로 공개라 해당 없음)
  if new.status = 'pending' then
    select b.status into mine from public.builds b
     where b.counter_id = new.counter_id and b.author_id = new.author_id and b.status in ('pending', 'revision_requested')
     order by b.status = 'revision_requested' desc
     limit 1;
    if mine = 'revision_requested' then
      raise exception '이 매치업에 재검토 요청을 받은 내 빌드가 있어요. [내 활동]에서 고쳐서 다시 보내 주세요.' using errcode = '23514';
    end if;
    if mine = 'pending' then
      raise exception '이 매치업에 이미 승인 대기 중인 내 빌드가 있어요. 처리된 뒤에 다시 등록해 주세요.' using errcode = '23514';
    end if;
  end if;
  if exists (
    select 1 from public.builds b
    where b.counter_id = new.counter_id and b.status = 'approved' and public.build_signature(b) = public.build_signature(new)
  ) then
    raise exception '똑같은 빌드가 이미 공개돼 있어요. 따봉으로 응원해 주세요.' using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function public.publish_proposal_build(
  p public.edit_proposals, p_counter_id bigint, p_note text, p_build jsonb, p_original jsonb)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  b jsonb := public.clean_build(p_build);
  bid bigint;
  old record;
begin
  select id into bid from public.builds x
   where x.counter_id = p_counter_id and x.status = 'approved' and public.build_signature(x) = b - 'patch'
   order by (x.proposal_id = p.id) desc nulls last, x.id
   limit 1;
  if bid is null then
    insert into public.builds
      (counter_id, author_id, proposal_id, runes, summoner_spells, starting_items, core_items, max_skill, patch,
       status, approve_note, reviewed_by, reviewed_at, original_build)
    values (
      p_counter_id, p.proposer_id, p.id, b -> 'runes',
      array(select jsonb_array_elements_text(b -> 'summoner_spells')),
      array(select jsonb_array_elements_text(b -> 'starting_items')),
      array(select jsonb_array_elements_text(b -> 'core_items')),
      b ->> 'max_skill',
      b ->> 'patch', 'approved', p_note, (select auth.uid()), now(), p_original
    )
    returning id into bid;
    insert into public.build_status_log (build_id, action, reason, actor) values (bid, 'approve', p_note, (select auth.uid()));
  end if;

  -- 같은 제안에서 나왔던 예전 첫 빌드는 숨긴다 (새 것이 공개된 뒤라 공개 빌드가 0개가 되지 않는다)
  for old in
    select id from public.builds where proposal_id = p.id and status = 'approved' and id <> bid
  loop
    update public.builds set status = 'hidden', hide_reason = '재검토로 교체: ' || p_note, hidden_at = now() where id = old.id;
    insert into public.build_status_log (build_id, action, reason, actor)
    values (old.id, 'hide', '재검토로 교체: ' || p_note, (select auth.uid()));
  end loop;
  -- (6단계) 첫 빌드는 카운터 승인 경험치(+100)에 포함, 빌드 승인 +30은 따로 주지 않는다 (SPEC 6-1)
  return bid;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 시작템 합계 검사를 붙이는 트리거 (바뀌었을 때만, 이미 공개된 빌드는 건드리지 않음)
-- ---------------------------------------------------------------------
-- 빌드: 시작템이 바뀌거나(고치기·다시 제출·고쳐서 승인), 승인 대기 → 공개일 때
create function public.check_build_start_gold()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.starting_items is distinct from old.starting_items
     or (new.status = 'approved' and old.status in ('pending', 'revision_requested')) then
    perform public.check_start_gold(new.starting_items);
  end if;
  return new;
end;
$$;
create trigger builds_start_gold before update on public.builds
  for each row execute function public.check_build_start_gold();

-- 새 카운터 제안: 빌드를 넣거나 바꿀 때 (승인할 때는 공개되는 빌드가 builds에 들어가며 다시 검사된다)
create function public.check_proposal_start_gold()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.build is not null and (tg_op = 'INSERT' or new.build is distinct from old.build) then
    perform public.check_start_gold(public.text_array(new.build -> 'starting_items', '시작 아이템'));
  end if;
  return new;
end;
$$;
create trigger edit_proposals_start_gold before insert or update of build on public.edit_proposals
  for each row execute function public.check_proposal_start_gold();

revoke execute on function public.check_build_start_gold() from public, anon, authenticated;
revoke execute on function public.check_proposal_start_gold() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. 확인용: 선마만 남기니 똑같아진 공개 빌드 (있으면 운영자가 하나를 숨기면 된다)
-- ---------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select counter_id, array_agg(id order by id) as ids from public.builds
     where status = 'approved'
     group by counter_id, public.build_signature(builds)
    having count(*) > 1
  loop
    raise notice '똑같아진 공개 빌드: 카운터 % — 빌드 %', r.counter_id, r.ids;
  end loop;
  for r in
    select b.id, b.status, sum(coalesce(p.gold, 0)) as gold
      from public.builds b cross join unnest(b.starting_items) x left join public.item_prices p on p.id = x
     where b.status in ('approved', 'pending', 'revision_requested')
     group by b.id, b.status
    having sum(coalesce(p.gold, 0)) > public.xp_rule('starting_gold_max')
  loop
    raise notice '시작템 합계 초과 빌드: % (%) — %골드', r.id, r.status, r.gold;
  end loop;
end;
$$;

commit;
