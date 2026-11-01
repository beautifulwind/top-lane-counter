-- =====================================================================
-- 롤 탑 카운터 위키 — 2단계: 테이블 + RLS + 초기 데이터 (SPEC 7장)
-- Supabase SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- (다시 실행하면 "already exists" 오류가 난다. 처음부터 다시 하려면
--  맨 아래 "초기화" 주석의 drop 문을 먼저 실행한다.)
-- 챔피언·아이템·룬·주문은 Data Dragon ID로만 참조한다 (DB에 복사하지 않음).
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 테이블
-- ---------------------------------------------------------------------

-- 유저 프로필 (auth.users 1:1). 프로필 자동 생성은 3단계(로그인)에서 추가.
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  nickname    text not null,
  role        text not null default 'user' check (role in ('user', 'admin')),
  xp          integer not null default 0 check (xp >= 0),
  level       integer not null default 1 check (level >= 1),
  main_title  text,  -- 대표 칭호 (user_titles에 있는 내 칭호만, 비워둘 수 있음 → 아래 FK)
  created_at  timestamptz not null default now(),
  -- 앞뒤 공백 없이 1~20자
  constraint profiles_nickname_format
    check (nickname = btrim(nickname) and char_length(nickname) between 1 and 20)
);
-- 닉네임 중복 금지 (대소문자만 다른 것도 같은 닉네임으로 본다: "Faker" = "faker")
create unique index profiles_nickname_unique on public.profiles (lower(nickname));

-- 유저가 받은 칭호 (명예 칭호, 권한 없음)
create table public.user_titles (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  title_key  text not null,
  earned_at  timestamptz not null default now(),
  primary key (user_id, title_key)
);

-- 대표 칭호는 "내가 실제로 가진 칭호" 중에서만 고를 수 있다.
-- (id, main_title) → user_titles(user_id, title_key). main_title이 null이면 검사하지 않음(= 비워둘 수 있음).
-- 칭호가 회수되면 대표 칭호는 자동으로 비워진다.
alter table public.profiles
  add constraint profiles_main_title_owned
  foreign key (id, main_title) references public.user_titles (user_id, title_key)
  on delete set null (main_title);

-- 카운터: target_champion(지는 쪽)을 counter_champion(이기는 쪽)이 이긴다
create table public.counters (
  id                bigint generated always as identity primary key,
  target_champion   text not null,
  counter_champion  text not null,
  sort_order        integer not null default 0,
  status            text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  proposed_by       uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now(),
  unique (target_champion, counter_champion),
  check (target_champion <> counter_champion)
);
create index counters_target_idx on public.counters (target_champion, sort_order);

-- 매치업 문서 (카운터 1개당 문서 1개)
create table public.matchup_docs (
  counter_id     bigint primary key references public.counters (id) on delete cascade,
  -- {"1": "...", "2": "...", ...} 필수 1/2/3/6/9/11 + 추가 레벨
  level_notes    jsonb not null default '{}'::jsonb
                 check (jsonb_typeof(level_notes) = 'object'
                        and level_notes ?& array['1', '2', '3', '6', '9', '11']),
  lane_cautions  text not null default '',
  summary        text not null default '',
  updated_by     uuid references public.profiles (id) on delete set null,
  updated_at     timestamptz not null default now()
);

-- 수정·승인 제안
create table public.edit_proposals (
  id                bigint generated always as identity primary key,
  type              text not null check (type in ('new_counter', 'doc_edit')),
  target_champion   text not null,
  counter_champion  text not null,
  counter_id        bigint references public.counters (id) on delete cascade,
  proposer_id       uuid not null references public.profiles (id) on delete cascade,
  content           jsonb not null,
  status            text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reject_reason     text,
  reviewed_by       uuid references public.profiles (id) on delete set null,
  reviewed_at       timestamptz,
  created_at        timestamptz not null default now(),
  check (type <> 'doc_edit' or counter_id is not null),
  check (status <> 'rejected' or coalesce(btrim(reject_reason), '') <> '')  -- 거절 사유 필수
);
create index edit_proposals_proposer_idx on public.edit_proposals (proposer_id, created_at desc);
create index edit_proposals_pending_idx on public.edit_proposals (created_at) where status = 'pending';

