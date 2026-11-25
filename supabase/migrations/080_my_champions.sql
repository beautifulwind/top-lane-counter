-- =====================================================================
-- 080: 내 챔피언 (2026-11-25, SPEC 6-116, 1.3 패치) - 새 표 2개 + 새 함수 3개(쓰기 1 · 읽기 2). 기존 함수·표·정책·권한·데이터는 바꾸지 않는다.
--
-- 무엇을: 사용자가 자기가 하는 챔피언을 최대 10개 등록하고, 그 챔피언들에 대해 여러 사람이 올린 공개 빌드를 한곳(/lists·/following 「내 챔피언」 탭)에서 모아 본다.
--
-- 1. 표 champion_catalog (champion_id text 기본 키, added_at) - 「있는 챔피언」 목록 (Data Dragon 16.23.1의 챔피언 id 173개를 넣는다).
--    지금까지 DB에는 챔피언 목록이 없고 상대법 등록도 영문 형식(^[A-Za-z]{1,30}$)만 본다. 「없는 챔피언 거절」을 위해 새로 둔다.
--    새 챔피언이 나오면 운영자가 SQL Editor에서 insert into public.champion_catalog (champion_id) values ('새id'); 한 줄로 더한다.
--    (그 전이라도 이미 공개 상대법의 「내 챔피언」 쪽(counter_champion)에 쓰인 id는 받아 준다.)
--    RLS 켬, 정책 없음, anon·authenticated 권한 없음 - 아래 함수(security definer)만 읽는다.
-- 2. 표 user_champions (user_id, champion, created_at) - 사용자별 등록 챔피언. 기본 키 (user_id, champion) = 같은 챔피언 두 번 등록 불가.
--    user_id → profiles(id) on delete cascade: 회원 탈퇴·비회원 정리(둘 다 auth.users 삭제 → profiles 삭제)에서 함께 지워진다
--    (기존 탈퇴 함수 withdraw_account_unchecked·cleanup_guest_accounts 본문은 고치지 않는다).
--    RLS 켬: 본인 줄만 읽기(select 정책 하나). 넣기·지우기는 set_my_champion으로만(표에 직접 쓰는 권한 없음). anon은 아무 권한 없음.
--    다른 사람의 등록 챔피언을 돌려주는 함수·화면은 없다(운영자 포함).
-- 3. 쓰기 함수 set_my_champion(p_champion text, p_selected boolean) → { champion, selected, count, limit }
--    - 첫 줄 assert_can_write()(활동 제한 중이면 TL423으로 거부 - 등록·해제 모두). 비로그인 거부, 비회원(게스트)·닉네임 없음은 허용.
--    - p_selected = true: 등록. 이미 등록했으면 그대로 성공(순서·시각도 그대로). 없는 챔피언은 22023 「없는 챔피언입니다」로 거부.
--      10개를 이미 등록했으면 errcode TL413 「최대 10개까지 선택할 수 있습니다. 하나를 해제한 뒤 선택해 주세요.」로 거부(화면이 구분해 안내).
--    - p_selected = false: 해제. 등록하지 않은 챔피언이어도 그대로 성공. (목록에서 빠진 챔피언도 해제할 수 있게 형식만 본다)
--    - 같은 사람이 동시에 여러 번 눌러도 10개를 넘지 않게 그 사람 profiles 줄을 잠근다(066 save_build와 같은 방식).
-- 4. 읽기 함수 my_champions() → { limit: 10, items: ["Ahri", ...] } - 내 등록 챔피언, 최근 등록순. 로그인만(비회원 가능).
-- 5. 읽기 함수 my_champion_builds(p_champion text default null, p_page integer default 1)
--      → { total, page, size(20), blocked, items: [{ id, name, seq, max_skill, up, created_at, author_id, author, target, mine }] }
--    - 내 등록 챔피언이 「내 챔피언」(counter_champion)인 공개 빌드(빌드 approved + 상대법 approved = 전체 빌드 목록 /builds와 같은 기준).
--      숨김·대기·거절 빌드, 숨긴 상대법의 빌드는 나오지 않는다. p_champion을 주면 그 챔피언 하나로 좁힌다(내가 등록한 챔피언이 아니면 빈 목록).
--    - 정렬은 /builds 추천순(compareAllBuilds)과 같다: 장인 빌드 먼저 → 추천(up_count) 많은 순 → 최신(created_at) → id 큰 순. 20개씩 쪽.
--    - 내가 차단한 사람(user_blocks)의 빌드는 서버에서 빼고(쪽마다 20개가 고르게), 뺀 개수를 blocked로 알려 준다(board_page와 같은 방식).
--    - author = { influencer, nickname, photo_path } (전체 빌드 목록과 같은 칸) / 탈퇴한 작성자는 null(화면이 「탈퇴한 이용자」).
--      이메일·역할·레벨·운영 정보·별점은 돌려주지 않는다. 별점은 화면이 기존처럼 build_difficulties로 붙인다(071 전 DB에서도 동작).
--    - 로그인만(비회원 가능). 언제나 부른 사람 본인의 등록분만 쓴다(다른 사람 id를 받는 인자가 없다).
--
-- 함수 수: 쓰기 함수 103 / 첫 줄 검사 30 / 허용 목록 73 → 104 / 31 / 73 (set_my_champion은 검사 쪽, 허용 목록은 건드리지 않음).
--          읽기 함수 67 → 69 (my_champions · my_champion_builds).
-- 옛 앱 1.1·1.2: 새 표·함수만 더하므로 달라지는 것 없음(이 기능이 보이지 않을 뿐). 새 알림 종류·설정값·pg_cron·Edge Function 변경 없음.
--
-- 실행 전 supabase/scripts/check_my_champions_before.sql, 실행 뒤 check_my_champions_after.sql.
-- 079까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다(두 번째는 맨 앞 확인에서 멈춘다).
-- 웹은 먼저 배포해도 된다: 함수가 없으면 「내 챔피언」 탭이 「준비 중」 안내만 보인다.
--
-- >> 되돌리기 (rollback) - SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 079 상태로 돌아간다.
--    변경 전 상태: 이 두 표와 세 함수가 없었다. 080은 기존 함수·표·정책·권한·데이터를 하나도 고치지 않았으므로 "변경 전 본문"이 없다.
--    되돌리면 사용자들이 등록한 챔피언(user_champions)이 함께 지워진다(되살릴 수 없음).
--    되돌린 뒤 check_my_champions_before.sql 1번이 「없음 · 없음 · 없음 · 없음 · 없음」이면 정상. 새 웹은 「준비 중」 안내로 돌아간다.
--     begin;
--     drop function public.my_champion_builds(text, integer);
--     drop function public.my_champions();
--     drop function public.set_my_champion(text, boolean);
--     drop table public.user_champions;
--     drop table public.champion_catalog;
--     commit;
-- =====================================================================
begin;

