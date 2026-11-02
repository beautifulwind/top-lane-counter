-- =====================================================================
-- 6단계: 경험치·레벨·칭호 (SPEC 6장)
-- 방식: "원래 기록에서 지금 받아야 할 양"을 계산하고, xp_events에는 이미 받은 양과의 차이만 +/− 줄로 쌓는다.
--   - 지급할 일마다 키(source_key): proposal:<id> / build:<id> / vote:<build_vote_log id>
--   - 숨김↔공개·재검토 후 재승인을 반복해도 키마다 남는 양은 한 번분 → 중복 지급이 생기지 않는다
--   - 받아야 할 양은 늘 0 이상 → 경험치가 0 아래로 내려가지 않는다
--   - 숫자는 xp_rules·xp_levels에만. 바꾼 뒤 recalc_all_xp()를 실행하면 차이만 "규칙 변경" 줄로 들어간다
-- 언제: 제안·빌드·카운터 상태, 따봉 수, 투표 기록, 삭제가 바뀌면 "트랜잭션 끝"에 그 사람을 다시 계산한다
--   (deferrable 트리거 → 승인·숨김·완전 삭제처럼 여러 표를 바꾸는 함수도 끝난 뒤 최종 상태로 계산)
-- 고정 기록: 비주류 여부는 "승인할 때" 목록에 있었는지(offmeta), 따봉은 "그 사람이 그 빌드에 처음 누른 따봉"인지(first_up)
--   — 나중에 비주류 목록이 바뀌거나 투표한 사람이 탈퇴해도 이미 센 것은 그대로
-- 운영자: 항상 Lv.0, 경험치·칭호 없음 (계산하지 않고, 003의 트리거도 지급 기록을 막는다)
-- 기존 데이터: 마지막에 한 번 계산한다 (내역 날짜 = 실제 승인·따봉 날짜, 알림 없음)
-- 013_proposer_edit.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 설정: 경험치·하루 상한·칭호 기준 / 레벨표
-- ---------------------------------------------------------------------
create table public.xp_rules (
  key    text primary key,
  value  integer not null check (value >= 0),
  note   text not null
);
comment on table public.xp_rules is '경험치·칭호 숫자 (SPEC 6장). 바꾼 뒤 select public.recalc_all_xp(); 실행';
insert into public.xp_rules (key, value, note) values
  ('new_counter',          100, '새 카운터 제안 승인 (함께 공개된 첫 빌드 포함)'),
  ('doc_edit',              50, '문서 수정 제안 승인'),
  ('build',                 30, '빌드 승인 (새 카운터의 첫 빌드는 제외)'),
  ('vote',                   2, '내 빌드가 따봉 받음 (같은 사람이 같은 빌드에 누른 것은 처음 1번만)'),
  ('vote_daily_cap',        40, '따봉 경험치 하루 상한 (한국 시간)'),
  ('post',                   5, '자유게시판 글 (게시판 단계)'),
  ('post_daily_cap',        25, '자유게시판 글 하루 상한 (게시판 단계)'),
  ('comment',                1, '자유게시판 댓글 (게시판 단계)'),
  ('comment_daily_cap',     10, '자유게시판 댓글 하루 상한 (게시판 단계)'),
  ('level_step',          1000, 'Lv.10 이후 레벨마다 필요한 경험치'),
  ('title_top_addict',       1, '탑신병자: 승인받은 기여'),
  ('title_tool_hater',      10, '도구혐오자: 카운터 관련 승인 (새 카운터 + 문서 수정)'),
  ('title_solid_heavy',     25, '단단묵직: 카운터 관련 승인'),
  ('title_butcher_owner',   50, '백정주인: 카운터 관련 승인'),
  ('title_general',        100, '장군: 공개 중인 내 빌드들의 따봉 합계'),
  ('title_offmeta',          5, '비주류: 비주류 픽 매치업 기여 승인 (승인할 때 목록 기준)');

create table public.xp_levels (
  level   integer primary key check (level >= 1),
  min_xp  integer not null unique check (min_xp >= 0)
);
comment on table public.xp_levels is '레벨별 필요 누적 경험치 (SPEC 6-2). 마지막 레벨 뒤는 xp_rules.level_step씩';
insert into public.xp_levels (level, min_xp) values
  (1, 0), (2, 100), (3, 300), (4, 600), (5, 1000), (6, 1500), (7, 2100), (8, 2800), (9, 3600), (10, 4500);

