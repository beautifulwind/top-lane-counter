-- =====================================================================
-- 053: 칭호 도감 - 1단계 DB (2026-11-13, SPEC 6-39)
--
-- 1. 새 표 title_catalog (칭호 도감): 칭호마다 이름, 소개, 얻는 방법, 종류, 장착 가능 여부, 기간, 비밀, 숨김, 순서, 그림, 색.
--    - 종류(kind): activity(활동 칭호 6개 - 지금처럼 sync_rewards가 조건으로 주고 회수) /
--                  influencer(장인 - profiles.influencer로 표시만, user_titles에 넣지 않음) /
--                  limited(한정판 - 운영자가 grant_title/revoke_title로 직접 지급/회수).
--    - 장착(대표 칭호): activity만. 한정판/장인은 고를 수 없다(표의 check + profiles 트리거).
--    - 처음에는 활동 6개 + 장인 1개만 넣는다. 한정판은 0개(나중에 INSERT로 추가, 아래 "한정판 추가 예").
--    - RLS 켬, 정책 없음, anon/authenticated 권한 회수 = 직접 읽기/쓰기 불가. 화면은 my_title_book()으로만 읽는다.
--    - 설정 데이터라 테스트 데이터 비우기(reset_test_data)에서 지우지 않는다.
-- 2. user_titles.title_key -> title_catalog(key) 외래 키 (없는 칭호 키는 들어갈 수 없다).
--    user_titles에는 activity/limited만 들어간다(장인 칭호 줄은 트리거가 막는다).
-- 3. sync_rewards: 회수 대상을 kind = 'activity'인 칭호로만 좁힌다. 지금 DB에 있는 본문에서 회수 반복문 한 줄만 바꾼다(038과 같은 방식).
--    활동 칭호의 지급/회수 조건, 알림 문장은 그대로. 한정판 칭호는 sync_rewards가 건드리지 않는다.
-- 4. title_name(): 도감 표에서 이름을 읽는다(표에 없으면 키 그대로 - 예전과 같음). 알림 문장용. immutable -> stable.
-- 5. my_title_book(): 로그인한 회원의 칭호 도감(아래 "돌려주는 값"). 비밀 칭호를 아직 못 얻었으면 이름/소개/얻는 방법/그림이 null.
-- 6. grant_title / revoke_title: 운영자(운영자 모드 켬)만. 한정판만. 메모 필수(500자 이하). 알림 title_earned/title_revoked +
--    처리 기록(moderation_log) grant_title/revoke_title. 이미 받은 칭호는 기간이 끝나도 유지 - 회수는 운영자만(부정 취득 때).
--
-- 새 알림 종류 없음(title_earned/title_revoked 그대로, 푸시 없음). 새 설정값 없음. 처리 기록 종류 2개(grant_title, revoke_title).
-- pg_cron 없음. Edge Function 재배포 없음.
-- 실행 전 supabase/scripts/check_title_catalog_before.sql, 실행 뒤 check_title_catalog_after.sql.
--
-- >> 한정판 추가 예 (나중에 SQL Editor에서. 그림 파일은 먼저 public/titles/ 에 넣고 배포):
--     insert into public.title_catalog (key, name, description, how_to, kind, equippable, starts_at, ends_at, secret, hidden, sort_order, icon, color)
--     values ('limited_example', '예시', '짧은 소개', '얻는 방법 문장', 'limited', false,
--             '2026-12-01 00:00+09', '2026-12-31 23:59+09', false, false, 1010, 'limited_example.webp', '#C0392B');
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다. 053이 만든 것만 지우고 052 상태로 돌아간다.
--    (운영자가 준 한정판 칭호와 그 처리 기록도 지워진다. 활동 칭호, 대표 칭호, 알림은 그대로.)
--     begin;
--     do $r$
--     declare
--       old_def text := pg_get_functiondef('public.sync_rewards'::regproc);
--       new_def text;
--     begin
--       new_def := replace(old_def,
--         $s$  for t in select ut.title_key from public.user_titles ut join public.title_catalog c on c.key = ut.title_key where ut.user_id = p_user and c.kind = 'activity' and not (ut.title_key = any (want)) loop  -- 053: 활동 칭호만 회수$s$,
--         $s$  for t in select title_key from public.user_titles where user_id = p_user and not (title_key = any (want)) loop$s$);
--       if new_def = old_def then
--         raise exception 'sync_rewards에서 되돌릴 부분을 찾지 못했습니다.';
--       end if;
--       execute new_def;
--     end $r$;
--     drop trigger if exists profiles_main_title_equippable on public.profiles;
--     drop function if exists public.check_main_title_equippable();
--     drop trigger if exists user_titles_kind_guard on public.user_titles;
--     drop function if exists public.check_user_title_kind();
--     drop function if exists public.my_title_book();
--     drop function if exists public.grant_title(uuid, text, text);
--     drop function if exists public.revoke_title(uuid, text, text);
--     create or replace function public.title_name(p_key text)
--     returns text language sql immutable set search_path = ''
--     as $f$
--       select case p_key
--         when 'top_addict' then '탑신병자'
--         when 'tool_hater' then '도구혐오자'
--         when 'solid_heavy' then '단단묵직'
--         when 'butcher_owner' then '백정주인'
--         when 'general' then '장군'
--         when 'offmeta' then '비주류'
--         else p_key
--       end;
--     $f$;
--     comment on function public.title_name(text) is null;
--     delete from public.moderation_log where action in ('grant_title', 'revoke_title');
--     alter table public.moderation_log drop constraint moderation_log_action_check;
--     alter table public.moderation_log add constraint moderation_log_action_check check (action = any (array[
--       'hide', 'restore', 'dismiss_reports', 'approve_proposal', 'reject_proposal', 'grant_moderator', 'revoke_moderator',
--       'answer_inquiry', 'move_inquiry', 'edit_proposal', 'request_revision', 'delete', 'revert', 'resolve_report', 'dismiss_report',
--       'approve_influencer', 'reject_influencer', 'extend_influencer', 'revoke_influencer', 'rename_member',
--       'remove_link', 'add_link_domain', 'remove_link_domain',
--       'grant_influencer']));
--     delete from public.user_titles
--      where title_key not in ('top_addict', 'tool_hater', 'solid_heavy', 'butcher_owner', 'general', 'offmeta');
--     alter table public.user_titles drop constraint if exists user_titles_title_key_fkey;
--     drop table if exists public.title_catalog;
--     commit;
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.new_follower_counted') is null then
    raise exception '052가 아직 실행되지 않았습니다. 052를 먼저 실행해 주세요.';
  end if;
  if to_regclass('public.title_catalog') is not null then
    raise exception '053을 이미 실행했습니다.';
  end if;
  -- 014가 모르는 칭호 키를 지웠으므로 0이어야 한다. 있으면 외래 키를 걸 수 없으니 멈춘다(아무것도 바뀌지 않음).
  if exists (select 1 from public.user_titles
              where title_key not in ('top_addict', 'tool_hater', 'solid_heavy', 'butcher_owner', 'general', 'offmeta')) then
    raise exception '알 수 없는 칭호 키가 user_titles에 있습니다. check_title_catalog_before.sql 6번 줄을 확인해 주세요.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. 칭호 도감 표
