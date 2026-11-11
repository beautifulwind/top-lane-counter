-- =====================================================================
-- 038: 상대법 = 빌드 묶음, 빌드 = 완성된 공략 (위키 방식·무승인) — DB 준비 (2026-11-11, SPEC 6-25)
--
-- 1. builds에 공략 칸: 이름(선택)·번호(seq, "빌드 N")·한 줄 요약·레벨별 딜교법·특이사항·마지막 수정(시각·사람)·wiki 표시
--    counters에 first_build_id(상대법과 함께 등록된 첫 빌드)·wiki 표시
-- 2. build_revisions(모든 등록·수정의 전후 내용, 운영자 전용 — 아무도 직접 못 읽음, 1년 보관)
--    build_editors(기여자 목록 — 시초(빌드 작성자) 말고 고친 사람, build_contributors()로만 읽음)
--    wiki_last_write(등록·수정 간격)
-- 3. 함수 (승인 없이 바로 공개):
--    create_matchup(상대, 플레이할, 빌드)  — 새 상대법 + 첫 빌드. 운영자에게 matchup_created 알림
--    create_build(상대법, 빌드)            — 새 빌드. 운영자에게 build_created 알림
--    edit_build(빌드, 본 버전, 빌드)        — 누구나 수정(위키). 남의 빌드는 정식 회원만(비회원은 내 빌드만).
--                                            버전이 다르면 TL412 「다른 분이 먼저 수정했습니다. 최신 내용을 확인해 주세요.」
--    build_contributors(빌드)              — 기여자 닉네임 목록(시초 표시는 is_origin 칸 — 닉네임 글자와 별개)
-- 4. 경험치·칭호: 새 상대법 +100(키 matchup:<id>), 새 빌드 +30(키 build:<id>) — 위키로 등록한 것은 그날(한국 시간)
--    먼저 등록한 순서대로 합계 create_daily_cap(200)까지. 수정은 0. 숨기면 회수. 예전 승인 기록은 그대로.
--    칭호(도구혐오자·단단묵직·백정주인)는 승인된 제안 + 내가 시초인 공개 상대법 + 공개 빌드를 센다.
-- 5. 알림·푸시: matchup_created·build_created (운영자만, 처리자 본인 제외, 운영자 모드를 끄면 안 보임·푸시 안 감)
-- 6. 승인 제도 스위치 xp_rules.approval_on (이 파일은 1 = 켜짐 그대로). 039가 0으로 바꾸면 옛 화면의
--    제안·빌드 등록(승인 대기)을 DB가 「이제 승인 없이 바로 등록합니다. 화면을 새로고침해 주세요.」로 거부한다.
-- 7. 기존 데이터 이전: 상대법마다 matchup_docs 내용을 그 상대법의 공개(숨김 포함) 빌드에 복사, 번호·첫 빌드 지정,
--    'migrate' 수정 기록 1줄, 승인된 문서 수정 제안자를 기여자로. 시초 = 빌드 작성자(첫 빌드 = 처음 제안자).
--    (wiki_backfill_matchups() — 039에서 한 번 더 부른다: 그 사이 옛 화면으로 승인된 빌드도 채움)
--
-- 하위 호환: 있던 칸·함수 모양은 그대로이고 승인 제도도 켜진 채라 지금 배포된 화면이 그대로 동작한다.
--   - 038 ~ 039 사이 옛 길로 승인된 빌드·문서 수정: 빌드가 공개될 때 문서 내용을 채우고(트리거), 문서가 바뀌면
--     아직 문서와 같은 내용인 빌드에도 반영한다(트리거).
--   - 새 상대법은 옛 화면용으로 matchup_docs 사본도 만든다 (PWA에 남은 옛 화면에서도 내용이 보이게).
-- 순서: 이 파일 실행 → supabase/scripts/check_wiki_builds.sql로 확인 → (2단계) 새 코드 push → 039.
-- 037까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 0. 설정값
-- ---------------------------------------------------------------------
insert into public.xp_rules (key, value, note) values
  ('approval_on', 1, '승인 제도 켜짐(1)/꺼짐(0) — 꺼지면 옛 제안·빌드 승인 대기 등록을 DB가 거부 (038, 039가 0으로)'),
  ('create_daily_cap', 200, '위키로 등록한 새 상대법(+100)·새 빌드(+30) 경험치 하루(한국 시간) 상한 (038)'),
  ('wiki_create_interval', 60, '새 상대법·새 빌드 등록 간격(초) (038)'),
  ('build_edit_interval', 10, '빌드 수정 간격(초) (038)'),
  ('build_caution_ups', 3, '추천이 이만큼 이상인 빌드를 고칠 때 「많은 분이 추천한 빌드입니다. 신중히 수정해 주세요」 안내 (화면, 038)'),
  ('build_revision_keep_days', 365, '빌드 수정 기록(전후 내용) 보관 기간(일) — 지나면 매일 지움 (purge_old_build_revisions, pg_cron)')
on conflict (key) do nothing;

create function public.approval_on()
returns boolean language sql stable security definer set search_path = ''
as $$ select coalesce(public.xp_rule('approval_on'), 1) = 1 $$;
comment on function public.approval_on() is '승인 제도가 켜져 있는가 (xp_rules.approval_on, 038)';