-- 설정은 누구나 읽기 (/me의 "다음 레벨까지"), 바꾸기는 SQL Editor에서만
revoke all on public.xp_rules, public.xp_levels from anon, authenticated;
grant select on public.xp_rules, public.xp_levels to anon, authenticated;
alter table public.xp_rules enable row level security;
alter table public.xp_levels enable row level security;
create policy "xp_rules: 누구나 읽기" on public.xp_rules for select using (true);
create policy "xp_levels: 누구나 읽기" on public.xp_levels for select using (true);

create function public.xp_rule(p_key text)
returns integer language sql stable security definer set search_path = ''
as $$ select value from public.xp_rules where key = p_key $$;

create function public.level_for(p_xp integer)
returns integer language sql stable security definer set search_path = ''
as $$
  with top as (select max(level) as lv, max(min_xp) as xp from public.xp_levels)
  select case
    when p_xp >= top.xp then top.lv + (p_xp - top.xp) / greatest(public.xp_rule('level_step'), 1)
    else (select max(level) from public.xp_levels where min_xp <= greatest(p_xp, 0))
  end
  from top;
$$;

-- 칭호 이름 (알림 문구용, 화면은 src/lib/titles.js) — "운영자"·"관리자"는 칭호에 쓰지 않는다
create function public.title_name(p_key text)
returns text language sql immutable set search_path = ''
as $$
  select case p_key
    when 'top_addict' then '탑신병자'
    when 'tool_hater' then '도구혐오자'
    when 'solid_heavy' then '단단묵직'
    when 'butcher_owner' then '백정주인'
    when 'general' then '장군'
    when 'offmeta' then '비주류'
    else p_key
  end;
$$;

-- ---------------------------------------------------------------------
-- 2. 경험치 기록 칸 / 고정 기록 칸
-- ---------------------------------------------------------------------
alter table public.xp_events
  add column source_key       text,     -- proposal:<id> / build:<id> / vote:<log id> — 키마다 합 = 지금 받은 양
  add column change           text check (change in ('grant', 'revoke', 'adjust')),
  add column reason           text,     -- 화면에 보일 이유 (예: 카운터 숨김)
  add column target_champion  text,     -- 매치업 이름 (카운터가 지워져도 내역에 남게 복사)
  add column counter_champion text;
comment on column public.xp_events.type is 'new_counter / doc_edit / build / vote (게시판 단계: post / comment)';
create index xp_events_source_idx on public.xp_events (user_id, source_key);

alter table public.edit_proposals add column offmeta boolean;
comment on column public.edit_proposals.offmeta is '처음 승인될 때 이기는 챔피언이 비주류 픽 목록에 있었나 (고정, 칭호 "비주류")';
alter table public.builds add column offmeta boolean;
comment on column public.builds.offmeta is '처음 공개될 때 이기는 챔피언이 비주류 픽 목록에 있었나 (고정)';
alter table public.build_vote_log add column first_up boolean not null default false;
comment on column public.build_vote_log.first_up is '이 사람이 이 빌드에 처음 누른 따봉 (경험치 대상, 투표할 때 고정)';

-- 승인(공개)될 때 비주류 여부를 한 번만 기록
create function public.stamp_offmeta()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  champ text;
begin
  if new.status = 'approved' and new.offmeta is null then
    if tg_table_name = 'builds' then
      select counter_champion into champ from public.counters where id = new.counter_id;
    else
      champ := new.counter_champion;
    end if;
    new.offmeta := exists (select 1 from public.offmeta_champions where champion_id = champ);
  end if;
  return new;
end;
$$;
create trigger edit_proposals_stamp_offmeta before insert or update of status on public.edit_proposals
  for each row execute function public.stamp_offmeta();
create trigger builds_stamp_offmeta before insert or update of status on public.builds
  for each row execute function public.stamp_offmeta();

-- 투표할 때 "처음 누른 따봉"인지 기록
create function public.stamp_first_up()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  new.first_up := new.new_value = 1 and new.voter_id is not null and not exists (
    select 1 from public.build_vote_log l where l.build_id = new.build_id and l.voter_id = new.voter_id and l.first_up
  );
  return new;