-- 승인된 문서 수정 기록 (되돌리기용)
create table public.doc_revisions (
  id           bigint generated always as identity primary key,
  counter_id   bigint not null references public.counters (id) on delete cascade,
  proposal_id  bigint references public.edit_proposals (id) on delete set null,
  content      jsonb not null,  -- 그 시점 문서 전체 {level_notes, lane_cautions, summary}
  edited_by    uuid references public.profiles (id) on delete set null,
  approved_by  uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now()
);
create index doc_revisions_counter_idx on public.doc_revisions (counter_id, created_at desc);

-- 빌드
create table public.builds (
  id               bigint generated always as identity primary key,
  counter_id       bigint not null references public.counters (id) on delete cascade,
  author_id        uuid references public.profiles (id) on delete set null,  -- null = 예시(초기) 빌드
  runes            jsonb not null,   -- {primaryPath, keystone, primary[], secondaryPath, secondary[], shards[]}
  summoner_spells  text[] not null check (cardinality(summoner_spells) = 2),
  starting_items   text[] not null default '{}',
  core_items       text[] not null default '{}',  -- 순서 있음
  skill_order      jsonb not null,   -- ["Q","E","W"]
  patch            text not null,
  up_count         integer not null default 0,  -- build_votes 트리거가 관리
  down_count       integer not null default 0,
  status           text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  reject_reason    text,
  reviewed_by      uuid references public.profiles (id) on delete set null,
  reviewed_at      timestamptz,
  created_at       timestamptz not null default now(),
  check (status <> 'rejected' or coalesce(btrim(reject_reason), '') <> '')
);
create index builds_counter_idx on public.builds (counter_id) where status = 'approved';

