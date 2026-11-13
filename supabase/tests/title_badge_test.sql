-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 054: 한정판 대표 칭호 + 닉네임 옆 배지 (public_title_info, 장착 제약, 대표 칭호 트리거, 회수/장착 불가/숨김 때 대표 칭호 비우기, 되돌리기)
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set U   '00000000-0000-0000-0000-00000000000d'
\set V   '00000000-0000-0000-0000-00000000000c'
\set W   '00000000-0000-0000-0000-00000000000f'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'U', 'u@x.com'), (:'V', 'v@x.com'), (:'W', 'w@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = '보통' where id = :'V';
update public.profiles set nickname = '장인님', influencer = 'pro', influencer_at = '2026-11-01 00:00+00' where id = :'W';

create function pg_temp.info() returns jsonb language sql as $$ select public.public_title_info() $$;
create function pg_temp.info_keys() returns text[] language sql as $$
  select coalesce(array_agg(e ->> 'key' order by n), '{}') from jsonb_array_elements(public.public_title_info()) with ordinality a(e, n) $$;
create function pg_temp.main(u uuid) returns text language sql as $$ select main_title from public.profiles where id = u $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- ===== 0. 표 제약: 한정판은 장착 가능, 장인은 불가 =====
select t.ok('053 제약은 없어지고 054 제약이 있음',
  not exists (select 1 from pg_constraint where conname = 'title_catalog_equip_activity_only')
  and exists (select 1 from pg_constraint where conname = 'title_catalog_equip_kind'));
select t.fails('장인은 장착 가능으로 못 바꿈', $$update title_catalog set equippable = true where key = 'influencer'$$, 'title_catalog_equip_kind');
select t.ok('054는 칭호를 넣거나 equippable을 바꾸지 않음', (select count(*) = 7 from title_catalog)
  and (select count(*) = 6 from title_catalog where equippable));

-- 시험용 한정판 5개: 장착 가능(그림+색) / 장착 불가 / 비밀 + 장착 가능 / 숨김 + 장착 가능 / 색만 + 장착 가능
insert into title_catalog (key, name, description, how_to, kind, equippable, sort_order, secret, hidden, icon, color) values
  ('lim_cup',    '티확찢',   '공모전 우승', '공모전 1등',    'limited', true,  1010, false, false, 'lim_cup.webp', '#C0392B'),
  ('lim_plain',  '참가자',   null,          '공모전 참가',   'limited', false, 1020, false, false, null, null),
  ('lim_secret', '비밀이름', '비밀 소개',   '비밀 방법',     'limited', true,  1030, true,  false, null, '#112233'),
  ('lim_hidden', '숨김',     null,          '숨김 방법',     'limited', true,  1040, false, true,  null, null),
  ('lim_color',  '색만',     null,          '색 방법',       'limited', true,  1005, false, false, null, '#00AA55');

-- ===== 1. public_title_info: 누구나, 공개 가능한 칸만 =====
set role anon;
select t.ok('비로그인도 부를 수 있음', jsonb_typeof(pg_temp.info()) = 'array');
select t.fails('비로그인: 도감 표 직접 읽기는 그대로 거부', 'select * from title_catalog', 'permission denied');
select t.fails('비로그인: 장착 불가 트리거 함수 못 부름', 'select title_catalog_unequip()', 'permission denied');
reset role;
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.ok('회원도 부를 수 있음', jsonb_typeof(pg_temp.info()) = 'array');
select t.fails('회원: 도감 표 직접 읽기는 그대로 거부', 'select * from title_catalog', 'permission denied');
reset role;
select t.ok('순서: 활동 6 -> 한정판(sort_order), 장인/숨김/아무도 안 단 비밀은 빠짐',
  pg_temp.info_keys() = array['top_addict', 'tool_hater', 'solid_heavy', 'butcher_owner', 'general', 'offmeta', 'lim_color', 'lim_cup', 'lim_plain']);
select t.ok('칸은 key/kind/name/icon/color만',
  not exists (select 1 from jsonb_array_elements(pg_temp.info()) e
              where (select array_agg(k order by k) from jsonb_object_keys(e) k) <> array['color', 'icon', 'key', 'kind', 'name']));
select t.ok('한정판 그림/색/이름', exists (select 1 from jsonb_array_elements(pg_temp.info()) e
  where e ->> 'key' = 'lim_cup' and e ->> 'name' = '티확찢' and e ->> 'icon' = 'lim_cup.webp' and e ->> 'color' = '#C0392B' and e ->> 'kind' = 'limited'));
select t.ok('활동 칭호는 예전 이름, 그림/색 없음', exists (select 1 from jsonb_array_elements(pg_temp.info()) e
  where e ->> 'key' = 'solid_heavy' and e ->> 'name' = '단단묵직' and e -> 'icon' = 'null'::jsonb and e -> 'color' = 'null'::jsonb));
select t.ok('응답에 소개/얻는 방법/비밀 이름/숨김 이름 없음',
  position('공모전 1등' in pg_temp.info()::text) = 0 and position('공모전 우승' in pg_temp.info()::text) = 0
  and position('비밀이름' in pg_temp.info()::text) = 0 and position('숨김' in pg_temp.info()::text) = 0);

-- ===== 2. 대표 칭호: 장착 가능한 한정판은 고를 수 있음 =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select grant_title(:'U', 'lim_cup', '공모전 우승');
select grant_title(:'U', 'lim_plain', '공모전 참가');
select grant_title(:'U', 'lim_secret', '비밀 이벤트');
select grant_title(:'U', 'lim_hidden', '숨김 시험');
select grant_title(:'V', 'lim_cup', '공동 우승');
select grant_title(:'V', 'lim_color', '색 시험');
set request.jwt.claim.sub = :'U';
update profiles set main_title = 'lim_cup' where id = auth.uid();
reset role;
select t.ok('장착 가능한 한정판을 대표로 고름', pg_temp.main(:'U') = 'lim_cup');
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('장착 불가 한정판은 못 고름', $$update profiles set main_title = 'lim_plain' where id = auth.uid()$$, '대표 칭호로 고를 수 없습니다');
select t.fails('숨김 칭호는 장착 가능이어도 못 고름', $$update profiles set main_title = 'lim_hidden' where id = auth.uid()$$, '대표 칭호로 고를 수 없습니다');
select t.fails('장인은 그대로 못 고름', $$update profiles set main_title = 'influencer' where id = auth.uid()$$, '대표 칭호로 고를 수 없습니다');
select t.fails('안 가진 한정판은 외래 키', $$update profiles set main_title = 'lim_color' where id = auth.uid()$$, 'profiles_main_title_owned');
select t.ok('실패한 시도 뒤에도 대표 칭호 그대로', pg_temp.main(auth.uid()) = 'lim_cup');
set request.jwt.claim.sub = :'W';
select t.fails('장인 회원도 장인 칭호는 대표로 못 고름', $$update profiles set main_title = 'influencer' where id = auth.uid()$$, '대표 칭호로 고를 수 없습니다');
set request.jwt.claim.sub = :'V';
update profiles set main_title = 'lim_cup' where id = auth.uid();
reset role;

-- ===== 3. 비밀 칭호: 누군가 대표로 달면 이름/그림/색이 공개 정보에 들어감 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
update profiles set main_title = 'lim_secret' where id = auth.uid();
reset role;
set role anon;
select t.ok('비밀 칭호를 대표로 단 회원이 있으면 공개 정보에 들어감 (비로그인에게도)',
  exists (select 1 from jsonb_array_elements(pg_temp.info()) e where e ->> 'key' = 'lim_secret' and e ->> 'name' = '비밀이름' and e ->> 'color' = '#112233'));
select t.ok('그래도 비밀 칭호의 소개/얻는 방법은 없음', position('비밀 방법' in pg_temp.info()::text) = 0 and position('비밀 소개' in pg_temp.info()::text) = 0);
reset role;
set role authenticated;
set request.jwt.claim.sub = :'U';
update profiles set main_title = null where id = auth.uid();
reset role;
select t.ok('대표에서 내리면 다시 빠짐', not ('lim_secret' = any (pg_temp.info_keys())));
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.ok('비밀 칭호를 대표에서 내려도 가진 사람의 도감에는 그대로 보임',
  exists (select 1 from jsonb_array_elements(my_title_book() -> 'items') i where i ->> 'key' = 'lim_secret' and i ->> 'name' = '비밀이름'
          and (i ->> 'equippable')::boolean));
update profiles set main_title = 'lim_cup' where id = auth.uid();
reset role;

-- ===== 4. 회수하면 대표 칭호가 저절로 비워짐 (외래 키 on delete set null) =====
create temp table before_titles as select count(*) as n from user_titles;
set role authenticated;
set request.jwt.claim.sub = :'OP';
select revoke_title(:'U', 'lim_cup', '부정 취득 확인');
reset role;
select t.ok('한정판 회수 -> 그 회원의 대표 칭호만 비워짐', pg_temp.main(:'U') is null and pg_temp.main(:'V') = 'lim_cup');
select t.ok('회수는 그 줄 하나만', (select count(*) from user_titles) = (select n - 1 from before_titles));
select t.ok('알림은 회수 알림 그대로', exists (select 1 from notifications where user_id = :'U' and kind = 'title_revoked'
  and message = '칭호 ''티확찢''이 회수됐습니다. 사유: 부정 취득 확인'));

-- ===== 5. 운영자가 장착 불가로 바꾸거나 숨기면 대표 칭호가 비워짐 =====
set role authenticated;
set request.jwt.claim.sub = :'V';
update profiles set main_title = 'lim_color' where id = auth.uid();
reset role;
update title_catalog set name = '색만2' where key = 'lim_color';
select t.ok('이름만 바꾸면 대표 칭호 그대로 + 공개 정보에 새 이름',
  pg_temp.main(:'V') = 'lim_color' and exists (select 1 from jsonb_array_elements(pg_temp.info()) e where e ->> 'key' = 'lim_color' and e ->> 'name' = '색만2'));
update title_catalog set equippable = false where key = 'lim_color';
select t.ok('장착 불가로 바꾸면 대표 칭호 비워짐 (칭호 줄은 그대로)', pg_temp.main(:'V') is null
  and exists (select 1 from user_titles where user_id = :'V' and title_key = 'lim_color'));
update title_catalog set equippable = true where key = 'lim_color';
set role authenticated;
set request.jwt.claim.sub = :'V';
update profiles set main_title = 'lim_cup' where id = auth.uid();
reset role;
update title_catalog set hidden = true where key = 'lim_cup';
select t.ok('숨기면 대표 칭호 비워짐 + 공개 정보에서 빠짐', pg_temp.main(:'V') is null and not ('lim_cup' = any (pg_temp.info_keys())));
update title_catalog set hidden = false where key = 'lim_cup';

-- ===== 6. 활동 칭호는 예전과 같음 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select create_post('첫 글', '본문');
update profiles set main_title = 'top_addict' where id = auth.uid();
reset role;
select t.ok('활동 칭호 대표 고르기 그대로', pg_temp.main(:'U') = 'top_addict');
update xp_rules set value = 99 where key = 'title_top_addict';
select sync_rewards(:'U');
select t.ok('활동 칭호가 회수되면 sync_rewards로 대표 칭호 비워짐 (예전과 같음), 한정판 줄은 그대로', pg_temp.main(:'U') is null
  and exists (select 1 from user_titles where user_id = :'U' and title_key = 'lim_secret'));
update xp_rules set value = 1 where key = 'title_top_addict';

-- ===== 7. 되돌리기 SQL (054 파일 맨 위 주석과 같은 내용) =====
set role authenticated;
set request.jwt.claim.sub = :'V';
update profiles set main_title = 'lim_cup' where id = auth.uid();
reset role;
create temp table titles_before_rollback as select user_id, title_key from user_titles;
begin;
drop trigger if exists title_catalog_unequip on public.title_catalog;
drop function if exists public.title_catalog_unequip();
drop function if exists public.public_title_info();
update public.profiles p set main_title = null
  from public.title_catalog c where c.key = p.main_title and c.kind <> 'activity';
update public.title_catalog set equippable = false where kind <> 'activity' and equippable;
alter table public.title_catalog drop constraint if exists title_catalog_equip_kind;
alter table public.title_catalog add constraint title_catalog_equip_activity_only check (kind = 'activity' or not equippable);
comment on column public.title_catalog.equippable is null;
create or replace function public.check_main_title_equippable()
returns trigger language plpgsql security definer set search_path = ''
as $f$
begin
  if new.main_title is not null
     and not exists (select 1 from public.title_catalog c where c.key = new.main_title and c.equippable) then
    raise exception '이 칭호는 대표 칭호로 고를 수 없습니다.' using errcode = '23514';
  end if;
  return new;
end;
$f$;
commit;
select t.ok('되돌리기: 함수/트리거 없어지고 053 제약으로', to_regprocedure('public.public_title_info()') is null
  and to_regprocedure('public.title_catalog_unequip()') is null
  and not exists (select 1 from pg_trigger where tgname = 'title_catalog_unequip')
  and exists (select 1 from pg_constraint where conname = 'title_catalog_equip_activity_only')
  and not exists (select 1 from pg_constraint where conname = 'title_catalog_equip_kind'));
select t.ok('되돌리기: 한정판 대표 칭호는 비워지고 칭호 줄은 그대로', pg_temp.main(:'V') is null
  and (select count(*) from user_titles) = (select count(*) from titles_before_rollback)
  and not exists (select user_id, title_key from titles_before_rollback except select user_id, title_key from user_titles));
select t.ok('되돌리기: 053 규칙(한정판 장착 불가)으로', not exists (select 1 from title_catalog where kind <> 'activity' and equippable)
  and pg_get_functiondef('public.check_main_title_equippable'::regproc) not like '%054%');
select t.fails('되돌린 뒤 한정판은 다시 장착 가능으로 못 바꿈', $$update title_catalog set equippable = true where key = 'lim_cup'$$, 'title_catalog_equip_activity_only');
