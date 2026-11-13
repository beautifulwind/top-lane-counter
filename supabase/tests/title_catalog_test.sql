-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 053: 칭호 도감 (표 권한, 외래 키, sync_rewards는 활동 칭호만 회수, title_name, my_title_book, grant_title/revoke_title, 대표 칭호)
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-00000000000b'
\set U   '00000000-0000-0000-0000-00000000000d'
\set V   '00000000-0000-0000-0000-00000000000c'
\set W   '00000000-0000-0000-0000-00000000000f'
\set GU  '00000000-0000-0000-0000-000000000010'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'MOD', 'm@x.com'), (:'U', 'u@x.com'), (:'V', 'v@x.com'), (:'W', 'w@x.com');
insert into auth.users (id, email, is_anonymous) values (:'GU', null, true);
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'MOD';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = '보통' where id = :'V';
update public.profiles set nickname = '장인님', influencer = 'pro', influencer_at = '2026-11-01 00:00+00' where id = :'W';
update public.profiles set nickname = '손님' where id = :'GU';
update public.xp_rules set value = 0 where key in ('post_interval', 'comment_interval');

create function pg_temp.titles(u uuid) returns text[] language sql as $$
  select coalesce(array_agg(title_key order by title_key), '{}') from public.user_titles where user_id = u $$;
create function pg_temp.notes(u uuid, k text) returns integer language sql as $$
  select count(*)::integer from public.notifications where user_id = u and kind = k $$;
create function pg_temp.item(book jsonb, k text) returns jsonb language sql as $$
  select i from jsonb_array_elements(book -> 'items') i where i ->> 'key' = k $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- ===== 0. 도감 표: 처음 7줄, 순서, 장착 가능 =====
select t.ok('처음 7줄: 활동 6 + 장인 1, 한정판 0', (select count(*) = 7 from title_catalog)
  and (select count(*) = 6 from title_catalog where kind = 'activity' and equippable)
  and (select count(*) = 1 from title_catalog where kind = 'influencer' and key = 'influencer' and name = '장인' and not equippable)
  and not exists (select 1 from title_catalog where kind = 'limited'));
select t.ok('기존 6개는 그림/색이 비어 있음 (화면 모양 그대로)', not exists (select 1 from title_catalog where icon is not null or color is not null));
select t.ok('title_name: 예전 이름 그대로 + 장인 + 없는 키는 키 그대로',
  title_name('top_addict') = '탑신병자' and title_name('tool_hater') = '도구혐오자' and title_name('solid_heavy') = '단단묵직'
  and title_name('butcher_owner') = '백정주인' and title_name('general') = '장군' and title_name('offmeta') = '비주류'
  and title_name('influencer') = '장인' and title_name('nope') = 'nope');
select t.fails('한정판은 장착 가능으로 못 넣음',
  $$insert into title_catalog (key, name, how_to, kind, equippable, sort_order) values ('lim_x', 'x', 'x', 'limited', true, 1000)$$,
  'title_catalog_equip_activity_only');
select t.fails('기간은 한정판만',
  $$insert into title_catalog (key, name, how_to, kind, equippable, sort_order, starts_at) values ('act_x', 'x', 'x', 'activity', true, 70, now())$$,
  'title_catalog_period_limited_only');
select t.fails('끝이 시작보다 빠르면 거부',
  $$insert into title_catalog (key, name, how_to, kind, sort_order, starts_at, ends_at) values ('lim_x', 'x', 'x', 'limited', 1000, now(), now() - interval '1 day')$$,
  'title_catalog_period_order');
select t.fails('그림 파일 이름에 경로 거부',
  $$insert into title_catalog (key, name, how_to, kind, sort_order, icon) values ('lim_x', 'x', 'x', 'limited', 1000, '../x.png')$$,
  'title_catalog_icon_check');
select t.fails('색은 #RRGGBB만',
  $$insert into title_catalog (key, name, how_to, kind, sort_order, color) values ('lim_x', 'x', 'x', 'limited', 1000, 'red')$$,
  'title_catalog_color_check');