-- ---------------------------------------------------------------------
create table public.title_catalog (
  key         text primary key check (key ~ '^[a-z][a-z0-9_]{1,39}$'),
  name        text not null check (char_length(btrim(name)) between 1 and 20),
  description text check (description is null or char_length(description) <= 200),
  how_to      text not null check (char_length(btrim(how_to)) between 1 and 300),
  kind        text not null check (kind in ('activity', 'influencer', 'limited')),
  equippable  boolean not null default false,
  starts_at   timestamptz,
  ends_at     timestamptz,
  secret      boolean not null default false,
  hidden      boolean not null default false,
  sort_order  integer not null,
  icon        text check (icon is null or icon ~ '^[a-z0-9][a-z0-9_-]{0,59}\.(png|webp|svg)$'),
  color       text check (color is null or color ~ '^#[0-9A-Fa-f]{6}$'),
  created_at  timestamptz not null default now(),
  constraint title_catalog_equip_activity_only check (kind = 'activity' or not equippable),
  constraint title_catalog_period_limited_only check (kind = 'limited' or (starts_at is null and ends_at is null)),
  constraint title_catalog_period_order check (starts_at is null or ends_at is null or ends_at > starts_at)
);
comment on table public.title_catalog is
  '칭호 도감 (053). kind activity(조건으로 자동)/influencer(장인 표시만)/limited(운영자 지급). 직접 읽기/쓰기 불가 - my_title_book()으로만';