-- ---------------------------------------------------------------------
-- 1. 칸 추가
-- ---------------------------------------------------------------------
alter table public.builds
  add column name text check (name is null or char_length(name) between 1 and 20),
  add column seq integer,
  add column summary text,
  add column level_notes jsonb,
  add column lane_cautions text,
  add column updated_at timestamptz,
  add column updated_by uuid references public.profiles (id) on delete set null,
  add column wiki boolean not null default false;
update public.builds set updated_at = coalesce(reviewed_at, created_at);
alter table public.builds alter column updated_at set default now();
create unique index builds_counter_seq on public.builds (counter_id, seq) where seq is not null;
comment on column public.builds.name is '빌드 이름 (선택, 1~20자). 비면 화면이 "빌드 {seq}" (038)';
comment on column public.builds.seq is '상대법 안 번호 — 공개될 때 정해지고 바뀌지 않음 (038)';
comment on column public.builds.summary is '한 줄 요약 (038 — 예전 matchup_docs에서 옮김)';
comment on column public.builds.updated_by is '마지막으로 고친 사람 (038, 탈퇴하면 비움)';
comment on column public.builds.wiki is '승인 없이 위키로 등록된 빌드 (038) — 경험치 하루 상한 대상';

alter table public.counters
  add column first_build_id bigint,
  add column wiki boolean not null default false;
comment on column public.counters.first_build_id is
  '상대법과 함께 등록된 첫 빌드 (038). 첫 빌드는 상대법 +100에 포함(+30 따로 없음). 빌드와 외래 키로 묶지 않음(상대법 삭제 때 빌드와 함께 지워짐)';
comment on column public.counters.wiki is '승인 없이 위키로 등록된 상대법 (038). proposed_by = 시초';

-- ---------------------------------------------------------------------
-- 2. 수정 기록 · 기여자 · 간격
-- ---------------------------------------------------------------------
create table public.build_revisions (
  id bigint generated always as identity primary key,
  build_id bigint not null references public.builds (id) on delete cascade,
  counter_id bigint not null,
  editor_id uuid references public.profiles (id) on delete set null,
  kind text not null check (kind in ('migrate', 'create', 'edit', 'revert')),
  before jsonb,
  after jsonb not null,
  version integer not null,
  created_at timestamptz not null default now()
);
create index build_revisions_build on public.build_revisions (build_id, id desc);
create index build_revisions_created on public.build_revisions (created_at);
alter table public.build_revisions enable row level security;  -- 정책 없음: 아무도 직접 못 읽고 못 씀
revoke all on public.build_revisions from anon, authenticated;
comment on table public.build_revisions is
  '빌드 등록·수정 기록 (038): 수정자·시각·전후 내용. 운영자 전용(다음 작업의 운영자 함수로만 읽음), build_revision_keep_days(365)일 뒤 지움';