do $chk$
begin
  if to_regclass('public.user_champions') is not null or to_regclass('public.champion_catalog') is not null
     or to_regprocedure('public.set_my_champion(text, boolean)') is not null then
    raise exception '내 챔피언 표·함수가 이미 있습니다(080을 이미 실행함). 실행을 멈춥니다.';
  end if;
  if to_regprocedure('public.assert_can_write()') is null or to_regclass('public.user_blocks') is null then
    raise exception '061·068이 아직 실행되지 않았습니다.';
  end if;
end $chk$;

-- ---------------------------------------------------------------------
-- 1. 있는 챔피언 목록
-- ---------------------------------------------------------------------
create table public.champion_catalog (
  champion_id text primary key check (champion_id ~ '^[A-Za-z]{1,30}$'),
  added_at    timestamptz not null default now()
);
comment on table public.champion_catalog is
  '080 있는 챔피언 id 목록 (Data Dragon 영문 id). 내 챔피언 등록 때 없는 챔피언을 거른다. 새 챔피언은 운영자가 SQL로 한 줄 더함. 함수만 읽음';
alter table public.champion_catalog enable row level security;
revoke all on public.champion_catalog from public, anon, authenticated;

insert into public.champion_catalog (champion_id) values
  ('Aatrox'), ('Ahri'), ('Akali'), ('Akshan'), ('Alistar'), ('Ambessa'), ('Amumu'), ('Anivia'), ('Annie'), ('Aphelios'), ('Ashe'),
  ('AurelionSol'), ('Aurora'), ('Azir'), ('Bard'), ('Belveth'), ('Blitzcrank'), ('Brand'), ('Braum'), ('Briar'), ('Caitlyn'), ('Camille'),
  ('Cassiopeia'), ('Chogath'), ('Corki'), ('Darius'), ('Diana'), ('DrMundo'), ('Draven'), ('Ekko'), ('Elise'), ('Evelynn'), ('Ezreal'),
  ('Fiddlesticks'), ('Fiora'), ('Fizz'), ('Galio'), ('Gangplank'), ('Garen'), ('Gnar'), ('Gragas'), ('Graves'), ('Gwen'), ('Hecarim'),
  ('Heimerdinger'), ('Hwei'), ('Illaoi'), ('Irelia'), ('Ivern'), ('Janna'), ('JarvanIV'), ('Jax'), ('Jayce'), ('Jhin'), ('Jinx'),
  ('KSante'), ('Kaisa'), ('Kalista'), ('Karma'), ('Karthus'), ('Kassadin'), ('Katarina'), ('Kayle'), ('Kayn'), ('Kennen'), ('Khazix'),
  ('Kindred'), ('Kled'), ('KogMaw'), ('Leblanc'), ('LeeSin'), ('Leona'), ('Lillia'), ('Lissandra'), ('Locke'), ('Lucian'), ('Lulu'),
  ('Lux'), ('Malphite'), ('Malzahar'), ('Maokai'), ('MasterYi'), ('Mel'), ('Milio'), ('MissFortune'), ('MonkeyKing'), ('Mordekaiser'),
  ('Morgana'), ('Naafiri'), ('Nami'), ('Nasus'), ('Nautilus'), ('Neeko'), ('Nidalee'), ('Nilah'), ('Nocturne'), ('Nunu'), ('Olaf'),
  ('Orianna'), ('Ornn'), ('Pantheon'), ('Poppy'), ('Pyke'), ('Qiyana'), ('Quinn'), ('Rakan'), ('Rammus'), ('RekSai'), ('Rell'), ('Renata'),
  ('Renekton'), ('Rengar'), ('Riven'), ('Rumble'), ('Ryze'), ('Samira'), ('Sejuani'), ('Senna'), ('Seraphine'), ('Sett'), ('Shaco'),
  ('Shen'), ('Shyvana'), ('Singed'), ('Sion'), ('Sivir'), ('Skarner'), ('Smolder'), ('Sona'), ('Soraka'), ('Swain'), ('Sylas'), ('Syndra'),
  ('TahmKench'), ('Taliyah'), ('Talon'), ('Taric'), ('Teemo'), ('Thresh'), ('Tristana'), ('Trundle'), ('Tryndamere'), ('TwistedFate'),
  ('Twitch'), ('Udyr'), ('Urgot'), ('Varus'), ('Vayne'), ('Veigar'), ('Velkoz'), ('Vex'), ('Vi'), ('Viego'), ('Viktor'), ('Vladimir'),
  ('Volibear'), ('Warwick'), ('Xayah'), ('Xerath'), ('XinZhao'), ('Yasuo'), ('Yone'), ('Yorick'), ('Yunara'), ('Yuumi'), ('Zaahen'),
  ('Zac'), ('Zed'), ('Zeri'), ('Ziggs'), ('Zilean'), ('Zoe'), ('Zyra');