-- 시험용 한정판 4개: 진행 중 / 시작 전(비밀) / 끝남 / 숨김
insert into title_catalog (key, name, description, how_to, kind, sort_order, starts_at, ends_at, secret, hidden, icon, color) values
  ('lim_open',   '진행중',   '소개1', '방법1', 'limited', 1010, now() - interval '1 day', now() + interval '1 day', false, false, 'lim_open.webp', '#C0392B'),
  ('lim_secret', '비밀이름', '소개2', '방법2', 'limited', 1020, now() + interval '3 day', null,                     true,  false, 'lim_secret.png', '#112233'),
  ('lim_ended',  '끝남',     null,    '방법3', 'limited', 1030, null,                     now() - interval '1 day', false, false, null, null),
  ('lim_hidden', '숨김',     null,    '방법4', 'limited', 1040, null,                     null,                     false, true,  null, null);

-- ===== 1. 클라이언트는 표를 직접 못 읽고 못 씀 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('회원: 표 읽기 거부', 'select * from title_catalog', 'permission denied');
select t.fails('회원: 표 쓰기 거부', $$insert into title_catalog (key, name, how_to, kind, sort_order) values ('lim_y', 'y', 'y', 'limited', 1)$$, 'permission denied');
select t.fails('회원: 칭호 직접 넣기 그대로 거부', $$insert into user_titles (user_id, title_key) values (auth.uid(), 'lim_open')$$, 'permission denied');
select t.fails('회원: title_name 직접 못 부름 (014 그대로)', $$select title_name('top_addict')$$, 'permission denied');
reset role;
set role anon;
select t.fails('비로그인: 표 읽기 거부', 'select * from title_catalog', 'permission denied');
select t.fails('비로그인: 도감 함수 거부', 'select my_title_book()', 'permission denied');
reset role;
select t.ok('표 RLS 켜짐', (select relrowsecurity from pg_class where oid = 'public.title_catalog'::regclass));

-- ===== 2. 외래 키 + 장인 칭호 줄 막기 =====
select t.fails('없는 칭호 키는 user_titles에 못 들어감', format('insert into user_titles (user_id, title_key) values (%L, %L)', :'U', 'nope'), 'user_titles_title_key_fkey');
select t.fails('장인 칭호 줄은 못 넣음', format('insert into user_titles (user_id, title_key) values (%L, %L)', :'W', 'influencer'), '장인 칭호는 장인 인증으로만');
select t.fails('도감에서 쓰이는 칭호는 못 지움', $$delete from title_catalog where key = 'top_addict'$$, 'user_titles_title_key_fkey')
  where exists (select 1 from user_titles where title_key = 'top_addict');

-- ===== 3. 활동 칭호는 예전과 같이 + 실제 회원의 칭호가 지워지지 않음 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select create_post('첫 글', '본문');
set request.jwt.claim.sub = :'V';
select create_post('보통 글', '본문');
reset role;
select t.ok('글을 쓰면 탑신병자 (예전과 같음)', pg_temp.titles(:'U') = array['top_addict'] and pg_temp.titles(:'V') = array['top_addict']);
set role authenticated;
set request.jwt.claim.sub = :'U';
update profiles set main_title = 'top_addict' where id = auth.uid();
reset role;
create temp table snap as select user_id, title_key, earned_at from user_titles;
create temp table snap_main as select id, main_title from profiles where main_title is not null;
select recalc_all_xp(true);
select t.ok('모두 다시 계산해도 칭호/얻은 시각/대표 칭호 그대로',
  (select count(*) from snap) = (select count(*) from user_titles)
  and not exists (select user_id, title_key, earned_at from snap except select user_id, title_key, earned_at from user_titles)
  and not exists (select id, main_title from snap_main except select id, main_title from profiles where main_title is not null)
  and (select count(*) from snap_main) = 1);