end;
$$;
create trigger build_vote_log_stamp_first_up before insert on public.build_vote_log
  for each row execute function public.stamp_first_up();

-- ---------------------------------------------------------------------
-- 3. 알림 종류
-- ---------------------------------------------------------------------
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications
  add constraint notifications_kind_check check (kind in (
    'revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected',
    'build_approved', 'build_rejected', 'build_hidden', 'build_restored',
    'level_up', 'level_down', 'title_earned', 'title_revoked'));

-- ---------------------------------------------------------------------
-- 4. 지금 받아야 할 경험치 (키마다 한 줄)
-- ---------------------------------------------------------------------
create function public.xp_should_have(p_user uuid)
returns table (source_key text, kind text, ref_id text, amount integer, at timestamptz, target_champion text, counter_champion text)
language sql stable security definer set search_path = ''
as $$
  -- 새 카운터: 승인 + 카운터 공개 중 (숨기면 0, 다시 공개·재승인하면 같은 키로 돌아온다)
  select 'proposal:' || p.id, 'new_counter', p.id::text, public.xp_rule('new_counter'), p.reviewed_at, p.target_champion, p.counter_champion
  from public.edit_proposals p join public.counters c on c.id = p.counter_id
  where p.proposer_id = p_user and p.type = 'new_counter' and p.status = 'approved' and c.status = 'approved'
  union all
  -- 문서 수정: 승인 + 카운터가 있음 (숨김은 회수하지 않고 완전 삭제만)
  select 'proposal:' || p.id, 'doc_edit', p.id::text, public.xp_rule('doc_edit'), p.reviewed_at, p.target_champion, p.counter_champion
  from public.edit_proposals p join public.counters c on c.id = p.counter_id
  where p.proposer_id = p_user and p.type = 'doc_edit' and p.status = 'approved'
  union all
  -- 빌드: 공개 중, 새 카운터의 첫 빌드는 카운터 +100에 포함
  select 'build:' || b.id, 'build', b.id::text, public.xp_rule('build'), b.reviewed_at, c.target_champion, c.counter_champion
  from public.builds b join public.counters c on c.id = b.counter_id
  where b.author_id = p_user and b.status = 'approved' and b.proposal_id is null
  union all
  -- 따봉: 처음 누른 따봉만, 받은 사람 기준 하루(한국 시간) 상한 — 상한은 지워진 빌드의 따봉까지 넣고 센다
  --       (빌드가 지워졌다고 그날 상한에 걸렸던 따봉이 새로 들어오지 않게). 빌드가 남아 있는 동안만 (숨겨도 유지)
  select 'vote:' || v.id, 'vote', v.build_id::text, public.xp_rule('vote'), v.created_at, c.target_champion, c.counter_champion
  from (
    select l.*, row_number() over (
      partition by (l.created_at at time zone 'Asia/Seoul')::date order by l.created_at, l.id) as rn
    from public.build_vote_log l
    where l.author_id = p_user and l.first_up
  ) v
  join public.builds b on b.id = v.build_id
  join public.counters c on c.id = b.counter_id
  where v.rn <= public.xp_rule('vote_daily_cap') / greatest(public.xp_rule('vote'), 1);
$$;

-- 줄이 바뀐 이유 (화면용)
create function public.xp_reason(p_kind text, p_ref text, p_want integer, p_have integer, p_seen boolean)
returns text language plpgsql stable security definer set search_path = ''
as $$
declare
  st text;
  cst text;
begin
  if p_want > 0 and p_have > 0 then
    return '규칙 변경';
  end if;
  if p_want > 0 then
    return case when p_seen then '다시 공개·승인' else null end;
  end if;
  -- 회수
  if p_kind in ('new_counter', 'doc_edit') then
    select p.status, c.status into st, cst
    from public.edit_proposals p left join public.counters c on c.id = p.counter_id where p.id = p_ref::bigint;
    if not found or cst is null then return '카운터 삭제'; end if;
    if st = 'revoked' or cst = 'hidden' then return '카운터 숨김 (승인 취소)'; end if;
    return '승인 취소';
  elsif p_kind = 'build' then
    select status into st from public.builds where id = p_ref::bigint;
    if not found then return '카운터 삭제'; end if;
    if st = 'hidden' then return '빌드 숨김'; end if;
    return '승인 취소';
  elsif p_kind = 'vote' then
    if not exists (select 1 from public.builds where id = p_ref::bigint) then return '빌드 삭제 (카운터 삭제)'; end if;
    return '규칙 변경';
  end if;
  return null;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. 한 사람 다시 계산: 경험치 차이 기록 → 경험치·레벨 → 칭호 (+ 알림)