-- 빌드 따봉 / 따봉 반대 (1인 1표, 바꿀 수 있음)
create table public.build_votes (
  build_id    bigint not null references public.builds (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  value       smallint not null check (value in (1, -1)),
  created_at  timestamptz not null default now(),
  primary key (build_id, user_id)
);

-- 자유게시판
create table public.posts (
  id          bigint generated always as identity primary key,
  author_id   uuid not null references public.profiles (id) on delete cascade,
  title       text not null check (char_length(btrim(title)) between 1 and 100),
  body        text not null check (char_length(btrim(body)) >= 1),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index posts_created_idx on public.posts (created_at desc);

create table public.post_comments (
  id          bigint generated always as identity primary key,
  post_id     bigint not null references public.posts (id) on delete cascade,
  author_id   uuid not null references public.profiles (id) on delete cascade,
  body        text not null check (char_length(btrim(body)) >= 1),
  created_at  timestamptz not null default now()
);
create index post_comments_post_idx on public.post_comments (post_id, created_at);

-- 경험치 지급 기록 (하루 상한 계산·확인용)
create table public.xp_events (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  type        text not null,
  amount      integer not null,
  ref_id      text,
  created_at  timestamptz not null default now()
);
create index xp_events_user_idx on public.xp_events (user_id, type, created_at);

-- 관리자가 지정한 비주류 픽
create table public.offmeta_champions (
  champion_id  text primary key,
  added_by     uuid references public.profiles (id) on delete set null,
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 2. 함수·트리거
-- ---------------------------------------------------------------------

-- 지금 로그인한 사람이 관리자인가 (RLS 안에서 profiles를 다시 RLS로 읽지 않도록 security definer)
create function public.is_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles where id = (select auth.uid()) and role = 'admin'
  );
$$;

-- updated_at 자동 갱신
create function public.touch_updated_at()
returns trigger language plpgsql set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger matchup_docs_touch before update on public.matchup_docs
  for each row execute function public.touch_updated_at();
create trigger posts_touch before update on public.posts
  for each row execute function public.touch_updated_at();

-- 따봉 수를 builds.up_count / down_count에 반영 (클라이언트는 숫자를 직접 못 바꿈)
create function public.apply_build_vote()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    update public.builds
       set up_count   = up_count   - (old.value = 1)::int,
           down_count = down_count - (old.value = -1)::int
     where id = old.build_id;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    update public.builds
       set up_count   = up_count   + (new.value = 1)::int,
           down_count = down_count + (new.value = -1)::int
     where id = new.build_id;
  end if;
  return null;
end;
$$;
create trigger build_votes_count after insert or update or delete on public.build_votes
  for each row execute function public.apply_build_vote();

-- 트리거 전용 함수는 API로 직접 호출하지 못하게
revoke execute on function public.apply_build_vote() from public, anon, authenticated;
revoke execute on function public.touch_updated_at() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. 권한 (칸 단위) — Supabase 기본값(anon/authenticated 전부 허용)을 걷어내고 필요한 것만 연다.
--    RLS가 "어느 행", 아래 grant가 "어느 칸"을 막는다.
-- ---------------------------------------------------------------------
revoke all on
  public.profiles, public.user_titles, public.counters, public.matchup_docs,
  public.edit_proposals, public.doc_revisions, public.builds, public.build_votes,
  public.posts, public.post_comments, public.xp_events, public.offmeta_champions
from anon, authenticated;

-- 읽기
grant select on
  public.profiles, public.user_titles, public.counters, public.matchup_docs,
  public.builds, public.posts, public.post_comments, public.offmeta_champions
to anon, authenticated;
grant select on public.edit_proposals, public.doc_revisions, public.build_votes, public.xp_events
to authenticated;

-- profiles: 본인 닉네임·대표 칭호만 수정 가능. role/xp/level은 클라이언트에서 못 바꿈.
grant insert (id, nickname) on public.profiles to authenticated;
grant update (nickname, main_title) on public.profiles to authenticated;

-- 제안·빌드: 내용 칸만 넣을 수 있음 → status는 항상 기본값 'pending'
grant insert (type, target_champion, counter_champion, counter_id, proposer_id, content)
  on public.edit_proposals to authenticated;
grant insert (counter_id, author_id, runes, summoner_spells, starting_items, core_items, skill_order, patch)
  on public.builds to authenticated;

-- 투표
grant insert (build_id, user_id, value), update (value), delete on public.build_votes to authenticated;

-- 자유게시판
grant insert (author_id, title, body), update (title, body), delete on public.posts to authenticated;
grant insert (post_id, author_id, body), update (body), delete on public.post_comments to authenticated;

-- 관리자 작업(승인·순서 변경 등)용 쓰기 권한. 실제로 누가 쓸 수 있는지는 RLS의 is_admin()이 막는다.
grant insert, update, delete on public.counters, public.matchup_docs, public.doc_revisions,
  public.offmeta_champions, public.user_titles, public.xp_events to authenticated;
grant update (status, reject_reason, reviewed_by, reviewed_at) on public.edit_proposals to authenticated;
grant update (status, reject_reason, reviewed_by, reviewed_at) on public.builds to authenticated;
grant delete on public.builds, public.edit_proposals to authenticated;

-- ---------------------------------------------------------------------
-- 4. RLS
-- ---------------------------------------------------------------------
alter table public.profiles          enable row level security;
alter table public.user_titles       enable row level security;
alter table public.counters          enable row level security;
alter table public.matchup_docs      enable row level security;
alter table public.edit_proposals    enable row level security;
alter table public.doc_revisions     enable row level security;
alter table public.builds            enable row level security;
alter table public.build_votes       enable row level security;
alter table public.posts             enable row level security;
alter table public.post_comments     enable row level security;
alter table public.xp_events         enable row level security;
alter table public.offmeta_champions enable row level security;

-- profiles: 누구나 보기(닉네임·레벨·칭호 표시), 본인 행만 생성·수정
create policy "profiles: 누구나 읽기" on public.profiles
  for select using (true);
create policy "profiles: 본인 생성" on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
create policy "profiles: 본인 수정" on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- user_titles: 누구나 보기, 지급은 관리자 또는 DB 함수만
create policy "user_titles: 누구나 읽기" on public.user_titles
  for select using (true);
create policy "user_titles: 관리자 쓰기" on public.user_titles
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- counters: 승인된 것만 공개, 관리자는 전부
create policy "counters: 승인된 것 읽기" on public.counters
  for select using (status = 'approved' or public.is_admin());
create policy "counters: 관리자 쓰기" on public.counters
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- matchup_docs: 승인된 카운터의 문서만 공개
create policy "matchup_docs: 승인된 카운터 문서 읽기" on public.matchup_docs
  for select using (
    public.is_admin()
    or exists (select 1 from public.counters c where c.id = counter_id and c.status = 'approved')
  );
create policy "matchup_docs: 관리자 쓰기" on public.matchup_docs
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- edit_proposals: 본인 제안만 보기·작성(대기 상태로만), 처리는 관리자
create policy "edit_proposals: 본인 또는 관리자 읽기" on public.edit_proposals
  for select to authenticated using (proposer_id = (select auth.uid()) or public.is_admin());
create policy "edit_proposals: 본인 이름으로 대기 제안 작성" on public.edit_proposals
  for insert to authenticated with check (
    proposer_id = (select auth.uid()) and status = 'pending'
    and reviewed_by is null and reviewed_at is null and reject_reason is null
  );
create policy "edit_proposals: 관리자 처리" on public.edit_proposals
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "edit_proposals: 관리자 삭제" on public.edit_proposals
  for delete to authenticated using (public.is_admin());

-- doc_revisions: 관리자만 (되돌리기용)
create policy "doc_revisions: 관리자" on public.doc_revisions
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- builds: 승인된 것은 누구나, 내 빌드는 대기·거절 상태도 보임
create policy "builds: 승인된 것 / 내 것 읽기" on public.builds
  for select using (
    (status = 'approved'
      and exists (select 1 from public.counters c where c.id = counter_id and c.status = 'approved'))
    or author_id = (select auth.uid())
    or public.is_admin()
  );
create policy "builds: 본인 이름으로 대기 빌드 등록" on public.builds
  for insert to authenticated with check (
    author_id = (select auth.uid()) and status = 'pending'
    and reviewed_by is null and reviewed_at is null and reject_reason is null
    and up_count = 0 and down_count = 0
  );
create policy "builds: 관리자 처리" on public.builds
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "builds: 관리자 삭제" on public.builds
  for delete to authenticated using (public.is_admin());

-- build_votes: 내 표만 보기·쓰기, 승인된 남의 빌드에만 투표 가능
create policy "build_votes: 내 표 읽기" on public.build_votes
  for select to authenticated using (user_id = (select auth.uid()) or public.is_admin());
create policy "build_votes: 투표" on public.build_votes
  for insert to authenticated with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.builds b
      where b.id = build_id and b.status = 'approved'
        and b.author_id is distinct from (select auth.uid())   -- 본인 빌드 투표 불가
    )
  );