-- ---------------------------------------------------------------------
-- 2. 사용자별 등록 챔피언
-- ---------------------------------------------------------------------
create table public.user_champions (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  champion   text not null check (champion ~ '^[A-Za-z]{1,30}$'),
  created_at timestamptz not null default clock_timestamp(),  -- 한 트랜잭션에서 여러 개를 넣어도 등록 순서가 남게
  primary key (user_id, champion)
);
comment on table public.user_champions is
  '080 내 챔피언 (사용자별 최대 10개): 본인만 읽음, 넣기·지우기는 set_my_champion으로만. 다른 사람에게 보여 주는 경로 없음. 탈퇴·비회원 정리 때 함께 지워짐';
create index user_champions_user_recent_idx on public.user_champions (user_id, created_at desc);

alter table public.user_champions enable row level security;
create policy "user_champions: 본인 읽기" on public.user_champions
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.user_champions from public, anon, authenticated;
grant select on public.user_champions to authenticated;

-- ---------------------------------------------------------------------
-- 3. 쓰기: 등록·해제
-- ---------------------------------------------------------------------
create function public.set_my_champion(p_champion text, p_selected boolean)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  _can_write constant boolean := public.assert_can_write();
  me uuid := (select auth.uid());
  lim constant integer := 10;
  n integer;
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  if p_selected is null then
    raise exception '선택할지 해제할지 알려 주세요.' using errcode = '22023';
  end if;
  if coalesce(p_champion, '') !~ '^[A-Za-z]{1,30}$' then
    raise exception '없는 챔피언입니다. 다시 골라 주세요.' using errcode = '22023';
  end if;
  -- 같은 사람이 동시에 여러 번 눌러도 10개를 넘지 않게 그 사람 줄을 잠근다
  perform 1 from public.profiles where id = me for update;
  if not p_selected then
    delete from public.user_champions where user_id = me and champion = p_champion;
  elsif not exists (select 1 from public.user_champions where user_id = me and champion = p_champion) then
    if not exists (select 1 from public.champion_catalog where champion_id = p_champion)
       and not exists (select 1 from public.counters where counter_champion = p_champion and status = 'approved') then
      raise exception '없는 챔피언입니다. 다시 골라 주세요.' using errcode = '22023';
    end if;
    select count(*) into n from public.user_champions where user_id = me;
    if n >= lim then
      raise exception '최대 10개까지 선택할 수 있습니다. 하나를 해제한 뒤 선택해 주세요.' using errcode = 'TL413';
    end if;
    insert into public.user_champions (user_id, champion) values (me, p_champion);
  end if;
  select count(*) into n from public.user_champions where user_id = me;
  return jsonb_build_object('champion', p_champion, 'selected', p_selected, 'count', n, 'limit', lim);