create table public.build_editors (
  build_id bigint not null references public.builds (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  first_at timestamptz not null default now(),
  last_at timestamptz not null default now(),
  edits integer not null default 1,
  primary key (build_id, user_id)
);
alter table public.build_editors enable row level security;
revoke all on public.build_editors from anon, authenticated;
comment on table public.build_editors is
  '빌드 기여자 (038): 시초(builds.author_id) 말고 그 빌드를 고친 사람. build_contributors()로만 읽음. 탈퇴하면 빠짐. 수정 기록 정리와 상관없이 빌드가 있는 동안 남음';

create table public.wiki_last_write (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  created_at timestamptz,
  edited_at timestamptz
);
alter table public.wiki_last_write enable row level security;
revoke all on public.wiki_last_write from anon, authenticated;
comment on table public.wiki_last_write is '상대법·빌드 등록과 빌드 수정의 마지막 시각 (038, 간격 제한용, 아무도 직접 못 읽음)';

-- ---------------------------------------------------------------------
-- 3. 도우미
-- ---------------------------------------------------------------------
-- 빌드 한 줄의 공략 전체 (수정 기록·바뀐 것 비교용)
create function public.wiki_snapshot(b public.builds)
returns jsonb language sql stable set search_path = ''
as $$
  select public.build_json(b) || jsonb_build_object(
    'name', b.name, 'summary', b.summary, 'level_notes', b.level_notes, 'lane_cautions', coalesce(b.lane_cautions, ''));
$$;

-- 화면이 보낸 빌드(룬·주문·아이템·선마·패치 + 이름·요약·딜교법·특이사항) 검사 → wiki_snapshot과 같은 모양
create function public.clean_wiki_build(p jsonb)
returns jsonb language plpgsql stable set search_path = ''
as $$
declare
  b jsonb := public.clean_build(p);
  d jsonb := public.clean_doc_content(jsonb_build_object(
    'summary', p -> 'summary', 'level_notes', p -> 'level_notes', 'lane_cautions', p -> 'lane_cautions'));
  nm text := nullif(btrim(coalesce(p ->> 'name', '')), '');
begin
  if char_length(nm) > 20 then
    raise exception '빌드 이름은 20자 이하로 적어 주세요.' using errcode = '23514';
  end if;
  return b || d || jsonb_build_object('name', nm);
end;
$$;

-- 등록·수정 간격 (p_kind: create / edit)
create function public.wiki_throttle(p_kind text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  secs integer := public.xp_rule(case p_kind when 'create' then 'wiki_create_interval' else 'build_edit_interval' end);
  last timestamptz;
  wait integer;
begin
  insert into public.wiki_last_write (user_id) values (me) on conflict (user_id) do nothing;
  select case p_kind when 'create' then created_at else edited_at end into last
    from public.wiki_last_write where user_id = me for update;
  if last is not null and secs is not null and last > now() - make_interval(secs => secs) then
    wait := greatest(ceil(extract(epoch from (last + make_interval(secs => secs) - now())))::integer, 1);
    raise exception '%은 %초에 한 번 할 수 있습니다. %초 뒤에 다시 해 주세요.',
      case p_kind when 'create' then '새 상대법·빌드 등록' else '빌드 수정' end, secs, wait using errcode = '23514';
  end if;
  if p_kind = 'create' then
    update public.wiki_last_write set created_at = now() where user_id = me;
  else
    update public.wiki_last_write set edited_at = now() where user_id = me;
  end if;
end;
$$;

-- 운영자에게만 알림 (처리자 본인 제외. 운영자 모드를 끄면 RLS가 가리고 푸시도 안 감 — 034·037과 같음)
create function public.notify_admins_wiki(p_kind text, p_message text, p_counter bigint, p_build bigint)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.notifications (user_id, kind, message, counter_id, build_id)
  select u.id, p_kind, p_message, p_counter, p_build
    from public.profiles u
   where u.role = 'admin' and u.id is distinct from (select auth.uid());
end;
$$;

-- 위키 빌드 한 줄 넣기 (검사는 끝난 내용 c). 'create' 수정 기록까지
create function public.wiki_insert_build(p_counter bigint, p_author uuid, c jsonb)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  nb public.builds;
  spells text[] := array(select jsonb_array_elements_text(c -> 'summoner_spells'));
  core text[] := array(select jsonb_array_elements_text(c -> 'core_items'));
begin
  -- 바로 공개되는 줄은 트리거가 핵심 템트리·강타 검사를 건너뛰므로(예전 승인 빌드용 예외) 여기서 한다
  perform public.check_core_items(core);
  perform public.check_no_smite(spells);
  insert into public.builds
    (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch, status,
     name, summary, level_notes, lane_cautions, wiki, updated_by)
  values (
    p_counter, p_author, c -> 'runes', spells, array(select jsonb_array_elements_text(c -> 'starting_items')), core,
    c ->> 'max_skill', c ->> 'patch', 'approved',
    c ->> 'name', c ->> 'summary', c -> 'level_notes', c ->> 'lane_cautions', true, p_author
  )
  returning * into nb;  -- check_new_build가 상대법 공개 여부·시작 골드·똑같은 공개 빌드를 검사한다
  insert into public.build_revisions (build_id, counter_id, editor_id, kind, before, after, version)
  values (nb.id, nb.counter_id, p_author, 'create', null, public.wiki_snapshot(nb), nb.version);
  return nb.id;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 트리거: 빌드가 공개될 때 번호·문서 내용 채우기 / 문서가 바뀌면 같은 내용 빌드에 반영 (038 ~ 039 사이 옛 길용)
-- ---------------------------------------------------------------------
create function public.builds_wiki_fill()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  d public.matchup_docs;
begin
  if new.status = 'approved' then
    if new.summary is null then
      select * into d from public.matchup_docs where counter_id = new.counter_id;
      if found then
        new.summary := d.summary;
        new.level_notes := d.level_notes;
        new.lane_cautions := coalesce(d.lane_cautions, '');
      end if;
    end if;
    if new.seq is null then
      perform 1 from public.counters where id = new.counter_id for update;  -- 같은 상대법에 동시에 공개돼도 번호가 겹치지 않게
      select coalesce(max(seq), 0) + 1 into new.seq from public.builds where counter_id = new.counter_id;
    end if;
  end if;
  return new;
end;
$$;
create trigger builds_wiki_fill before insert or update of status on public.builds
  for each row execute function public.builds_wiki_fill();

create function public.matchup_docs_to_builds()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  b public.builds;
  nb public.builds;
begin
  if (new.summary, new.level_notes, coalesce(new.lane_cautions, ''))
     is not distinct from (old.summary, old.level_notes, coalesce(old.lane_cautions, '')) then
    return null;
  end if;
  for b in
    select * from public.builds x
     where x.counter_id = new.counter_id and x.summary is not null
       and (x.summary, x.level_notes, coalesce(x.lane_cautions, '')) = (old.summary, old.level_notes, coalesce(old.lane_cautions, ''))
     for update
  loop
    update public.builds
       set summary = new.summary, level_notes = new.level_notes, lane_cautions = coalesce(new.lane_cautions, ''),
           updated_at = now(), updated_by = new.updated_by, version = version + 1
     where id = b.id
     returning * into nb;
    insert into public.build_revisions (build_id, counter_id, editor_id, kind, before, after, version)
    values (b.id, b.counter_id, new.updated_by, 'migrate', public.wiki_snapshot(b), public.wiki_snapshot(nb), nb.version);
    if new.updated_by is not null and new.updated_by is distinct from b.author_id then
      insert into public.build_editors (build_id, user_id) values (b.id, new.updated_by)
      on conflict (build_id, user_id) do update set last_at = now(), edits = public.build_editors.edits + 1;
    end if;
  end loop;
  return null;
end;
$$;
create trigger matchup_docs_to_builds after update on public.matchup_docs
  for each row execute function public.matchup_docs_to_builds();

-- ---------------------------------------------------------------------
-- 5. 기존 데이터 이전 (다시 불러도 같은 결과 — 039에서 한 번 더 부른다)
--    돌려주는 값: 내용을 채운 빌드 수
-- ---------------------------------------------------------------------
create function public.wiki_backfill_matchups()
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  r record;
  nb public.builds;
  filled integer := 0;
begin
  -- 문서 내용 → 공개(숨김 포함) 빌드
  for r in
    select b.id, d.summary, d.level_notes, d.lane_cautions, d.updated_at
      from public.builds b join public.matchup_docs d on d.counter_id = b.counter_id
     where b.summary is null and b.status in ('approved', 'hidden')
     order by b.id
  loop
    update public.builds
       set summary = r.summary, level_notes = r.level_notes, lane_cautions = coalesce(r.lane_cautions, ''),
           updated_at = greatest(coalesce(updated_at, created_at), coalesce(r.updated_at, created_at))
     where id = r.id;
    filled := filled + 1;
  end loop;

  -- 번호: 공개(숨김 포함) 빌드에 등록 순서대로
  update public.builds b set seq = n.seq
    from (
      select x.id, coalesce((select max(y.seq) from public.builds y where y.counter_id = x.counter_id), 0)
                   + row_number() over (partition by x.counter_id order by x.created_at, x.id) as seq
        from public.builds x where x.seq is null and x.status in ('approved', 'hidden')
    ) n
   where b.id = n.id;

  -- 첫 빌드: 상대법을 만든 처음 제안과 함께 공개된 빌드, 없으면 가장 먼저 공개된 빌드
  update public.counters c
     set first_build_id = coalesce(
       (select b.id from public.builds b
         where b.counter_id = c.id and b.proposal_id = public.origin_proposal_id(c.id) order by b.id limit 1),
       (select b.id from public.builds b where b.counter_id = c.id and b.status in ('approved', 'hidden') order by b.seq, b.id limit 1))
   where c.first_build_id is null;

  -- 기록이 하나도 없는 공개(숨김 포함) 빌드 → 'migrate' 1줄 (전 = 없음, 후 = 지금 내용)
  for nb in
    select b.* from public.builds b
     where b.status in ('approved', 'hidden') and b.summary is not null
       and not exists (select 1 from public.build_revisions rv where rv.build_id = b.id)
     order by b.id
  loop
    insert into public.build_revisions (build_id, counter_id, editor_id, kind, before, after, version, created_at)
    values (nb.id, nb.counter_id, null, 'migrate', null, public.wiki_snapshot(nb), nb.version, nb.updated_at);
  end loop;

  -- 기여자: 승인된 문서 수정 제안을 낸 사람 (빌드 작성자 = 시초는 빼고)
  insert into public.build_editors (build_id, user_id, first_at, last_at, edits)
  select b.id, p.proposer_id, min(p.reviewed_at), max(p.reviewed_at), count(*)
    from public.builds b
    join public.edit_proposals p on p.counter_id = b.counter_id and p.type = 'doc_edit' and p.status = 'approved'
   where b.status in ('approved', 'hidden') and p.proposer_id is not null and p.proposer_id is distinct from b.author_id
     and p.reviewed_at is not null
   group by b.id, p.proposer_id
  on conflict (build_id, user_id) do nothing;

  return filled;
end;
$$;
comment on function public.wiki_backfill_matchups() is
  '038 데이터 이전: 문서 내용을 빌드로 복사·번호·첫 빌드·migrate 기록·기여자. 다시 불러도 같은 결과. 사람은 못 부름';

-- ---------------------------------------------------------------------
-- 6. 등록·수정 함수 (DB가 모두 검사 — 화면은 보이는 것만 맞춘다)
-- ---------------------------------------------------------------------
create function public.create_matchup(p_target text, p_mine text, p_build jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();  -- 로그인 + 닉네임 (비회원 가능)
  c jsonb := public.clean_wiki_build(p_build);
  st text;
  cid bigint;
  bid bigint;
begin
  if coalesce(p_target, '') !~ '^[A-Za-z]{1,30}$' or coalesce(p_mine, '') !~ '^[A-Za-z]{1,30}$' then
    raise exception '챔피언을 다시 골라 주세요.' using errcode = '23514';
  end if;
  if p_target = p_mine then
    raise exception '같은 챔피언끼리는 상대법을 만들 수 없습니다.' using errcode = '23514';
  end if;
  select status into st from public.counters where target_champion = p_target and counter_champion = p_mine;
  if st = 'approved' then
    raise exception '이미 있는 상대법입니다. 그 상대법에 새 빌드를 더해 주세요.' using errcode = '23505';
  elsif st is not null then
    raise exception '운영진이 숨긴 상대법이라 새로 등록할 수 없습니다.' using errcode = '23514';
  end if;
  perform public.wiki_throttle('create');

  begin
    insert into public.counters (target_champion, counter_champion, sort_order, status, proposed_by, wiki)
    values (p_target, p_mine,
            (select coalesce(max(sort_order), 0) + 1 from public.counters where target_champion = p_target),
            'approved', me, true)
    returning id into cid;
  exception when unique_violation then
    raise exception '이미 있는 상대법입니다. 그 상대법에 새 빌드를 더해 주세요.' using errcode = '23505';
  end;
  -- 옛 화면용 사본 (PWA에 남은 옛 상대법 화면·챔피언 목록이 내용을 보여 주게). 이후 빌드 수정은 반영하지 않는다
  insert into public.matchup_docs (counter_id, summary, level_notes, lane_cautions, updated_by)
  values (cid, c ->> 'summary', c -> 'level_notes', c ->> 'lane_cautions', me);
  bid := public.wiki_insert_build(cid, me, c);
  update public.counters set first_build_id = bid where id = cid;
  perform public.notify_admins_wiki('matchup_created', '새 상대법이 등록됐습니다.', cid, bid);
  return jsonb_build_object('counter_id', cid, 'build_id', bid);
end;
$$;

create function public.create_build(p_counter bigint, p_build jsonb)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  c jsonb := public.clean_wiki_build(p_build);
  bid bigint;
begin
  if not exists (select 1 from public.counters where id = p_counter and status = 'approved') then
    raise exception '빌드를 등록할 상대법을 찾지 못했습니다.' using errcode = '23514';
  end if;
  perform public.wiki_throttle('create');
  bid := public.wiki_insert_build(p_counter, me, c);
  perform public.notify_admins_wiki('build_created', '새 빌드가 등록됐습니다.', p_counter, bid);
  return bid;
end;
$$;

-- 돌려주는 값: 새 버전 (화면은 다음 수정 때 이 값을 보낸다)
create function public.edit_build(p_id bigint, p_version integer, p_build jsonb)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  b public.builds;
  nb public.builds;
  c jsonb;
  before jsonb;
  same_build boolean;
begin
  select * into b from public.builds where id = p_id for update;
  if not found then
    raise exception '빌드를 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if b.status <> 'approved' or not exists (select 1 from public.counters where id = b.counter_id and status = 'approved') then
    raise exception '공개된 빌드만 수정할 수 있습니다.' using errcode = '23514';
  end if;
  if b.author_id is distinct from me and public.is_guest(me) then
    raise exception '다른 분의 빌드는 구글·카카오로 로그인한 회원만 수정할 수 있습니다. 비회원은 새 빌드를 등록하거나 내 빌드를 수정할 수 있습니다.'
      using errcode = '42501';
  end if;
  if p_version is distinct from b.version then
    raise exception '다른 분이 먼저 수정했습니다. 최신 내용을 확인해 주세요.' using errcode = 'TL412';
  end if;
  c := public.clean_wiki_build(p_build);
  before := public.wiki_snapshot(b);
  if c - 'patch' = before - 'patch' then
    raise exception '바뀐 내용이 없습니다.' using errcode = '23514';
  end if;
  same_build := c - 'patch' - 'name' - 'summary' - 'level_notes' - 'lane_cautions' = public.build_signature(b);
  if not same_build and exists (
    select 1 from public.builds x
     where x.counter_id = b.counter_id and x.id <> b.id and x.status = 'approved'
       and public.build_signature(x) = c - 'patch' - 'name' - 'summary' - 'level_notes' - 'lane_cautions'
  ) then
    raise exception '똑같은 빌드가 이미 공개돼 있습니다. 그 빌드를 추천해 주세요.' using errcode = '23514';
  end if;
  perform public.wiki_throttle('edit');

  update public.builds
     set runes = c -> 'runes',
         summoner_spells = array(select jsonb_array_elements_text(c -> 'summoner_spells')),
         starting_items = array(select jsonb_array_elements_text(c -> 'starting_items')),
         core_items = array(select jsonb_array_elements_text(c -> 'core_items')),
         max_skill = c ->> 'max_skill',
         patch = case when same_build then b.patch else c ->> 'patch' end,  -- 글만 고치면 패치 그대로
         name = c ->> 'name', summary = c ->> 'summary', level_notes = c -> 'level_notes', lane_cautions = c ->> 'lane_cautions',
         version = b.version + 1, updated_at = now(), updated_by = me
   where id = b.id
   returning * into nb;  -- 핵심 템트리·강타·시작 골드는 바뀐 칸만 트리거가 검사
  insert into public.build_revisions (build_id, counter_id, editor_id, kind, before, after, version)
  values (b.id, b.counter_id, me, 'edit', before, public.wiki_snapshot(nb), nb.version);
  if me is distinct from b.author_id then
    insert into public.build_editors (build_id, user_id) values (b.id, me)
    on conflict (build_id, user_id) do update set last_at = now(), edits = public.build_editors.edits + 1;
  end if;
  return nb.version;  -- 수정마다 알림은 보내지 않는다. 경험치도 없다
end;
$$;

-- 기여자 목록: [{user_id, nickname, role, is_guest, level, main_title, is_origin}] — 시초가 맨 앞(탈퇴했으면 user_id·nickname null)
create function public.build_contributors(p_build bigint)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  b public.builds;
begin
  select * into b from public.builds where id = p_build;
  if not found or not (
    public.is_admin()
    or (b.status = 'approved' and exists (select 1 from public.counters where id = b.counter_id and status = 'approved'))
  ) then
    raise exception '빌드를 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  return (
    select jsonb_agg(x.o order by x.ord, x.at, x.uid)
      from (
        select 0 as ord, b.created_at as at, b.author_id::text as uid,
               jsonb_build_object('user_id', p.id, 'nickname', p.nickname, 'role', p.role, 'is_guest', coalesce(p.is_guest, false),
                                  'level', p.level, 'main_title', p.main_title, 'is_origin', true) as o
          from (select 1) one left join public.profiles p on p.id = b.author_id
        union all
        select 1, e.first_at, e.user_id::text,
               jsonb_build_object('user_id', p.id, 'nickname', p.nickname, 'role', p.role, 'is_guest', p.is_guest,
                                  'level', p.level, 'main_title', p.main_title, 'is_origin', false)
          from public.build_editors e join public.profiles p on p.id = e.user_id
         where e.build_id = b.id and e.user_id is distinct from b.author_id
      ) x
  );
end;
$$;

-- 보관 기간이 지난 수정 기록 삭제 (사람은 못 부르고 pg_cron만). 기여자 목록·시초는 남는다
create function public.purge_old_build_revisions()
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  n integer;
begin
  delete from public.build_revisions
   where created_at < now() - make_interval(days => coalesce(public.xp_rule('build_revision_keep_days'), 365));
  get diagnostics n = row_count;
  return n;
end;
$$;

-- ---------------------------------------------------------------------
-- 7. 승인 제도 스위치: 꺼지면 옛 화면의 승인 대기 등록을 거부 (지금은 켜짐 — 039가 끈다)
-- ---------------------------------------------------------------------
do $$
declare
  f oid;
  old_def text;
  new_def text;
begin
  select 'public.check_new_proposal'::regproc into f;
  old_def := pg_get_functiondef(f);
  new_def := replace(old_def,
$s$begin
  new.content := public.clean_doc_content(new.content);
$s$,
$s$begin
  if not public.approval_on() then  -- 038: 승인 제도가 꺼지면 제안을 받지 않는다 (옛 화면)
    raise exception '이제 승인 없이 바로 등록합니다. 화면을 새로고침해 주세요.' using errcode = '23514';
  end if;
  new.content := public.clean_doc_content(new.content);
$s$);
  if new_def = old_def then
    raise exception 'check_new_proposal에서 바꿀 부분을 찾지 못했습니다. (이미 038을 실행했거나 정의가 달라졌습니다)';
  end if;
  execute new_def;

  select 'public.check_new_build'::regproc into f;
  old_def := pg_get_functiondef(f);
  new_def := replace(old_def,
$s$  if new.status = 'pending' then
    select b.status into mine$s$,
$s$  if new.status = 'pending' then
    if not public.approval_on() then  -- 038: 승인 제도가 꺼지면 승인 대기 빌드를 받지 않는다 (옛 화면)
      raise exception '이제 승인 없이 바로 등록합니다. 화면을 새로고침해 주세요.' using errcode = '23514';
    end if;
    select b.status into mine$s$);
  if new_def = old_def then
    raise exception 'check_new_build에서 바꿀 부분을 찾지 못했습니다. (이미 038을 실행했거나 정의가 달라졌습니다)';
  end if;
  execute new_def;
end;
$$;

-- ---------------------------------------------------------------------
-- 8. 경험치·칭호
-- ---------------------------------------------------------------------
create or replace function public.xp_should_have(p_user uuid)
returns table(source_key text, kind text, ref_id text, amount integer, at timestamptz, target_champion text, counter_champion text)
language sql stable security definer set search_path = ''
as $$
  -- 새 카운터(예전 승인 제안): 승인 + 카운터 공개 중 (숨기면 0, 다시 공개·재승인하면 같은 키로 돌아온다)
  select 'proposal:' || p.id, 'new_counter', p.id::text, public.xp_rule('new_counter'), p.reviewed_at, p.target_champion, p.counter_champion
  from public.edit_proposals p join public.counters c on c.id = p.counter_id
  where p.proposer_id = p_user and p.type = 'new_counter' and p.status = 'approved' and c.status = 'approved'
  union all
  -- 문서 수정(예전 승인 제안): 승인 + 카운터가 있음 (숨김은 회수하지 않고 완전 삭제만)
  select 'proposal:' || p.id, 'doc_edit', p.id::text, public.xp_rule('doc_edit'), p.reviewed_at, p.target_champion, p.counter_champion
  from public.edit_proposals p join public.counters c on c.id = p.counter_id
  where p.proposer_id = p_user and p.type = 'doc_edit' and p.status = 'approved'
  union all
  -- 빌드(예전 승인): 공개 중, 새 카운터의 첫 빌드는 카운터 +100에 포함
  select 'build:' || b.id, 'build', b.id::text, public.xp_rule('build'), b.reviewed_at, c.target_champion, c.counter_champion
  from public.builds b join public.counters c on c.id = b.counter_id
  where b.author_id = p_user and b.status = 'approved' and b.proposal_id is null and not b.wiki
  union all
  -- 위키 등록(038): 새 상대법 +100(공개 중, 첫 빌드 포함) · 새 빌드 +30(공개 중, 첫 빌드 제외)
  --   그날(한국 시간) 먼저 등록한 순서대로 합계 create_daily_cap까지 — 하나가 숨겨지면 다음 것이 들어온다
  select w.source_key, w.kind, w.ref_id, w.amount, w.at, w.target_champion, w.counter_champion
  from (
    select k.*, sum(k.amount) over (
      partition by (k.at at time zone 'Asia/Seoul')::date order by k.at, k.source_key) as run
    from (
      select 'matchup:' || c.id as source_key, 'new_matchup' as kind, c.id::text as ref_id, public.xp_rule('new_counter') as amount,
             c.created_at as at, c.target_champion, c.counter_champion
      from public.counters c
      where c.proposed_by = p_user and c.wiki and c.status = 'approved'
      union all
      select 'build:' || b.id, 'build', b.id::text, public.xp_rule('build'), b.created_at, c.target_champion, c.counter_champion
      from public.builds b join public.counters c on c.id = b.counter_id
      where b.author_id = p_user and b.wiki and b.status = 'approved' and b.id is distinct from c.first_build_id
    ) k
  ) w
  where w.run <= coalesce(public.xp_rule('create_daily_cap'), 200)
  union all
  -- 추천: 처음 누른 추천만, 받은 사람 기준 하루(한국 시간) 상한 — 상한은 지워진 빌드의 추천까지 넣고 센다
  select 'vote:' || v.id, 'vote', v.build_id::text, public.xp_rule('vote'), v.created_at, c.target_champion, c.counter_champion
  from (
    select l.*, row_number() over (
      partition by (l.created_at at time zone 'Asia/Seoul')::date order by l.created_at, l.id) as rn
    from public.build_vote_log l
    where l.author_id = p_user and l.first_up
  ) v
  join public.builds b on b.id = v.build_id
  join public.counters c on c.id = b.counter_id
  where v.rn <= public.xp_rule('vote_daily_cap') / greatest(public.xp_rule('vote'), 1)
  union all
  -- 게시판 글: 보이는 글(숨김·삭제 아님)을 그날(한국 시간) 먼저 쓴 순서대로 상한까지
  select 'post:' || p.id, 'post', p.id::text, public.xp_rule('post'), p.created_at, null::text, null::text
  from (
    select p.id, p.created_at, row_number() over (
      partition by (p.created_at at time zone 'Asia/Seoul')::date order by p.created_at, p.id) as rn
    from public.posts p
    where p.author_id = p_user and p.status = 'visible' and p.deleted_at is null
  ) p
  where p.rn <= public.xp_rule('post_daily_cap') / greatest(public.xp_rule('post'), 1)
  union all
  -- 댓글: 게시판 댓글 + 문서 댓글을 합쳐 그날 먼저 쓴 순서대로 상한까지
  select x.source_key, x.kind, x.ref_id, public.xp_rule('comment'), x.created_at, x.target_champion, x.counter_champion
  from (
    select y.*, row_number() over (
      partition by (y.created_at at time zone 'Asia/Seoul')::date order by y.created_at, y.kind, y.id) as rn
    from (
      select 'comment:' || c.id as source_key, 'comment' as kind, c.id::text as ref_id, c.id, c.created_at,
             null::text as target_champion, null::text as counter_champion
      from public.post_comments c
      where c.author_id = p_user and c.status = 'visible'
      union all
      select 'doc_comment:' || d.id, 'doc_comment', d.counter_id || ':' || d.id, d.id, d.created_at, k.target_champion, k.counter_champion
      from public.doc_comments d join public.counters k on k.id = d.counter_id
      where d.author_id = p_user and d.status = 'visible'
    ) y
  ) x
  where x.rn <= public.xp_rule('comment_daily_cap') / greatest(public.xp_rule('comment'), 1);
$$;

-- 회수 이유: 새 상대법 (상대법 숨김 / 상대법 삭제)
do $$
declare
  f oid := 'public.xp_reason'::regproc;
  old_def text := pg_get_functiondef(f);
  new_def text;
begin
  new_def := replace(old_def,
$s$  elsif p_kind = 'build' then$s$,
$s$  elsif p_kind = 'new_matchup' then  -- 038
    select status into cst from public.counters where id = p_ref::bigint;
    if not found then return '상대법 삭제'; end if;
    if cst = 'hidden' then return '상대법 숨김'; end if;
    return '규칙 변경';
  elsif p_kind = 'build' then$s$);
  if new_def = old_def then
    raise exception 'xp_reason에서 바꿀 부분을 찾지 못했습니다.';
  end if;
  execute new_def;
end;
$$;

-- 칭호: 승인된 제안 + 내가 시초인 공개 상대법 + 공개 빌드(첫 빌드 제외)를 센다
do $$
declare
  f oid := 'public.sync_rewards'::regproc;
  old_def text := pg_get_functiondef(f);
  new_def text;
begin
  new_def := replace(old_def,
$s$    where b.author_id = p_user and b.status = 'approved' and b.proposal_id is null
  )
  select count(*) filter (where kind in ('new_counter', 'doc_edit')), count(*), count(*) filter (where offmeta)$s$,
$s$    where b.author_id = p_user and b.status = 'approved' and b.proposal_id is null and b.id is distinct from c.first_build_id
    union all
    -- 038: 위키로 등록한 상대법 (비주류 여부는 첫 빌드가 공개될 때 고정한 값)
    select 'new_matchup', coalesce(fb.offmeta, false)
    from public.counters c left join public.builds fb on fb.id = c.first_build_id
    where c.proposed_by = p_user and c.wiki and c.status = 'approved'
  )
  select count(*) filter (where kind in ('new_counter', 'doc_edit', 'new_matchup', 'build')), count(*), count(*) filter (where offmeta)$s$);
  if new_def = old_def then
    raise exception 'sync_rewards에서 바꿀 부분을 찾지 못했습니다.';
  end if;
  execute new_def;