-- ===== 4. grant_title 권한/입력 =====
delete from notifications;
delete from moderation_log;
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관 지급 거부', format('select grant_title(%L, %L, %L)', :'U', 'lim_open', 'x'), '운영자만');
set request.jwt.claim.sub = :'U';
select t.fails('회원 지급 거부', format('select grant_title(%L, %L, %L)', :'U', 'lim_open', 'x'), '운영자만');
select t.fails('회원 회수 거부', format('select revoke_title(%L, %L, %L)', :'U', 'lim_open', 'x'), '운영자만');
set request.jwt.claim.sub = :'OP';
select set_operator_mode(false);
select t.fails('운영자 모드 꺼짐 거부', format('select grant_title(%L, %L, %L)', :'U', 'lim_open', 'x'), '운영자만');
select set_operator_mode(true);
select t.fails('메모 없으면 거부', format('select grant_title(%L, %L, %L)', :'U', 'lim_open', '  '), '지급 메모를 적어 주세요');
select t.fails('메모 501자 거부', format('select grant_title(%L, %L, %L)', :'U', 'lim_open', repeat('a', 501)), '500자 이하');
select t.fails('없는 칭호', format('select grant_title(%L, %L, %L)', :'U', 'nope', 'x'), '칭호를 찾지 못했습니다');
select t.fails('활동 칭호는 직접 못 줌', format('select grant_title(%L, %L, %L)', :'V', 'general', 'x'), '한정판 칭호만 직접 줄 수 있습니다');
select t.fails('장인 칭호는 직접 못 줌', format('select grant_title(%L, %L, %L)', :'V', 'influencer', 'x'), '한정판 칭호만 직접 줄 수 있습니다');
select t.fails('없는 회원', format('select grant_title(%L, %L, %L)', '00000000-0000-0000-0000-0000000000ff', 'lim_open', 'x'), '회원을 찾지 못했습니다');
select t.fails('운영자 계정에는 못 줌', format('select grant_title(%L, %L, %L)', :'OP', 'lim_open', 'x'), '운영자 계정에는');
reset role;
set role anon;
select t.fails('비로그인 거부', format('select grant_title(%L, %L, %L)', :'U', 'lim_open', 'x'), 'permission denied');
reset role;
select t.ok('거부된 시도는 아무것도 남기지 않음', (select count(*) = 0 from moderation_log) and (select count(*) = 0 from notifications)
  and not exists (select 1 from user_titles where title_key like 'lim_%'));

-- ===== 5. 지급: 줄, 알림, 처리 기록 / 끝난 칭호도 줄 수 있음 / 게스트도 =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select grant_title(:'U', 'lim_open', '  12월 이벤트 1등  ');
select grant_title(:'U', 'lim_secret', '비밀 이벤트');
select grant_title(:'V', 'lim_ended', '지난 이벤트 늦게 지급');
select grant_title(:'GU', 'lim_open', '게스트 참여');
select t.fails('이미 가진 칭호 거부', format('select grant_title(%L, %L, %L)', :'U', 'lim_open', 'x'), '이미 가진 칭호입니다');
reset role;
select t.ok('지급: user_titles 줄', pg_temp.titles(:'U') = array['lim_open', 'lim_secret', 'top_addict']
  and pg_temp.titles(:'V') = array['lim_ended', 'top_addict'] and pg_temp.titles(:'GU') = array['lim_open']);
select t.ok('지급 알림 title_earned (조사, 마이페이지 안내)', pg_temp.notes(:'U', 'title_earned') = 2
  and exists (select 1 from notifications where user_id = :'U' and kind = 'title_earned'
               and message = '칭호 ''진행중''을 얻었습니다. [마이페이지] 칭호 칸에서 볼 수 있습니다.')
  and exists (select 1 from notifications where user_id = :'V' and message = '칭호 ''끝남''을 얻었습니다. [마이페이지] 칭호 칸에서 볼 수 있습니다.'));