create policy "build_votes: 표 바꾸기" on public.build_votes
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "build_votes: 표 취소" on public.build_votes
  for delete to authenticated using (user_id = (select auth.uid()));

-- posts / post_comments: 누구나 보기, 본인 것만 작성·수정·삭제 (관리자는 삭제 가능)
create policy "posts: 누구나 읽기" on public.posts
  for select using (true);
create policy "posts: 본인 작성" on public.posts
  for insert to authenticated with check (author_id = (select auth.uid()));
create policy "posts: 본인 수정" on public.posts
  for update to authenticated
  using (author_id = (select auth.uid())) with check (author_id = (select auth.uid()));
create policy "posts: 본인 또는 관리자 삭제" on public.posts
  for delete to authenticated using (author_id = (select auth.uid()) or public.is_admin());

create policy "post_comments: 누구나 읽기" on public.post_comments
  for select using (true);
create policy "post_comments: 본인 작성" on public.post_comments
  for insert to authenticated with check (author_id = (select auth.uid()));
create policy "post_comments: 본인 수정" on public.post_comments
  for update to authenticated
  using (author_id = (select auth.uid())) with check (author_id = (select auth.uid()));
create policy "post_comments: 본인 또는 관리자 삭제" on public.post_comments
  for delete to authenticated using (author_id = (select auth.uid()) or public.is_admin());