end;
$$;

-- 상대법 상태가 바뀌면 상대법 시초도 다시 계산
create or replace function public.rewards_on_counter()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  u uuid;
begin
  for u in
    select proposer_id from public.edit_proposals where counter_id = new.id
    union select author_id from public.builds where counter_id = new.id
    union select new.proposed_by
  loop
    perform public.sync_rewards(u);
  end loop;
  return null;
end;
$$;

-- ---------------------------------------------------------------------
-- 9. 알림 종류 · 운영자 모드 · 푸시
-- ---------------------------------------------------------------------
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind = any (array[
  'revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
  'build_hidden', 'build_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked', 'post_comment', 'post_hidden',
  'post_restored', 'comment_hidden', 'comment_restored', 'doc_comment', 'doc_comment_hidden', 'doc_comment_restored',
  'moderator_granted', 'moderator_revoked', 'inquiry_answered', 'proposal_submitted', 'build_submitted', 'inquiry_received',
  'counter_restored', 'matchup_created', 'build_created']));

-- 운영자 모드를 끄면 운영진 알림(새 상대법·새 빌드 포함)은 목록·빨간 점에서 빠진다 (034와 같은 방식)
drop policy "notifications: 본인 읽기" on public.notifications;
create policy "notifications: 본인 읽기" on public.notifications
  for select using (
    user_id = (select auth.uid())
    and not (kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created')
             and public.operator_mode_off())
  );

