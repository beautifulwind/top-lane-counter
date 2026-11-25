-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것. (운영 DB 확인은 scripts/check_kept_titles_after.sql)
-- 076 유지 칭호 builder(빌드 설계자) - 077에서 first_upload(첫 발자국)는 폐지(아래 「첫 발자국」 기대값은 077 뒤 규칙 = 주지 않음):
--   도감·설정값·칸 모양, 새 함수 실행 권한 없음(쓰기 함수 103/30/73·읽기 함수 66 그대로), sync_rewards 본문은 한 줄만 바뀜(되돌리면 이전 지문),
--   첫 상대법(create_matchup)·첫 빌드(create_build)·옛 방식 새 상대법 제안 → 077 뒤로는 칭호·알림 없음,
--   공개 빌드 10개 → 빌드 설계자 + title_earned 알림 1줄·휴대폰 알림(net.http_post) 없음(숨김·대기·숨긴 상대법 제외, 상대법이 공개되면 셈),
--   한 번 얻으면 숨기거나 지워도 유지(sync_rewards가 기존 활동 칭호는 회수하지만 유지 칭호는 안 건드림), 두 번 받지 않음, 운영자 없음,
--   조용히(p_quiet) 주기, 도감 줄이 없으면 주지 않고 등록도 실패하지 않음, 도감·대표 칭호(my_title_book·public_title_info·장착),
--   푸시 판정: push_group·push_wanted 074 지문 그대로, title_earned는 묶음 없음, 모든 사람 × 모든 종류 판정이 칭호를 준 전후로 같음
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP '00000000-0000-0000-0000-0000000000d0'
\set U  '00000000-0000-0000-0000-0000000000d1'
\set V  '00000000-0000-0000-0000-0000000000d2'
\set W  '00000000-0000-0000-0000-0000000000d3'
\set B  '00000000-0000-0000-0000-0000000000d4'
\set H  '00000000-0000-0000-0000-0000000000d5'
\set C  '00000000-0000-0000-0000-0000000000d6'
\set T  '00000000-0000-0000-0000-0000000000d7'
\set Q  '00000000-0000-0000-0000-0000000000d8'
\set N  '00000000-0000-0000-0000-0000000000d9'
\set doc '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'U', 'u@x.com'), (:'V', 'v@x.com'), (:'W', 'w@x.com'), (:'B', 'b@x.com'),
  (:'H', 'h@x.com'), (:'C', 'c@x.com'), (:'T', 't@x.com'), (:'Q', 'q@x.com'), (:'N', 'n@x.com');
update public.profiles set nickname = '영자', role = 'admin', level = 0, xp = 0, main_title = null where id = :'OP';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = '브이' where id = :'V';
update public.profiles set nickname = '더블유' where id = :'W';
update public.profiles set nickname = '비' where id = :'B';
update public.profiles set nickname = '에이치' where id = :'H';
update public.profiles set nickname = '씨' where id = :'C';
update public.profiles set nickname = '티' where id = :'T';
update public.profiles set nickname = '큐' where id = :'Q';
update public.profiles set nickname = '엔' where id = :'N';
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;
create function pg_temp.tk(n int) returns text language sql immutable as $$ select md5('tok' || n) || md5('ken' || n) $$;
-- 휴대폰 알림이 갈 수 있는 상태로 만든다 (웹 구독·앱 토큰·발송 주소) - 그래도 칭호 알림은 부르지 않아야 한다
insert into public.push_subscriptions (user_id, endpoint, p256dh, auth) values (:'U', 'https://push.example/u', 'k', 'a'), (:'B', 'https://push.example/b', 'k', 'a');
insert into public.device_push_tokens (user_id, platform, token) values (:'V', 'ios', pg_temp.tk(1)), (:'W', 'android', pg_temp.tk(2));
insert into vault.decrypted_secrets values ('push_function_url', 'https://fn.test/functions/v1/web-push'), ('push_webhook_secret', 's3cret');

create function pg_temp.has(u uuid, k text) returns boolean language sql stable as $$
  select exists (select 1 from public.user_titles where user_id = u and title_key = k) $$;