select t.ok('처리 기록 grant_title (대상 닉네임, 칭호 이름 + 메모 앞뒤 공백 정리)',
  (select count(*) = 4 from moderation_log where action = 'grant_title')
  and exists (select 1 from moderation_log where action = 'grant_title' and target_kind = 'user' and target_id = :'U'
               and target_nickname = '유저' and actor_id = :'OP' and note = '진행중 ' || chr(183) || ' 12월 이벤트 1등'));

-- ===== 6. sync_rewards는 한정판을 지우지 않음, 활동 칭호는 예전처럼 회수/지급 =====
delete from notifications;
update xp_rules set value = 99 where key = 'title_top_addict';
select sync_rewards(:'U');
select t.ok('활동 칭호 조건이 깨지면 그것만 회수, 한정판은 그대로', pg_temp.titles(:'U') = array['lim_open', 'lim_secret']);
select t.ok('대표 칭호(탑신병자)는 비워짐 (예전과 같음)', (select main_title is null from profiles where id = :'U'));
select t.ok('회수 알림은 활동 칭호 1개만', pg_temp.notes(:'U', 'title_revoked') = 1
  and exists (select 1 from notifications where user_id = :'U' and kind = 'title_revoked' and message like '칭호 ''탑신병자''가 회수됐습니다.%'));
update xp_rules set value = 1 where key = 'title_top_addict';
select recalc_all_xp(true);
select t.ok('조건을 다시 채우면 다시 받음, 한정판 그대로', pg_temp.titles(:'U') = array['lim_open', 'lim_secret', 'top_addict']
  and pg_temp.titles(:'V') = array['lim_ended', 'top_addict'] and pg_temp.titles(:'GU') = array['lim_open']);
-- 글을 지워 활동 칭호가 사라져도(트리거로 sync_rewards) 한정판은 남음
set role authenticated;
set request.jwt.claim.sub = :'V';
select delete_my_post((select id from posts where author_id = :'V'));
reset role;
select t.ok('글 삭제로 활동 칭호 회수 (트리거) -> 한정판 그대로', pg_temp.titles(:'V') = array['lim_ended']);

-- ===== 7. 대표 칭호: 활동 칭호만 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('한정판은 대표로 못 고름', $$update profiles set main_title = 'lim_open' where id = auth.uid()$$, '대표 칭호로 고를 수 없습니다');
select t.fails('장인은 대표로 못 고름 (가진 칭호도 아님)', $$update profiles set main_title = 'influencer' where id = auth.uid()$$, '대표 칭호로 고를 수 없습니다');
update profiles set main_title = 'top_addict' where id = auth.uid();
select t.ok('활동 칭호는 그대로 고름', (select main_title = 'top_addict' from profiles where id = auth.uid()));
select t.fails('안 가진 활동 칭호는 예전처럼 외래 키', $$update profiles set main_title = 'general' where id = auth.uid()$$, 'profiles_main_title_owned');
update profiles set main_title = null where id = auth.uid();
select t.ok('비우기 가능', (select main_title is null from profiles where id = auth.uid()));
reset role;

-- ===== 8. my_title_book =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select my_title_book() as bu \gset
set request.jwt.claim.sub = :'V';
select my_title_book() as bv \gset
set request.jwt.claim.sub = :'W';
select my_title_book() as bw \gset
set request.jwt.claim.sub = :'OP';
select my_title_book() as bo \gset
reset role;
select t.ok('순서: 활동 6 -> 장인 -> 한정판, 숨김은 빠짐',
  (select array_agg(i ->> 'key' order by n) from jsonb_array_elements(:'bu'::jsonb -> 'items') with ordinality a(i, n))
  = array['top_addict', 'tool_hater', 'solid_heavy', 'butcher_owner', 'general', 'offmeta', 'influencer', 'lim_open', 'lim_secret', 'lim_ended']);