do $$
declare
  f oid := 'public.mark_all_notifications_read'::regproc;
  old_def text := pg_get_functiondef(f);
  new_def text;
begin
  new_def := replace(old_def,
    $s$kind in ('proposal_submitted', 'build_submitted', 'inquiry_received')$s$,
    $s$kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created')$s$);
  if new_def = old_def then
    raise exception 'mark_all_notifications_read에서 바꿀 부분을 찾지 못했습니다.';
  end if;
  execute new_def;
end;
$$;

create or replace function public.push_group(p_kind text)
returns text language sql immutable set search_path = ''
as $$
  select case
    when p_kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created') then 'staff_new'
    when p_kind in ('proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
                    'revision_request', 'counter_restored', 'build_restored') then 'my_results'
  end;
$$;

-- Edge Function이 누르면 갈 주소를 만들 수 있게 상대법 정보도 함께 (있던 칸은 그대로 — 옛 Edge Function도 동작)
do $$
declare
  f oid := 'public.push_targets'::regproc;
  old_def text := pg_get_functiondef(f);
  new_def text;
begin
  new_def := replace(old_def,
$s$'proposal_id', n.proposal_id, 'build_id', n.build_id),$s$,
$s$'proposal_id', n.proposal_id, 'build_id', n.build_id, 'counter_id', n.counter_id,
                                       'target_champion', (select k.target_champion from public.counters k where k.id = n.counter_id),
                                       'counter_champion', (select k.counter_champion from public.counters k where k.id = n.counter_id)),$s$);
  if new_def = old_def then
    raise exception 'push_targets에서 바꿀 부분을 찾지 못했습니다.';
  end if;
  execute new_def;