comment on column public.title_catalog.how_to is '얻는 방법. activity는 {n}이 xp_rules의 title_<key> 값으로 바뀐다';
comment on column public.title_catalog.icon is '그림 파일 이름(경로 없이). 사이트 public/titles/ 아래. null이면 공통 훈장에 color를 입힌다';
comment on column public.title_catalog.color is '칭호 색 #RRGGBB. null이면 화면의 기본 색(기존 6개는 CSS 색 그대로)';
comment on column public.title_catalog.sort_order is '같은 종류 안의 순서. 화면 순서는 활동 -> 장인 -> 한정판 고정, 그 안에서 이 값';
alter table public.title_catalog enable row level security;
revoke all on public.title_catalog from anon, authenticated;

insert into public.title_catalog (key, name, how_to, kind, equippable, sort_order) values
  ('top_addict',    '탑신병자',   E'처음으로 승인받은 기여 {n}개 또는 탑신병자 커뮤니티 글\u00B7댓글\u00B7문서 댓글 1개', 'activity', true, 10),
  ('tool_hater',    '도구혐오자', '상대법 관련 승인 {n}개',                 'activity', true, 20),
  ('solid_heavy',   '단단묵직',   '상대법 관련 승인 {n}개',                 'activity', true, 30),
  ('butcher_owner', '백정주인',   '상대법 관련 승인 {n}개',                 'activity', true, 40),
  ('general',       '장군',       '공개 중인 내 빌드들의 추천 합계 {n}',    'activity', true, 50),
  ('offmeta',       '비주류',     '비주류 픽 매치업 기여 승인 {n}개',       'activity', true, 60),
  ('influencer',    '장인',
   '장인 인증을 받으면 표시됩니다(대표 칭호로는 고를 수 없음). 크리에이터: 채널에 공개된 공식 이메일로 본인 확인 / '
   '프로게이머: 팀 공식 이메일로 본인 확인 / 그랜드마스터 이상: 라이엇 친구 요청과 op.gg 티어로 확인. '
   '[마이페이지] 맨 위 [장인 인증]에서 신청합니다.',
   'influencer', false, 100);

-- ---------------------------------------------------------------------
-- 2. user_titles -> title_catalog 외래 키, 장인 칭호 줄 막기
-- ---------------------------------------------------------------------
alter table public.user_titles
  add constraint user_titles_title_key_fkey foreign key (title_key) references public.title_catalog (key);

create function public.check_user_title_kind()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if exists (select 1 from public.title_catalog c where c.key = new.title_key and c.kind = 'influencer') then
    raise exception '장인 칭호는 장인 인증으로만 표시되고 따로 줄 수 없습니다.' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger user_titles_kind_guard before insert or update of title_key on public.user_titles
  for each row execute function public.check_user_title_kind();

-- 대표 칭호는 장착할 수 있는 칭호(activity)만. 가진 칭호인지는 예전처럼 profiles_main_title_owned 외래 키가 본다.
create function public.check_main_title_equippable()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.main_title is not null
     and not exists (select 1 from public.title_catalog c where c.key = new.main_title and c.equippable) then
    raise exception '이 칭호는 대표 칭호로 고를 수 없습니다.' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger profiles_main_title_equippable before insert or update of main_title on public.profiles
  for each row execute function public.check_main_title_equippable();

-- ---------------------------------------------------------------------
-- 3. sync_rewards: 회수는 활동 칭호만 (지금 본문에서 한 줄만 바꾼다. 정확히 한 번 나와야 바꾼다)
-- ---------------------------------------------------------------------
do $$
declare
  old_def text := pg_get_functiondef('public.sync_rewards'::regproc);
  target text := $s$  for t in select title_key from public.user_titles where user_id = p_user and not (title_key = any (want)) loop$s$;
  -- 바뀐 줄도 한 줄이다(되돌리기 SQL이 주석 앞 공백과 관계없이 같은 글자를 찾도록)
  repl text := $s$  for t in select ut.title_key from public.user_titles ut join public.title_catalog c on c.key = ut.title_key where ut.user_id = p_user and c.kind = 'activity' and not (ut.title_key = any (want)) loop  -- 053: 활동 칭호만 회수$s$;
  n integer;