select t.ok('숨김 칭호는 가진 사람에게도 빠짐', pg_temp.item(:'bv'::jsonb, 'lim_hidden') is null and pg_temp.item(:'bu'::jsonb, 'lim_hidden') is null);
select t.ok('활동 칭호 얻는 방법: {n}이 지금 기준 숫자로',
  pg_temp.item(:'bu'::jsonb, 'tool_hater') ->> 'how_to' = '상대법 관련 승인 10개'
  and pg_temp.item(:'bu'::jsonb, 'general') ->> 'how_to' = '공개 중인 내 빌드들의 추천 합계 100'
  and pg_temp.item(:'bu'::jsonb, 'top_addict') ->> 'how_to' like '처음으로 승인받은 기여 1개 또는%');
select t.ok('가진 칭호: owned + 얻은 시각, 못 가진 칭호: false + null',
  (pg_temp.item(:'bu'::jsonb, 'top_addict') ->> 'owned')::boolean and pg_temp.item(:'bu'::jsonb, 'top_addict') ->> 'earned_at' is not null
  and not (pg_temp.item(:'bu'::jsonb, 'general') ->> 'owned')::boolean and pg_temp.item(:'bu'::jsonb, 'general') -> 'earned_at' = 'null'::jsonb);
select t.ok('장착 가능: 활동만', (pg_temp.item(:'bu'::jsonb, 'top_addict') ->> 'equippable')::boolean
  and not (pg_temp.item(:'bu'::jsonb, 'influencer') ->> 'equippable')::boolean and not (pg_temp.item(:'bu'::jsonb, 'lim_open') ->> 'equippable')::boolean);
select t.ok('한정판 기간 상태: 진행 중 open / 시작 전 upcoming / 끝남 ended, 활동은 null',
  pg_temp.item(:'bu'::jsonb, 'lim_open') ->> 'period' = 'open' and pg_temp.item(:'bu'::jsonb, 'lim_secret') ->> 'period' = 'upcoming'
  and pg_temp.item(:'bu'::jsonb, 'lim_ended') ->> 'period' = 'ended' and pg_temp.item(:'bu'::jsonb, 'general') -> 'period' = 'null'::jsonb
  and pg_temp.item(:'bu'::jsonb, 'lim_open') ->> 'starts_at' is not null and pg_temp.item(:'bu'::jsonb, 'lim_secret') -> 'ends_at' = 'null'::jsonb);
select t.ok('한정판 그림/색/소개', pg_temp.item(:'bu'::jsonb, 'lim_open') ->> 'icon' = 'lim_open.webp'
  and pg_temp.item(:'bu'::jsonb, 'lim_open') ->> 'color' = '#C0392B' and pg_temp.item(:'bu'::jsonb, 'lim_open') ->> 'description' = '소개1');
select t.ok('비밀 칭호를 가진 사람: 다 보임', pg_temp.item(:'bu'::jsonb, 'lim_secret') ->> 'name' = '비밀이름'
  and pg_temp.item(:'bu'::jsonb, 'lim_secret') ->> 'how_to' = '방법2' and pg_temp.item(:'bu'::jsonb, 'lim_secret') ->> 'icon' = 'lim_secret.png'
  and (pg_temp.item(:'bu'::jsonb, 'lim_secret') ->> 'secret')::boolean);
select t.ok('비밀 칭호를 못 가진 사람: 이름/소개/방법/그림 null, 비밀 표시와 기간은 보임',
  pg_temp.item(:'bv'::jsonb, 'lim_secret') -> 'name' = 'null'::jsonb and pg_temp.item(:'bv'::jsonb, 'lim_secret') -> 'how_to' = 'null'::jsonb
  and pg_temp.item(:'bv'::jsonb, 'lim_secret') -> 'icon' = 'null'::jsonb and pg_temp.item(:'bv'::jsonb, 'lim_secret') -> 'description' = 'null'::jsonb
  and (pg_temp.item(:'bv'::jsonb, 'lim_secret') ->> 'secret')::boolean and not (pg_temp.item(:'bv'::jsonb, 'lim_secret') ->> 'owned')::boolean
  and pg_temp.item(:'bv'::jsonb, 'lim_secret') ->> 'period' = 'upcoming');