create function pg_temp.earned(u uuid, nm text) returns integer language sql stable as $$
  select count(*)::integer from public.notifications where user_id = u and kind = 'title_earned' and message like '칭호 ''' || nm || '''%' $$;
-- 칭호 알림이 휴대폰 알림을 부른 수
create function pg_temp.pushed_titles() returns integer language sql stable as $$
  select count(*)::integer from net.calls c join public.notifications n on n.id = (c.body ->> 'notification_id')::bigint
   where n.kind in ('title_earned', 'title_revoked') $$;
-- 모든 사람 × 모든 알림 종류의 푸시 판정 지문
create function pg_temp.push_fp() returns text language sql stable as $$
  with kinds as (
    select (regexp_matches(pg_get_constraintdef(oid), '''([a-z_]+)''', 'g'))[1] as k
      from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass
    union select 'no_such_kind')
  select count(*) || ' / ' || md5(string_agg(p.id::text || ':' || k.k || ':' || public.push_wanted(p.id, k.k)::text || ':' || coalesce(public.push_group(k.k), '-'), ',' order by p.id, k.k))
    from public.profiles p cross join kinds k $$;
-- 빌드 바로 넣기 (검사 트리거를 잠깐 끄고 픽스처 빌드 복사 - fixtures.sql과 같은 방식). 보상 트리거는 그대로 돈다
create temp table src as select * from public.builds where counter_id = (select id from public.counters where counter_champion = 'Quinn') order by id limit 1;
create function pg_temp.mk(author uuid, st text, n integer, champ text default 'Quinn') returns void language sql as $$
  insert into public.builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch, status,
                             hide_reason, hidden_at, reject_reason)
  select (select id from public.counters where counter_champion = champ), author, s.runes, s.summoner_spells, s.starting_items, s.core_items,
         s.max_skill, s.patch, st, case when st = 'hidden' then '검사' end, case when st = 'hidden' then now() end,
         case when st = 'rejected' then '검사' end
    from src s, generate_series(1, n) $$;
grant execute on all functions in schema pg_temp to anon, authenticated;
select pg_temp.push_fp() as push0 \gset

-- ===== 1. 모양 / 권한 =====
select t.ok('유지 칭호 도감 1줄(077에서 첫 발자국 삭제): 활동·장착 가능·유지, 순서 65, 그림·색 없음',
  (select array_agg(key || ':' || name || ':' || kind || ':' || equippable || ':' || permanent || ':' || sort_order order by sort_order)
     from public.title_catalog where permanent)
  = array['builder:빌드 설계자:activity:true:true:65']
  and not exists (select 1 from public.title_catalog where key = 'first_upload')
  and not exists (select 1 from public.title_catalog where permanent and (icon is not null or color is not null or secret or hidden)));
select t.ok('기존 7줄은 permanent = false, 칸 기본값 false·not null',
  (select count(*) = 7 from public.title_catalog where not permanent and key in
     ('top_addict', 'tool_hater', 'solid_heavy', 'butcher_owner', 'general', 'offmeta', 'influencer'))
  and (select column_default = 'false' and is_nullable = 'NO' from information_schema.columns
        where table_schema = 'public' and table_name = 'title_catalog' and column_name = 'permanent'));
select t.ok('설정값 title_builder = 10', public.xp_rule('title_builder') = 10);
select t.ok('새 함수 2개: 아무도(anon·authenticated·public) 실행 못 함, security definer, search_path 빈 값', (
  select bool_and(not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                  and not exists (select 1 from unnest(p.proacl) a where a::text like '=%')
                  and p.prosecdef and p.proconfig = array['search_path=""']) and count(*) = 2
    from pg_proc p where p.oid in ('public.grant_kept_titles(uuid, boolean)'::regprocedure, 'public.kept_titles_on_change()'::regprocedure)));
select t.ok('068 쓰기 함수 수: 103 / 첫 줄 검사 30 / 허용 목록 73 그대로', (
  select count(*) = 103
     and count(*) filter (where p.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                             or p.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);') = 30
     and count(*) filter (where exists (select 1 from public.restriction_exemptions e where e.kind = 'function'
                                         and e.name = p.proname || '(' || oidvectortypes(p.proargtypes) || ')')) = 73
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))));
select t.ok('읽기 함수 66개 그대로 (075 뒤 수)', (
  select count(*) = 66 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile in ('s', 'i') and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))));
select t.ok('트리거 2개(077에서 edit_proposals_kept_titles 삭제): deferrable initially deferred, 지우기에는 반응 안 함', (
  select count(*) = 2 and bool_and(tgdeferrable and tginitdeferred) and bool_and((tgtype & 8) = 0)
    from pg_trigger where tgname in ('builds_kept_titles', 'counters_kept_titles', 'edit_proposals_kept_titles')));
select t.ok('grant_kept_titles: 077 본문(첫 발자국 조건 없음) 지문 3370625…', (select md5(replace(prosrc, E'\r', '')) from pg_proc
  where oid = 'public.grant_kept_titles(uuid, boolean)'::regprocedure) = '3370625539c7ce4bd794a96b4609b03f');
select t.ok('sync_rewards: 076 지문, 바뀐 줄을 되돌리면 076 전 지문(c405f791…), 모양·권한 그대로',
  (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'public.sync_rewards(uuid, boolean)'::regprocedure) = 'd31e09d02d8344c09ec4adc3a2a00992'
  and (select md5(replace(replace(prosrc, E'\r', ''),
         $s$and c.kind = 'activity' and not c.permanent and not (ut.title_key = any (want)) loop  -- 053: 활동 칭호만 회수, 076: 유지 칭호 제외$s$,
         $s$and c.kind = 'activity' and not (ut.title_key = any (want)) loop  -- 053: 활동 칭호만 회수$s$))
         from pg_proc where oid = 'public.sync_rewards(uuid, boolean)'::regprocedure) = 'c405f7913721afcaf02a560d0427dd40'
  and (select pg_get_function_result(oid) = 'void' and prosecdef and proconfig = array['search_path=""'] and array_to_string(proacl, ',') = 'postgres=X/postgres'
         from pg_proc where oid = 'public.sync_rewards(uuid, boolean)'::regprocedure));
select t.ok('push_group·push_wanted 본문은 074 그대로, title_earned·title_revoked는 묶음 없음',
  (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'public.push_group(text)'::regprocedure) = '2be75ed999aa158e20557beda4db0814'
  and (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'public.push_wanted(uuid, text)'::regprocedure) = 'fa8eb83cd5786a7155e5f2439917b04e'
  and public.push_group('title_earned') is null and public.push_group('title_revoked') is null);
select t.ok('fixtures 빌드(작성자 없음)에는 칭호를 주지 않음', not exists (select 1 from public.user_titles where user_id is null));

-- ===== 2. 첫 발자국 폐지(077): 실제 등록 함수로 처음 올려도 칭호·알림 없음 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select create_matchup('Darius', 'Garen', t.build() || :'doc'::jsonb) as mu \gset
reset role;
select t.ok('첫 상대법(create_matchup) → 칭호·칭호 알림 없음', not exists (select 1 from public.user_titles where user_id = :'U' and title_key in ('first_upload', 'builder'))
  and not exists (select 1 from public.notifications where user_id = :'U' and kind = 'title_earned' and (message like '%첫 발자국%' or message like '%빌드 설계자%')));
set role authenticated;
set request.jwt.claim.sub = :'V';
insert into ids select 'bV', create_build((select id from public.counters where counter_champion = 'Quinn'), t.build(array['3071','3047','3053']) || :'doc'::jsonb);
reset role;
select t.ok('첫 빌드(create_build) → 칭호·칭호 알림 없음', not pg_temp.has(:'V', 'first_upload') and pg_temp.earned(:'V', '첫 발자국') = 0);
-- 옛 방식(승인 제도) 새 상대법 제안 (대기) - 표에 바로 넣기
insert into public.edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Fiora', :'W', :'doc', t.build());
select public.grant_kept_titles(:'W') as gw \gset
select t.ok('옛 방식 새 상대법 제안 → 칭호 없음, 직접 불러도 0', not pg_temp.has(:'W', 'first_upload') and :gw = 0 and pg_temp.earned(:'W', '첫 발자국') = 0);
-- 숨김 처리된 빌드만 있는 사람
begin;
alter table public.builds disable trigger builds_check_new;
select pg_temp.mk(:'H', 'hidden', 3);
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
commit;
select public.grant_kept_titles(:'H') as gh \gset
select t.ok('숨김 빌드만 있는 사람도 칭호 없음', not pg_temp.has(:'H', 'first_upload') and :gh = 0);
begin;
alter table public.builds disable trigger builds_check_new;
select pg_temp.mk(:'N', 'rejected', 1);
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
commit;
select t.ok('거절된 빌드만 있는 사람도 칭호 없음', not pg_temp.has(:'N', 'first_upload'));
select t.ok('도감에 줄이 없어 first_upload는 user_titles에 들어갈 수도 없음(외래 키)', not exists (select 1 from public.title_catalog where key = 'first_upload'));

-- ===== 3. 빌드 설계자: 공개 빌드 10개 =====
begin;
alter table public.builds disable trigger builds_check_new;
select pg_temp.mk(:'B', 'approved', 9), pg_temp.mk(:'B', 'hidden', 3), pg_temp.mk(:'B', 'pending', 2);
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
commit;
select t.ok('공개 9 + 숨김 3 + 대기 2 → 빌드 설계자 없음 (첫 발자국도 없음 - 077)', not pg_temp.has(:'B', 'builder') and not pg_temp.has(:'B', 'first_upload'));
update public.builds set status = 'approved', hide_reason = null, hidden_at = null where id = (select min(id) from public.builds where author_id = :'B' and status = 'hidden');
select t.ok('숨긴 빌드 하나가 다시 공개되어 10개 → 빌드 설계자 + 알림 1줄', pg_temp.has(:'B', 'builder') and pg_temp.earned(:'B', '빌드 설계자') = 1
  and (select message from public.notifications where user_id = :'B' and message like '칭호 ''빌드 설계자''%')
      = '칭호 ''빌드 설계자''를 얻었습니다. [마이페이지]에서 대표 칭호로 고를 수 있습니다.');
-- 숨기고 지워도 유지
update public.builds set status = 'hidden', hide_reason = '검사', hidden_at = now() where author_id = :'B' and status = 'approved';
select t.ok('공개 빌드를 모두 숨겨도 빌드 설계자 유지, 회수 알림 없음', pg_temp.has(:'B', 'builder')
  and not exists (select 1 from public.notifications where user_id = :'B' and kind = 'title_revoked' and (message like '%빌드 설계자%' or message like '%첫 발자국%')));
delete from public.builds where author_id = :'B';
select public.sync_rewards(:'B');
select t.ok('빌드를 모두 지우고 sync_rewards를 다시 돌려도 유지', pg_temp.has(:'B', 'builder'));
begin;
alter table public.builds disable trigger builds_check_new;
select pg_temp.mk(:'B', 'approved', 10);
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
commit;
select t.ok('다시 10개를 채워도 두 번 받지 않음 (칭호 1줄·알림 1줄, 첫 발자국 0)', pg_temp.earned(:'B', '빌드 설계자') = 1 and pg_temp.earned(:'B', '첫 발자국') = 0
  and (select count(*) from public.user_titles where user_id = :'B' and title_key in ('builder', 'first_upload')) = 1
  and public.grant_kept_titles(:'B') = 0);
-- 숨긴·대기 상대법의 빌드는 세지 않고, 상대법이 공개되면 센다
insert into public.counters (target_champion, counter_champion, sort_order, status) values ('Darius', 'Vayne', 10, 'pending');
begin;
alter table public.builds disable trigger builds_check_new;
select pg_temp.mk(:'C', 'approved', 10, 'Vayne');
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
commit;
select t.ok('대기 상대법의 공개 빌드 10개 → 빌드 설계자 없음', not pg_temp.has(:'C', 'builder') and not pg_temp.has(:'C', 'first_upload'));
update public.counters set status = 'hidden' where counter_champion = 'Vayne';
select t.ok('숨긴 상대법이어도 없음', not pg_temp.has(:'C', 'builder'));
update public.counters set status = 'approved' where counter_champion = 'Vayne';
select t.ok('상대법이 공개되면(counters 트리거) 빌드 설계자', pg_temp.has(:'C', 'builder') and pg_temp.earned(:'C', '빌드 설계자') = 1);
update public.xp_rules set value = 11 where key = 'title_builder';
select t.ok('기준을 11로 올려도 이미 받은 칭호는 유지', pg_temp.has(:'C', 'builder') and public.grant_kept_titles(:'C') = 0);
update public.xp_rules set value = 10 where key = 'title_builder';

-- ===== 4. 기존 활동 칭호는 예전처럼 회수, 유지 칭호는 그대로 =====
begin;
alter table public.builds disable trigger builds_check_new;
select pg_temp.mk(:'T', 'approved', 10);
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
commit;
select t.ok('공개 빌드 10개: 탑신병자(기존) + 빌드 설계자(유지), 첫 발자국 없음', pg_temp.has(:'T', 'top_addict') and pg_temp.has(:'T', 'builder') and not pg_temp.has(:'T', 'first_upload'));
update public.profiles set main_title = 'builder' where id = :'T';
update public.builds set status = 'hidden', hide_reason = '검사', hidden_at = now() where author_id = :'T';
select t.ok('숨기면 탑신병자는 예전처럼 회수(알림), 빌드 설계자는 유지·대표 칭호 그대로',
  not pg_temp.has(:'T', 'top_addict') and pg_temp.has(:'T', 'builder')
  and exists (select 1 from public.notifications where user_id = :'T' and kind = 'title_revoked' and message like '%탑신병자%')
  and not exists (select 1 from public.notifications where user_id = :'T' and kind = 'title_revoked' and message like '%빌드 설계자%')
  and (select main_title from public.profiles where id = :'T') = 'builder');
select t.ok('회수 알림도 휴대폰 알림 없음', pg_temp.pushed_titles() = 0);

-- ===== 5. 운영자·조용히·도감 줄 없음·탈퇴 =====
begin;
alter table public.builds disable trigger builds_check_new;
select pg_temp.mk(:'OP', 'approved', 10);
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
commit;
select t.ok('운영자는 칭호 없음', not exists (select 1 from public.user_titles where user_id = :'OP') and public.grant_kept_titles(:'OP') = 0);
select t.ok('없는 사람·null → 0', public.grant_kept_titles(null) = 0 and public.grant_kept_titles('00000000-0000-0000-0000-00000000ffff') = 0);
-- 조용히: 바로 넣은 빌드(트리거 끔)로 조건만 만들고 p_quiet
begin;
alter table public.builds disable trigger builds_kept_titles;
alter table public.builds disable trigger builds_check_new;
select pg_temp.mk(:'Q', 'approved', 10);
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
alter table public.builds enable trigger builds_kept_titles;
commit;
select t.ok('트리거 없이 넣으면 아직 없음', not pg_temp.has(:'Q', 'builder'));
select public.grant_kept_titles(:'Q', true) as gq \gset
select t.ok('조용히 주기: 1개(빌드 설계자만), 알림 없음', :gq = 1 and pg_temp.has(:'Q', 'builder') and not pg_temp.has(:'Q', 'first_upload')
  and pg_temp.earned(:'Q', '빌드 설계자') = 0 and pg_temp.earned(:'Q', '첫 발자국') = 0);
-- 도감에서 줄이 지워지면(받은 사람이 없을 때만 지울 수 있음) 주지 않고, 등록도 실패하지 않음
create temp table kept_backup as select * from public.user_titles where title_key = 'builder';
create temp table main_backup as select id, main_title from public.profiles where main_title = 'builder';
delete from public.user_titles where title_key = 'builder';
delete from public.title_catalog where key = 'builder';
begin;
alter table public.builds disable trigger builds_check_new;
select pg_temp.mk(:'N', 'approved', 10);
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
commit;
select t.ok('도감에 없는 칭호는 주지 않고 빌드 등록은 그대로 됨', not pg_temp.has(:'N', 'builder')
  and (select count(*) from public.builds where author_id = :'N' and status = 'approved') = 10);
insert into public.title_catalog (key, name, how_to, kind, equippable, permanent, sort_order)
values ('builder', '빌드 설계자', '공개 빌드 {n}개 (숨김 처리된 빌드는 세지 않음, 한 번 얻으면 유지)', 'activity', true, true, 65);
insert into public.user_titles select * from kept_backup;  -- 검사를 위해 지웠던 받은 기록을 그대로 되돌림
update public.profiles p set main_title = m.main_title from main_backup m where m.id = p.id;
select public.grant_kept_titles(:'N') as gn \gset
select t.ok('도감 줄을 되살리면 다음 계산 때 받음', :gn = 1 and pg_temp.has(:'N', 'builder'));
delete from auth.users where id = :'N';
select t.ok('탈퇴하면 칭호 줄도 지워짐 (cascade)', not exists (select 1 from public.user_titles where user_id = :'N'));

-- ===== 6. 화면이 읽는 함수: 도감·배지·장착 =====
set role authenticated;
set request.jwt.claim.sub = :'C';
select public.my_title_book() as book \gset
select t.ok('my_title_book: 활동 칭호 7개(빌드 설계자 포함, 첫 발자국 없음), 얻는 방법 {n} → 10, 얻음 표시',
  (select array_agg(e ->> 'key' order by o) from jsonb_array_elements(:'book'::jsonb -> 'items') with ordinality x(e, o) where e ->> 'kind' = 'activity')
    = array['top_addict', 'tool_hater', 'solid_heavy', 'butcher_owner', 'general', 'offmeta', 'builder']
  and (select e ->> 'how_to' from jsonb_array_elements(:'book'::jsonb -> 'items') e where e ->> 'key' = 'builder') = '공개 빌드 10개 (숨김 처리된 빌드는 세지 않음, 한 번 얻으면 유지)'
  and (select (e ->> 'owned')::boolean and (e ->> 'equippable')::boolean from jsonb_array_elements(:'book'::jsonb -> 'items') e where e ->> 'key' = 'builder'));
update public.profiles set main_title = 'builder' where id = :'C';
select t.ok('본인이 대표 칭호로 장착 가능', (select main_title from public.profiles where id = :'C') = 'builder');
reset role;
set role anon;
reset request.jwt.claim.sub;
select t.ok('public_title_info(비로그인): 빌드 설계자는 나오고 첫 발자국은 없음', (
  select count(*) = 1 from jsonb_array_elements(public.public_title_info()) e
   where (e ->> 'key', e ->> 'name', e ->> 'kind') in (('first_upload', '첫 발자국', 'activity'), ('builder', '빌드 설계자', 'activity')))
  and not exists (select 1 from jsonb_array_elements(public.public_title_info()) e where e ->> 'key' = 'first_upload'));
reset role;
set role authenticated;
set request.jwt.claim.sub = :'H';
select t.fails('못 얻은 칭호는 장착 불가', $$update public.profiles set main_title = 'builder' where id = '00000000-0000-0000-0000-0000000000d5'$$, 'profiles_main_title_owned');
select t.fails('직접 주기 불가 (내부 함수)', $$select public.grant_kept_titles('00000000-0000-0000-0000-0000000000d5')$$, 'permission denied');
select t.fails('칭호 표 직접 쓰기 불가', $$insert into public.user_titles (user_id, title_key) values ('00000000-0000-0000-0000-0000000000d5', 'builder')$$, 'permission denied');
reset role;
reset request.jwt.claim.sub;

-- ===== 7. 푸시 판정 그대로 =====
select t.ok('모든 사람 × 모든 알림 종류의 push_wanted·push_group 판정이 칭호를 준 전후로 같음 (' || :'push0' || ')',
  -- 사람 수가 줄어든 만큼(탈퇴 N)만 빼고 비교
  (with kinds as (
     select (regexp_matches(pg_get_constraintdef(oid), '''([a-z_]+)''', 'g'))[1] as k
       from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass
     union select 'no_such_kind')
   select count(*) || ' / ' || md5(string_agg(p.id::text || ':' || k.k || ':' || public.push_wanted(p.id, k.k)::text || ':' || coalesce(public.push_group(k.k), '-'), ',' order by p.id, k.k))
     from (select id from public.profiles union all select :'N'::uuid) p cross join kinds k) = :'push0');
select t.ok('title_earned는 모든 사람에게 푸시 대상 아님 (웹 구독·앱 토큰이 있어도)', not exists (
  select 1 from public.profiles p where public.push_wanted(p.id, 'title_earned') or public.push_wanted(p.id, 'title_revoked')));
select t.ok('끝까지 칭호 알림으로 부른 휴대폰 알림 0', pg_temp.pushed_titles() = 0);