end;
$$;

-- ---------------------------------------------------------------------
-- 10. 권한
-- ---------------------------------------------------------------------
revoke execute on function public.approval_on() from public, anon;
grant execute on function public.approval_on() to authenticated;
revoke execute on function public.wiki_snapshot(public.builds) from public, anon, authenticated;
revoke execute on function public.clean_wiki_build(jsonb) from public, anon, authenticated;
revoke execute on function public.wiki_throttle(text) from public, anon, authenticated;
revoke execute on function public.notify_admins_wiki(text, text, bigint, bigint) from public, anon, authenticated;
revoke execute on function public.wiki_insert_build(bigint, uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.builds_wiki_fill() from public, anon, authenticated;
revoke execute on function public.matchup_docs_to_builds() from public, anon, authenticated;
revoke execute on function public.wiki_backfill_matchups() from public, anon, authenticated;
revoke execute on function public.purge_old_build_revisions() from public, anon, authenticated;
revoke execute on function public.create_matchup(text, text, jsonb) from public, anon;
revoke execute on function public.create_build(bigint, jsonb) from public, anon;
revoke execute on function public.edit_build(bigint, integer, jsonb) from public, anon;
grant execute on function public.create_matchup(text, text, jsonb) to authenticated;
grant execute on function public.create_build(bigint, jsonb) to authenticated;
grant execute on function public.edit_build(bigint, integer, jsonb) to authenticated;
revoke execute on function public.build_contributors(bigint) from public;
grant execute on function public.build_contributors(bigint) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 11. 기존 데이터 이전 (말파이트 상대법 등)
-- ---------------------------------------------------------------------
select public.wiki_backfill_matchups();

commit;

-- ---------------------------------------------------------------------
-- pg_cron 일정 등록 (위를 실행한 뒤 따로 한 번): 수정 기록 1년 정리, 매일 한국 시간 새벽 4시 55분 (UTC 19시 55분)
--   (다른 일정: 알림 4:00 · 문의 4:10 · 처리 기록 4:20 · 비회원 정리 4:30 · 사진 정리 4:40 · (040) 지운 글 4:50)
-- select cron.schedule('purge-old-build-revisions', '55 19 * * *', $$select public.purge_old_build_revisions()$$);
-- ---------------------------------------------------------------------