select t.ok('도감 응답에 비밀 이름이 아예 없음 (못 가진 사람)', position('비밀이름' in :'bv') = 0 and position('방법2' in :'bv') = 0);
select t.ok('장인: 인증된 사람은 owned + 인증일, 아닌 사람은 false',
  (pg_temp.item(:'bw'::jsonb, 'influencer') ->> 'owned')::boolean
  and (pg_temp.item(:'bw'::jsonb, 'influencer') ->> 'earned_at')::timestamptz = '2026-11-01 00:00+00'
  and (:'bw'::jsonb ->> 'influencer') = 'pro'
  and not (pg_temp.item(:'bu'::jsonb, 'influencer') ->> 'owned')::boolean and (:'bu'::jsonb -> 'influencer') = 'null'::jsonb
  and pg_temp.item(:'bu'::jsonb, 'influencer') ->> 'how_to' like '장인 인증을 받으면 표시됩니다%');
select t.ok('운영자 계정도 도감을 봄 (모두 못 가짐)', jsonb_array_length(:'bo'::jsonb -> 'items') = 10
  and not exists (select 1 from jsonb_array_elements(:'bo'::jsonb -> 'items') i where (i ->> 'owned')::boolean));
select t.ok('대표 칭호 칸', (:'bu'::jsonb -> 'main_title') = 'null'::jsonb);

-- ===== 9. revoke_title =====
delete from notifications;
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.fails('사유 없으면 거부', format('select revoke_title(%L, %L, %L)', :'U', 'lim_open', ''), '회수 사유를 적어 주세요');
select t.fails('활동 칭호는 직접 회수 못 함', format('select revoke_title(%L, %L, %L)', :'U', 'top_addict', 'x'), '한정판 칭호만 직접 회수할 수 있습니다');
select t.fails('안 가진 칭호', format('select revoke_title(%L, %L, %L)', :'V', 'lim_open', 'x'), '그 칭호를 가지고 있지 않습니다');
select revoke_title(:'U', 'lim_open', '부정 취득 확인');
reset role;
select t.ok('회수: 그 칭호만 지워짐', pg_temp.titles(:'U') = array['lim_secret', 'top_addict'] and pg_temp.titles(:'GU') = array['lim_open']);
select t.ok('회수 알림 (사유 포함)', exists (select 1 from notifications where user_id = :'U' and kind = 'title_revoked'
  and message = '칭호 ''진행중''이 회수됐습니다. 사유: 부정 취득 확인'));
select t.ok('처리 기록 revoke_title', exists (select 1 from moderation_log where action = 'revoke_title' and target_id = :'U'
  and note = '진행중 ' || chr(183) || ' 부정 취득 확인'));
set role authenticated;
set request.jwt.claim.sub = :'OP';
select grant_title(:'U', 'lim_open', '확인 뒤 다시 지급');
reset role;
select t.ok('회수 뒤 다시 지급 가능', pg_temp.titles(:'U') = array['lim_open', 'lim_secret', 'top_addict']);

-- ===== 10. 운영자가 되면 칭호를 모두 지움 (예전 트리거 그대로, 한정판 포함) / 탈퇴하면 함께 지워짐 =====
update profiles set role = 'user' where id = :'OP';  -- 운영자는 한 명뿐 (profiles_one_operator)
update profiles set role = 'admin' where id = :'GU';
select t.ok('운영자가 되면 칭호가 모두 지워짐 (한정판 포함)', pg_temp.titles(:'GU') = '{}');
delete from auth.users where id = :'V';
select t.ok('탈퇴하면 한정판 칭호 줄도 지워짐', not exists (select 1 from user_titles where user_id = :'V'));
select t.ok('도감 표는 그대로', (select count(*) = 11 from title_catalog));