end;
$$;
comment on function public.set_my_champion(text, boolean) is
  '내 챔피언 등록·해제 (080): 최대 10개(넘으면 TL413), 없는 챔피언 거부(22023), 중복 등록·없는 것 해제는 그대로 성공. 로그인(비회원 가능), 활동 제한 검사';

-- ---------------------------------------------------------------------
-- 4. 읽기: 내 등록 챔피언
-- ---------------------------------------------------------------------
create function public.my_champions()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'limit', 10,
    'items', coalesce((select jsonb_agg(u.champion order by u.created_at desc, u.champion)
                         from public.user_champions u where u.user_id = me), '[]'::jsonb));
end;
$$;
comment on function public.my_champions() is
  '내 챔피언 목록 (080): { limit, items: [챔피언 id] } 최근 등록순. 본인 것만. 로그인(비회원 가능)';

-- ---------------------------------------------------------------------
-- 5. 읽기: 내 챔피언들의 공개 빌드
-- ---------------------------------------------------------------------
create function public.my_champion_builds(p_champion text default null, p_page integer default 1)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz constant integer := 20;
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  return (
    with mine as (
      select u.champion from public.user_champions u
       where u.user_id = me and (p_champion is null or u.champion = p_champion)
    ), pub as (
      select b.id, b.name, b.seq, b.max_skill, b.up_count, b.created_at, b.author_id,
             c.target_champion, c.counter_champion, a.id as a_id, a.influencer, a.nickname, a.photo_path,
             exists (select 1 from public.user_blocks k where k.blocker_id = me and k.blocked_id = b.author_id) as is_blocked
        from public.builds b
        join public.counters c on c.id = b.counter_id
        left join public.profiles a on a.id = b.author_id
       where b.status = 'approved' and c.status = 'approved'
         and c.counter_champion in (select champion from mine)
    ), shown as (
      select * from pub where not is_blocked
    ), pagex as (
      select * from shown
       order by (influencer is not null) desc, up_count desc, created_at desc, id desc
       limit sz offset (pg - 1) * sz
    )
    select jsonb_build_object(
      'total', (select count(*) from shown),
      'blocked', (select count(*) from pub where is_blocked),
      'page', pg, 'size', sz,
      'items', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', x.id, 'name', x.name, 'seq', x.seq, 'max_skill', x.max_skill, 'up', x.up_count, 'created_at', x.created_at,
                 'author_id', x.author_id,
                 'author', case when x.a_id is null then null
                                else jsonb_build_object('influencer', x.influencer, 'nickname', x.nickname, 'photo_path', x.photo_path) end,
                 'target', x.target_champion, 'mine', x.counter_champion)
               order by (x.influencer is not null) desc, x.up_count desc, x.created_at desc, x.id desc)
          from pagex x
      ), '[]'::jsonb))
  );
end;
$$;
comment on function public.my_champion_builds(text, integer) is
  '내 챔피언의 공개 빌드 (080): 내 등록 챔피언이 내 챔피언 쪽인 공개 빌드, /builds 추천순(장인 → 추천 → 최신), 20개씩, 차단한 사람 제외(blocked 개수). 로그인(비회원 가능)';

revoke execute on function public.set_my_champion(text, boolean) from public, anon;
revoke execute on function public.my_champions() from public, anon;
revoke execute on function public.my_champion_builds(text, integer) from public, anon;
grant execute on function public.set_my_champion(text, boolean) to authenticated;
grant execute on function public.my_champions() to authenticated;
grant execute on function public.my_champion_builds(text, integer) to authenticated;

commit;