-- xp_events: 내 기록만 보기, 지급은 관리자 또는 DB 함수만
create policy "xp_events: 내 기록 읽기" on public.xp_events
  for select to authenticated using (user_id = (select auth.uid()) or public.is_admin());
create policy "xp_events: 관리자 쓰기" on public.xp_events
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- offmeta_champions: 누구나 보기, 관리자만 지정
create policy "offmeta_champions: 누구나 읽기" on public.offmeta_champions
  for select using (true);
create policy "offmeta_champions: 관리자 쓰기" on public.offmeta_champions
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------
-- 5. 초기 데이터: 다리우스 상대 퀸 하나만 (카운터 1 + 문서 1 + 빌드 2)
--    아직 유저가 없으므로 작성자(author_id)는 비워 둔다 → 화면에는 "예시 빌드"로 표시.
-- ---------------------------------------------------------------------
with c as (
  insert into public.counters (target_champion, counter_champion, sort_order, status)
  values ('Darius', 'Quinn', 1, 'approved')
  returning id
),
d as (
  insert into public.matchup_docs (counter_id, summary, level_notes, lane_cautions)
  select c.id,
    '사거리로 일방적인 견제, 다리우스 W·E만 피하면 라인전 압승',
    jsonb_build_object(
      '1',  '퀸 쪽이 사거리가 길다. 다리우스에게 붙지 말고 미니언 뒤에서 평타로만 견제한다.',
      '2',  '상대가 2레벨을 먼저 찍으면 바로 뒤로 빠진다. 웨이브를 먼저 밀어 2레벨 선점을 노린다.',
      '3',  '핵심 스킬 3개가 모두 생기는 구간. 상대 주요 스킬이 빠진 걸 보고 짧게 딜교한다.',
      '4',  '첫 귀환 전 체력을 깎아 두면 다리우스가 CS를 포기하게 된다.',
      '6',  '궁극기 유무가 가장 중요하다. 상대 궁 각이 보이면 체력을 반 이상 유지한다.',
      '9',  '주력 스킬 마스터. 짧은 교환을 여러 번 하는 쪽이 유리하다.',
      '11', '궁극기 2레벨. 사이드 운영으로 상대를 라인에 묶어둔다.'
    ),
    E'다리우스 E(포획) 사거리 안에서 오래 머무르지 않는다.\n출혈 5중첩 + 궁극기 각이 나오면 바로 빠진다.\n상대 정글이 탑에 오면 다리우스 혼자서도 킬각이 나오므로 와드 필수.'
  from c
  returning counter_id
)
insert into public.builds
  (counter_id, author_id, runes, summoner_spells, starting_items, core_items, skill_order, patch, status)
select c.id, null, b.runes, b.spells, b.starting, b.core, b.skills, b.patch, 'approved'
from c, (values
  ( '{"primaryPath":8000,"keystone":8005,"primary":[9111,9104,8014],"secondaryPath":8100,"secondary":[8143,8106],"shards":[5005,5008,5011]}'::jsonb,
    array['SummonerFlash','SummonerTeleport'], array['1055','2003'], array['6672','3006','3031','3036'],
    '["Q","E","W"]'::jsonb, '16.21.1' ),
  ( '{"primaryPath":8000,"keystone":8021,"primary":[9111,9104,8299],"secondaryPath":8400,"secondary":[8444,8451],"shards":[5005,5008,5011]}'::jsonb,
    array['SummonerFlash','SummonerDot'], array['1055','2003'], array['3153','3006','3124','3031'],
    '["Q","W","E"]'::jsonb, '14.1.1' )
) as b (runes, spells, starting, core, skills, patch);

commit;

-- =====================================================================
-- 초기화 (처음부터 다시 만들 때만, 위 내용보다 먼저 실행 — 모든 데이터가 지워짐)
-- drop table if exists public.offmeta_champions, public.xp_events, public.post_comments, public.posts,
--   public.build_votes, public.builds, public.doc_revisions, public.edit_proposals, public.matchup_docs,
--   public.counters, public.profiles, public.user_titles cascade;
-- drop function if exists public.is_admin(), public.touch_updated_at(), public.apply_build_vote();
-- =====================================================================