--    p_quiet: 기존 데이터 계산(알림 없음, 지급 줄 날짜 = 실제 승인·따봉 날짜)
-- ---------------------------------------------------------------------
create function public.sync_rewards(p_user uuid, p_quiet boolean default false)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  prof public.profiles%rowtype;
  r record;
  total integer;
  lv integer;
  counter_cnt integer;
  contrib_cnt integer;
  offmeta_cnt integer;
  ups integer;
  want text[];
  t text;
begin
  if p_user is null then
    return;
  end if;
  select * into prof from public.profiles where id = p_user for update;
  if not found or prof.role = 'admin' then
    return;  -- 탈퇴했거나 운영자 (항상 Lv.0, 경험치·칭호 없음)
  end if;

  -- 경험치: 키마다 (받아야 할 양 − 이미 받은 양)만 기록
  for r in
    with should as (select * from public.xp_should_have(p_user)),
    got as (
      select e.source_key, sum(e.amount)::integer as amount, max(e.type) as kind, max(e.ref_id) as ref_id,
             max(e.target_champion) as target_champion, max(e.counter_champion) as counter_champion
      from public.xp_events e where e.user_id = p_user and e.source_key is not null group by e.source_key
    )
    select coalesce(w.source_key, h.source_key) as source_key, coalesce(w.kind, h.kind) as kind,
           coalesce(w.ref_id, h.ref_id) as ref_id, coalesce(w.amount, 0) as want, coalesce(h.amount, 0) as have,
           h.source_key is not null as seen, w.at,
           coalesce(w.target_champion, h.target_champion) as target_champion,
           coalesce(w.counter_champion, h.counter_champion) as counter_champion
    from should w full join got h on h.source_key = w.source_key
    where coalesce(w.amount, 0) <> coalesce(h.amount, 0)
    order by coalesce(w.at, now())
  loop
    insert into public.xp_events
      (user_id, type, amount, ref_id, source_key, change, reason, target_champion, counter_champion, created_at)
    values (
      p_user, r.kind, r.want - r.have, r.ref_id, r.source_key,
      case when r.want = 0 then 'revoke' when r.have = 0 then 'grant' else 'adjust' end,
      public.xp_reason(r.kind, r.ref_id, r.want, r.have, r.seen),
      r.target_champion, r.counter_champion,
      case when p_quiet and r.have = 0 and r.at is not null then r.at else now() end
    );
  end loop;

  select greatest(coalesce(sum(amount), 0), 0) into total from public.xp_events where user_id = p_user;
  lv := public.level_for(total);
  if prof.xp is distinct from total or prof.level is distinct from lv then
    update public.profiles set xp = total, level = lv where id = p_user;
    if not p_quiet and lv > prof.level then
      insert into public.notifications (user_id, kind, message) values (p_user, 'level_up', format('레벨이 올랐어요: Lv.%s', lv));
    elsif not p_quiet and lv < prof.level then
      insert into public.notifications (user_id, kind, message)
      values (p_user, 'level_down', format('승인 취소·삭제로 경험치가 줄어 레벨이 내려갔어요: Lv.%s', lv));
    end if;
  end if;

  -- 칭호: 지금 유효한 기여만 센다 (경험치와 같은 기준, 새 카운터의 첫 빌드는 카운터와 함께 1개)
  with contrib as (
    select p.type as kind, p.offmeta
    from public.edit_proposals p join public.counters c on c.id = p.counter_id
    where p.proposer_id = p_user and p.status = 'approved' and (p.type = 'doc_edit' or c.status = 'approved')
    union all
    select 'build', b.offmeta
    from public.builds b join public.counters c on c.id = b.counter_id
    where b.author_id = p_user and b.status = 'approved' and b.proposal_id is null
  )
  select count(*) filter (where kind in ('new_counter', 'doc_edit')), count(*), count(*) filter (where offmeta)
    into counter_cnt, contrib_cnt, offmeta_cnt
  from contrib;
  -- 장군: 공개 중인 내 빌드(카운터도 공개)의 지금 따봉 수 합계
  select coalesce(sum(b.up_count), 0) into ups
  from public.builds b join public.counters c on c.id = b.counter_id
  where b.author_id = p_user and b.status = 'approved' and c.status = 'approved';

  want := array_remove(array[
    case when contrib_cnt >= public.xp_rule('title_top_addict') then 'top_addict' end,
    case when counter_cnt >= public.xp_rule('title_tool_hater') then 'tool_hater' end,
    case when counter_cnt >= public.xp_rule('title_solid_heavy') then 'solid_heavy' end,
    case when counter_cnt >= public.xp_rule('title_butcher_owner') then 'butcher_owner' end,
    case when ups >= public.xp_rule('title_general') then 'general' end,
    case when offmeta_cnt >= public.xp_rule('title_offmeta') then 'offmeta' end
  ], null);

  for t in select title_key from public.user_titles where user_id = p_user and not (title_key = any (want)) loop
    delete from public.user_titles where user_id = p_user and title_key = t;  -- 대표 칭호였으면 FK가 비운다
    if not p_quiet then
      insert into public.notifications (user_id, kind, message)
      values (p_user, 'title_revoked', format('칭호가 회수됐어요: %s (승인 취소·삭제 등으로 조건이 깨졌어요)', public.title_name(t)));
    end if;
  end loop;
  foreach t in array want loop
    if not exists (select 1 from public.user_titles where user_id = p_user and title_key = t) then
      insert into public.user_titles (user_id, title_key) values (p_user, t);
      if not p_quiet then
        insert into public.notifications (user_id, kind, message)
        values (p_user, 'title_earned', format('칭호를 얻었어요: %s — [내 활동]에서 대표 칭호로 고를 수 있어요.', public.title_name(t)));
      end if;
    end if;
  end loop;