begin
  n := (char_length(old_def) - char_length(replace(old_def, target, ''))) / char_length(target);
  if n <> 1 then
    raise exception 'sync_rewards에서 바꿀 줄이 %번 나왔습니다(1번이어야 함). 실행을 멈춥니다.', n;
  end if;
  execute replace(old_def, target, repl);
end $$;

-- ---------------------------------------------------------------------
-- 4. title_name(): 도감 표에서 이름 (알림 문장용, 클라이언트는 못 부름 - 014 권한 그대로)
-- ---------------------------------------------------------------------
create or replace function public.title_name(p_key text)
returns text language sql stable set search_path = ''
as $$
  select coalesce((select c.name from public.title_catalog c where c.key = p_key), p_key);
$$;
comment on function public.title_name(text) is '칭호 이름 (053부터 title_catalog에서 읽음, 없으면 키 그대로). 알림 문장용';

-- ---------------------------------------------------------------------
-- 5. my_title_book(): 로그인한 회원의 칭호 도감
--    돌려주는 값: { influencer, influencer_at, main_title,
--                   items: [{ key, kind, equippable, secret, name, description, how_to, icon, color,
--                             starts_at, ends_at, period(limited만: upcoming/open/ended, 그 밖은 null), owned, earned_at }] }
--    - 순서: 활동 -> 장인 -> 한정판, 그 안에서 sort_order, key.
--    - hidden인 칭호는 빠진다(가진 사람에게도).
--    - 비밀 칭호를 아직 못 얻었으면 name/description/how_to/icon이 null(화면은 "???"). 얻으면 모두 보인다.
--    - 장인: owned = 지금 장인 인증 상태, earned_at = 인증일. 운영자 계정은 칭호가 없어 owned가 모두 false.
-- ---------------------------------------------------------------------
create function public.my_title_book()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  me public.profiles;
begin
  select * into me from public.profiles where id = (select auth.uid());
  if not found then
    raise exception '로그인이 필요합니다.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'influencer', me.influencer,
    'influencer_at', me.influencer_at,
    'main_title', me.main_title,
    'items', coalesce((
      select jsonb_agg(x.item order by x.grp, x.sort_order, x.key)
      from (
        select c.key, c.sort_order,
               case c.kind when 'activity' then 1 when 'influencer' then 2 else 3 end as grp,
               jsonb_build_object(
                 'key', c.key, 'kind', c.kind, 'equippable', c.equippable, 'secret', c.secret,
                 'name', case when s.shown then c.name end,
                 'description', case when s.shown then c.description end,
                 'how_to', case when s.shown then
                             case when c.how_to like '%{n}%'
                                  then replace(c.how_to, '{n}', coalesce(public.xp_rule('title_' || c.key)::text, '?'))
                                  else c.how_to end
                           end,
                 'icon', case when s.shown then c.icon end,
                 'color', c.color,
                 'starts_at', c.starts_at, 'ends_at', c.ends_at,
                 'period', case
                             when c.kind <> 'limited' then null
                             when c.starts_at is not null and c.starts_at > now() then 'upcoming'
                             when c.ends_at is not null and c.ends_at <= now() then 'ended'
                             else 'open'
                           end,
                 'owned', o.owned, 'earned_at', o.earned_at
               ) as item
        from public.title_catalog c
        left join public.user_titles ut on ut.user_id = me.id and ut.title_key = c.key
        cross join lateral (
          select case when c.kind = 'influencer' then me.influencer is not null else ut.user_id is not null end as owned,
                 case when c.kind = 'influencer' then me.influencer_at else ut.earned_at end as earned_at
        ) o
        cross join lateral (select (not c.secret) or o.owned as shown) s
        where not c.hidden
      ) x
    ), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------
-- 6. 한정판 칭호 지급/회수 (운영자만) + 처리 기록
-- ---------------------------------------------------------------------
alter table public.moderation_log drop constraint moderation_log_action_check;
alter table public.moderation_log add constraint moderation_log_action_check check (action = any (array[
  'hide', 'restore', 'dismiss_reports', 'approve_proposal', 'reject_proposal', 'grant_moderator', 'revoke_moderator',
  'answer_inquiry', 'move_inquiry', 'edit_proposal', 'request_revision', 'delete', 'revert', 'resolve_report', 'dismiss_report',
  'approve_influencer', 'reject_influencer', 'extend_influencer', 'revoke_influencer', 'rename_member',
  'remove_link', 'add_link_domain', 'remove_link_domain',
  'grant_influencer',
  'grant_title', 'revoke_title'  -- 053
]));

create function public.grant_title(p_user uuid, p_key text, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  u public.profiles;
  c public.title_catalog;
  note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  perform public.require_operator();
  if note is null or char_length(note) > 500 then
    raise exception '지급 메모를 적어 주세요. (500자 이하)' using errcode = '22023';
  end if;
  select * into c from public.title_catalog where key = p_key;
  if not found then
    raise exception '칭호를 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if c.kind <> 'limited' then
    raise exception '한정판 칭호만 직접 줄 수 있습니다. (활동 칭호는 조건을 채우면 저절로 받고, 장인 칭호는 장인 인증으로 표시됩니다)'
      using errcode = '23514';
  end if;
  select * into u from public.profiles where id = p_user for update;
  if not found then
    raise exception '회원을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if u.role = 'admin' then
    raise exception '운영자 계정에는 칭호를 줄 수 없습니다.' using errcode = '23514';
  end if;
  if exists (select 1 from public.user_titles where user_id = u.id and title_key = c.key) then
    raise exception '이미 가진 칭호입니다.' using errcode = '23505';
  end if;
  insert into public.user_titles (user_id, title_key) values (u.id, c.key);
  perform public.notify(u.id, 'title_earned',
    format('칭호 ''%s''%s 얻었습니다. [마이페이지] 칭호 칸에서 볼 수 있습니다.', c.name, public.title_josa(c.name, '을', '를')),
    null, null);
  perform public.log_moderation('grant_title', 'user', u.id::text, format(E'%s \u00B7 %s', c.name, note), u.nickname);
end;
$$;

create function public.revoke_title(p_user uuid, p_key text, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  u public.profiles;
  c public.title_catalog;
  note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  perform public.require_operator();
  if note is null or char_length(note) > 500 then
    raise exception '회수 사유를 적어 주세요. (500자 이하)' using errcode = '22023';
  end if;
  select * into c from public.title_catalog where key = p_key;
  if not found then
    raise exception '칭호를 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if c.kind <> 'limited' then
    raise exception '한정판 칭호만 직접 회수할 수 있습니다. (활동 칭호는 조건이 깨지면 저절로 회수됩니다)' using errcode = '23514';
  end if;
  select * into u from public.profiles where id = p_user for update;
  if not found then
    raise exception '회원을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.user_titles where user_id = u.id and title_key = c.key) then
    raise exception '이 회원은 그 칭호를 가지고 있지 않습니다.' using errcode = 'P0002';
  end if;
  delete from public.user_titles where user_id = u.id and title_key = c.key;
  perform public.notify(u.id, 'title_revoked',
    format('칭호 ''%s''%s 회수됐습니다. 사유: %s', c.name, public.title_josa(c.name, '이', '가'), note),
    null, null);
  perform public.log_moderation('revoke_title', 'user', u.id::text, format(E'%s \u00B7 %s', c.name, note), u.nickname);
end;
$$;

-- ---------------------------------------------------------------------
-- 7. 권한
-- ---------------------------------------------------------------------
revoke execute on function public.check_user_title_kind() from public, anon, authenticated;
revoke execute on function public.check_main_title_equippable() from public, anon, authenticated;
revoke execute on function public.my_title_book() from public, anon;
revoke execute on function public.grant_title(uuid, text, text) from public, anon;
revoke execute on function public.revoke_title(uuid, text, text) from public, anon;
grant execute on function public.my_title_book() to authenticated;
grant execute on function public.grant_title(uuid, text, text) to authenticated;   -- 운영자인지는 함수 안에서
grant execute on function public.revoke_title(uuid, text, text) to authenticated;  -- 운영자인지는 함수 안에서
-- title_name은 014에서 회수한 권한 그대로(create or replace는 권한을 바꾸지 않는다)

commit;