end;
$$;

-- 모두 다시 계산 (규칙을 바꾼 뒤 SQL Editor에서: select public.recalc_all_xp();) 돌려주는 값: 계산한 사람 수
create function public.recalc_all_xp(p_quiet boolean default false)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  u uuid;
  n integer := 0;
begin
  for u in select id from public.profiles where role <> 'admin' order by created_at loop
    perform public.sync_rewards(u, p_quiet);
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- ---------------------------------------------------------------------
-- 6. 언제 다시 계산하나: 트랜잭션 끝에 (함수 안에서 여러 표를 바꿔도 최종 상태로, 완전 삭제의 cascade도 끝난 뒤)
-- ---------------------------------------------------------------------
create function public.rewards_on_proposal()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  perform public.sync_rewards(case when tg_op = 'DELETE' then old.proposer_id else new.proposer_id end);
  return null;
end;
$$;
create constraint trigger edit_proposals_rewards after update of status, counter_id, proposer_id or delete on public.edit_proposals
  deferrable initially deferred for each row execute function public.rewards_on_proposal();

create function public.rewards_on_build()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  perform public.sync_rewards(case when tg_op = 'DELETE' then old.author_id else new.author_id end);
  return null;
end;
$$;
create constraint trigger builds_rewards after insert or update of status, up_count, author_id, proposal_id or delete on public.builds
  deferrable initially deferred for each row execute function public.rewards_on_build();

-- 카운터 숨김·다시 공개: 그 카운터의 제안자·빌드 작성자 모두
create function public.rewards_on_counter()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  u uuid;
begin
  for u in
    select proposer_id from public.edit_proposals where counter_id = new.id
    union select author_id from public.builds where counter_id = new.id
  loop
    perform public.sync_rewards(u);
  end loop;
  return null;
end;
$$;
create constraint trigger counters_rewards after insert or update of status on public.counters
  deferrable initially deferred for each row execute function public.rewards_on_counter();

create function public.rewards_on_vote()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  perform public.sync_rewards(new.author_id);
  return null;
end;
$$;
create constraint trigger build_vote_log_rewards after insert on public.build_vote_log
  deferrable initially deferred for each row execute function public.rewards_on_vote();

-- ---------------------------------------------------------------------
-- 7. 비주류 픽 목록 (운영자) — 바꿔도 이미 승인된 기여는 그대로 (승인할 때 기록한 offmeta 기준)
-- ---------------------------------------------------------------------
create function public.add_offmeta(p_champion text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  if p_champion is null or p_champion !~ '^[A-Za-z]{1,30}$' then
    raise exception '챔피언을 다시 골라 주세요.' using errcode = '23514';
  end if;
  if exists (select 1 from public.offmeta_champions where champion_id = p_champion) then
    raise exception '이미 비주류 픽 목록에 있어요.' using errcode = '23514';
  end if;
  insert into public.offmeta_champions (champion_id, added_by) values (p_champion, (select auth.uid()));
end;
$$;

create function public.remove_offmeta(p_champion text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  delete from public.offmeta_champions where champion_id = p_champion;
  if not found then
    raise exception '비주류 픽 목록에 없는 챔피언이에요.' using errcode = 'P0002';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 8. 권한: 경험치·칭호·비주류 목록은 DB 함수만 쓴다 (운영자도 표를 직접 못 고침)
-- ---------------------------------------------------------------------
revoke insert, update, delete on public.xp_events, public.user_titles, public.offmeta_champions from authenticated;
drop policy "xp_events: 관리자 쓰기" on public.xp_events;
drop policy "user_titles: 관리자 쓰기" on public.user_titles;
drop policy "offmeta_champions: 관리자 쓰기" on public.offmeta_champions;

revoke execute on function public.xp_rule(text) from public, anon, authenticated;
revoke execute on function public.level_for(integer) from public, anon, authenticated;
revoke execute on function public.title_name(text) from public, anon, authenticated;
revoke execute on function public.stamp_offmeta() from public, anon, authenticated;
revoke execute on function public.stamp_first_up() from public, anon, authenticated;
revoke execute on function public.xp_should_have(uuid) from public, anon, authenticated;
revoke execute on function public.xp_reason(text, text, integer, integer, boolean) from public, anon, authenticated;
revoke execute on function public.sync_rewards(uuid, boolean) from public, anon, authenticated;
revoke execute on function public.recalc_all_xp(boolean) from public, anon, authenticated;
revoke execute on function public.rewards_on_proposal() from public, anon, authenticated;
revoke execute on function public.rewards_on_build() from public, anon, authenticated;
revoke execute on function public.rewards_on_counter() from public, anon, authenticated;
revoke execute on function public.rewards_on_vote() from public, anon, authenticated;
revoke execute on function public.add_offmeta(text) from public, anon;
revoke execute on function public.remove_offmeta(text) from public, anon;
grant execute on function public.add_offmeta(text) to authenticated;
grant execute on function public.remove_offmeta(text) to authenticated;

-- ---------------------------------------------------------------------
-- 9. 기존 데이터: 고정 기록 채우기 → 모두 한 번 계산 (알림 없음)
-- ---------------------------------------------------------------------
-- 이미 승인된(그 뒤 숨겨진 것 포함) 기여의 비주류 여부 = 지금 목록 기준
update public.edit_proposals p set offmeta = exists (select 1 from public.offmeta_champions o where o.champion_id = p.counter_champion)
 where p.status in ('approved', 'revoked') and p.offmeta is null;
update public.builds b set offmeta = exists (
  select 1 from public.counters c join public.offmeta_champions o on o.champion_id = c.counter_champion where c.id = b.counter_id)
 where b.status in ('approved', 'hidden') and b.offmeta is null;
-- 지금까지의 투표 기록: 사람마다 빌드마다 처음 누른 따봉
update public.build_vote_log l set first_up = true
 where l.id in (
   select distinct on (build_id, voter_id) id from public.build_vote_log
   where new_value = 1 and voter_id is not null order by build_id, voter_id, created_at, id);

-- 칭호 키가 바뀌었다 (연구소 칭호 → 6개). 혹시 남아 있는 옛 칭호는 지운다 (대표 칭호면 FK가 비움)
delete from public.user_titles
 where title_key not in ('top_addict', 'tool_hater', 'solid_heavy', 'butcher_owner', 'general', 'offmeta');

select public.recalc_all_xp(true);

commit;
