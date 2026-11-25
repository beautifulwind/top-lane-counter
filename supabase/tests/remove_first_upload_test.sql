-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것. (운영 DB 확인은 scripts/check_remove_first_upload_after.sql)
-- 077 칭호 「첫 발자국」(first_upload) 삭제:
--   이 DB는 이미 077까지 실행돼 있으므로, 077 맨 위 되돌리기 블록(로직만 076으로)으로 076 상태를 만들고 실제 등록 흐름으로 데이터를 쌓은 뒤
--   077 본문(begin/commit 사이)을 다시 실행한다. 두 블록은 077 파일에서 그대로 옮긴 것이다(옮긴 함수가 077과 같은지는 지문으로 확인).
--   확인: 지운 수(도감 1·받은 줄·대표 칭호·정확히 같은 문장의 알림), 다른 칭호(기존 6개·빌드 설계자·한정판)의 받은 줄·대표 칭호·알림은
--   한 줄도 안 바뀜(비슷한 이름의 한정판 「첫 발자국 기념」 알림 포함), 그 밖의 알림·데이터 그대로, 함수는 grant_kept_titles만 바뀜,
--   트리거 edit_proposals_kept_titles 삭제, 쓰기 함수 103/30/73·읽기 66·허용 목록·푸시 판정 지문 그대로, 077 뒤 처음 올려도 칭호 없음,
--   빌드 설계자는 그대로 동작, 되돌리기 블록이 076 본문을 되살림
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP '00000000-0000-0000-0000-0000000000e0'
\set A  '00000000-0000-0000-0000-0000000000e1'
\set B  '00000000-0000-0000-0000-0000000000e2'
\set C  '00000000-0000-0000-0000-0000000000e3'
\set D  '00000000-0000-0000-0000-0000000000e4'
\set E  '00000000-0000-0000-0000-0000000000e5'
\set doc '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'A', 'a@x.com'), (:'B', 'b@x.com'), (:'C', 'c@x.com'), (:'D', 'd@x.com'), (:'E', 'e@x.com');
update public.profiles set nickname = '영자', role = 'admin', level = 0, xp = 0, main_title = null where id = :'OP';
update public.profiles set nickname = '에이' where id = :'A';
update public.profiles set nickname = '비' where id = :'B';
update public.profiles set nickname = '씨' where id = :'C';
update public.profiles set nickname = '디' where id = :'D';
update public.profiles set nickname = '이' where id = :'E';
insert into public.push_subscriptions (user_id, endpoint, p256dh, auth) values (:'A', 'https://push.example/a', 'k', 'a'), (:'B', 'https://push.example/b', 'k', 'a');
insert into vault.decrypted_secrets values ('push_function_url', 'https://fn.test/functions/v1/web-push'), ('push_webhook_secret', 's3cret');
create temp table src as select * from public.builds where counter_id = (select id from public.counters where counter_champion = 'Quinn') order by id limit 1;
create function pg_temp.mk(author uuid, st text, n integer) returns void language sql as $$
  insert into public.builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch, status, hide_reason, hidden_at)
  select s.counter_id, author, s.runes, s.summoner_spells, s.starting_items, s.core_items, s.max_skill, s.patch, st,
         case when st = 'hidden' then '검사' end, case when st = 'hidden' then now() end
    from src s, generate_series(1, n) $$;
create function pg_temp.has(u uuid, k text) returns boolean language sql stable as $$
  select exists (select 1 from public.user_titles where user_id = u and title_key = k) $$;
create function pg_temp.push_fp() returns text language sql stable as $$
  with kinds as (
    select (regexp_matches(pg_get_constraintdef(oid), '''([a-z_]+)''', 'g'))[1] as k
      from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass
    union select 'no_such_kind')
  select count(*) || ' / ' || md5(string_agg(p.id::text || ':' || k.k || ':' || public.push_wanted(p.id, k.k)::text || ':' || coalesce(public.push_group(k.k), '-'), ',' order by p.id, k.k))
    from public.profiles p cross join kinds k $$;
create function pg_temp.counts() returns text language sql stable as $$
  select (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
             and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')))
    || '/' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
             and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
             and (p.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                  or p.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);'))
    || '/' || (select count(*) from public.restriction_exemptions where kind = 'function')
    || '/' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prokind = 'f' and p.provolatile in ('s', 'i') and p.prorettype <> 'trigger'::regtype
             and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')))
    || '/' || (select md5(string_agg(kind || ':' || name || ':' || reason, ',' order by kind, name)) from public.restriction_exemptions) $$;
-- grant_kept_titles를 뺀 public 함수 지문
create function pg_temp.fn_fp() returns text language sql stable as $$
  select count(*) || '/' || md5(string_agg(p.proname || '(' || oidvectortypes(p.proargtypes) || ')' || pg_get_function_result(p.oid) || p.provolatile::text
           || replace(p.prosrc, E'\r', '') || p.prosecdef::text || coalesce(array_to_string(p.proconfig, ','), '') || coalesce(array_to_string(p.proacl, ','), ''),
           '|' order by p.proname, oidvectortypes(p.proargtypes)))
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') and p.proname <> 'grant_kept_titles' $$;
-- 다른 칭호(첫 발자국이 아닌 것)의 받은 줄·대표 칭호·칭호 알림, 그 밖의 알림·빌드·도감
create function pg_temp.others() returns text language sql stable as $$
  select (select md5(coalesce(string_agg(user_id || ':' || title_key || ':' || earned_at, ',' order by user_id, title_key), '')) from public.user_titles where title_key <> 'first_upload')
    || '#' || (select md5(coalesce(string_agg(id || ':' || main_title, ',' order by id), '')) from public.profiles where main_title is not null and main_title <> 'first_upload')
    || '#' || (select md5(coalesce(string_agg(n::text, '|' order by n.id), '')) from public.notifications n
                where not (n.kind = 'title_earned' and n.message = '칭호 ''첫 발자국''을 얻었습니다. [마이페이지]에서 대표 칭호로 고를 수 있습니다.'))
    || '#' || (select md5(coalesce(string_agg(b.id || ':' || b.status || ':' || coalesce(b.author_id::text, '-'), ',' order by b.id), '')) from public.builds b)
    || '#' || (select md5(string_agg(c::text, '|' order by c.key)) from public.title_catalog c where c.key <> 'first_upload')
    || '#' || (select md5(string_agg(key || value, ',' order by key)) from public.xp_rules) $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

select t.ok('시작: 077 뒤 상태 (도감에 first_upload 없음, grant_kept_titles 077 본문, 제안 트리거 없음)',
  not exists (select 1 from public.title_catalog where key = 'first_upload')
  and (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'public.grant_kept_titles(uuid, boolean)'::regprocedure) = '3370625539c7ce4bd794a96b4609b03f'
  and not exists (select 1 from pg_trigger where tgname = 'edit_proposals_kept_titles'));
select pg_temp.fn_fp() as fn77 \gset

-- ===== 1. 077 되돌리기 블록으로 076 로직을 되살린다 (077 파일에서 그대로) =====
begin;
insert into public.title_catalog (key, name, how_to, kind, equippable, permanent, sort_order)
values ('first_upload', '첫 발자국', '상대법 또는 빌드를 처음 올리기 (한 번 얻으면 유지)', 'activity', true, true, 5);
create or replace function public.grant_kept_titles(p_user uuid, p_quiet boolean default false)
returns integer
language plpgsql security definer set search_path = ''
as $f$
declare
  t text;
  k integer;
  n integer := 0;
  nm text;
begin
  if p_user is null or not exists (select 1 from public.profiles where id = p_user and role <> 'admin') then
    return 0;  -- 탈퇴했거나 운영자 (칭호 없음)
  end if;
  foreach t in array array_remove(array[
    -- 첫 발자국: 상대법 또는 빌드를 올린 적이 있음 (숨김 처리된 것은 세지 않음)
    case when exists (select 1 from public.builds b where b.author_id = p_user and b.status <> 'hidden')
           or exists (select 1 from public.counters c where c.proposed_by = p_user and c.status <> 'hidden')
           or exists (select 1 from public.edit_proposals ep
                       where ep.proposer_id = p_user and ep.type = 'new_counter' and ep.status <> 'revoked')
         then 'first_upload' end,
    -- 빌드 설계자: 공개 빌드 수 (숨김·대기 빌드, 숨긴 상대법의 빌드 제외)
    case when (select count(*) from public.builds b join public.counters c on c.id = b.counter_id
                where b.author_id = p_user and b.status = 'approved' and c.status = 'approved')
              >= coalesce(public.xp_rule('title_builder'), 10)
         then 'builder' end
  ], null) loop
    -- 도감에서 지워졌거나 유지 칭호가 아니면 주지 않는다 (외래 키 오류로 빌드 등록이 실패하지 않게)
    continue when not exists (select 1 from public.title_catalog c where c.key = t and c.permanent);
    insert into public.user_titles (user_id, title_key) values (p_user, t) on conflict do nothing;
    get diagnostics k = row_count;
    if k > 0 then
      n := n + 1;
      if not p_quiet then
        nm := public.title_name(t);
        insert into public.notifications (user_id, kind, message)
        values (p_user, 'title_earned',
                format('칭호 ''%s''%s 얻었습니다. [마이페이지]에서 대표 칭호로 고를 수 있습니다.', nm, public.title_josa(nm, '을', '를')));
      end if;
    end if;
  end loop;
  return n;
end;
$f$;
create constraint trigger edit_proposals_kept_titles after insert on public.edit_proposals
  deferrable initially deferred for each row when (new.type = 'new_counter') execute function public.kept_titles_on_change();
commit;
select t.ok('되돌리기: grant_kept_titles가 076 본문(55a61ba9…), 제안 트리거·도감 줄 다시 있음, 다른 함수는 그대로',
  (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'public.grant_kept_titles(uuid, boolean)'::regprocedure) = '55a61ba9297a02073f7b09756c7d4360'
  and exists (select 1 from pg_trigger where tgname = 'edit_proposals_kept_titles')
  and exists (select 1 from public.title_catalog where key = 'first_upload' and permanent)
  and pg_temp.fn_fp() = :'fn77');

-- ===== 2. 076 규칙으로 데이터 쌓기 =====
--  A: 빌드 1개 → 탑신병자 + 첫 발자국, 대표 칭호 첫 발자국 / B: 공개 빌드 10개 → 탑신병자 + 첫 발자국 + 빌드 설계자, 대표 칭호 빌드 설계자
--  C: 옛 방식 새 상대법 제안 → 첫 발자국(알림을 읽음) / D: 숨김 빌드만 → 없음 / E: 한정판 「첫 발자국 기념」(비슷한 이름, 지우면 안 됨)
set role authenticated;
set request.jwt.claim.sub = :'A';
select create_matchup('Darius', 'Garen', t.build() || :'doc'::jsonb) as ma \gset
reset role;
begin;
alter table public.builds disable trigger builds_check_new;
select pg_temp.mk(:'B', 'approved', 10), pg_temp.mk(:'D', 'hidden', 2);
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
commit;
insert into public.edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Fiora', :'C', :'doc', t.build());
update public.notifications set read_at = now() where user_id = :'C' and kind = 'title_earned';
update public.profiles set main_title = 'first_upload' where id = :'A';
update public.profiles set main_title = 'builder' where id = :'B';
insert into public.title_catalog (key, name, how_to, kind, sort_order) values ('lim_foot', '첫 발자국 기념', '검사', 'limited', 1001);
insert into public.user_titles (user_id, title_key) values (:'E', 'lim_foot');
insert into public.notifications (user_id, kind, message)
values (:'E', 'title_earned', '칭호 ''첫 발자국 기념''을 얻었습니다. [마이페이지]에서 대표 칭호로 고를 수 있습니다.');
select t.ok('076 규칙: A·B·C 첫 발자국, D 없음, B 빌드 설계자, 첫 발자국 알림 3줄',
  pg_temp.has(:'A', 'first_upload') and pg_temp.has(:'B', 'first_upload') and pg_temp.has(:'C', 'first_upload') and not pg_temp.has(:'D', 'first_upload')
  and pg_temp.has(:'B', 'builder') and pg_temp.has(:'A', 'top_addict')
  and (select count(*) from public.notifications where kind = 'title_earned'
        and message = '칭호 ''첫 발자국''을 얻었습니다. [마이페이지]에서 대표 칭호로 고를 수 있습니다.') = 3);
select pg_temp.others() as oth0 \gset
select pg_temp.push_fp() as push0 \gset
select pg_temp.counts() as cnt0 \gset
select count(*) as notes_all0 from public.notifications \gset
select count(*) as calls0 from net.calls \gset

-- ===== 3. 077 본문 다시 실행 (077 파일의 begin/commit 사이 그대로) =====
begin;

do $$
begin
  if to_regprocedure('public.grant_kept_titles(uuid, boolean)') is null then
    raise exception '076이 아직 실행되지 않았습니다.';
  end if;
  if md5(replace((select prosrc from pg_proc where oid = 'public.grant_kept_titles(uuid, boolean)'::regprocedure), E'\r', ''))
     <> '55a61ba9297a02073f7b09756c7d4360' then
    raise exception 'grant_kept_titles 본문이 076과 다릅니다(이미 077을 실행했거나 다른 변경이 있음). 실행을 멈춥니다. check_remove_first_upload_before.sql 1번을 알려 주세요.';
  end if;
  if md5(replace((select prosrc from pg_proc where oid = 'public.sync_rewards(uuid, boolean)'::regprocedure), E'\r', ''))
     <> 'd31e09d02d8344c09ec4adc3a2a00992' then
    raise exception 'sync_rewards 본문이 076과 다릅니다. 실행을 멈춥니다.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1~4. 데이터 지우기 (대표 칭호 → 받은 줄 → 알림 → 도감 줄 순서: 도감 줄은 받은 줄이 없어야 지워진다)
-- ---------------------------------------------------------------------
do $$
declare
  n_main integer;
  n_owned integer;
  n_notes integer;
  n_cat integer;
begin
  update public.profiles set main_title = null where main_title = 'first_upload';
  get diagnostics n_main = row_count;
  delete from public.user_titles where title_key = 'first_upload';
  get diagnostics n_owned = row_count;
  delete from public.notifications
   where kind = 'title_earned'
     and message = '칭호 ''첫 발자국''을 얻었습니다. [마이페이지]에서 대표 칭호로 고를 수 있습니다.';
  get diagnostics n_notes = row_count;
  delete from public.title_catalog where key = 'first_upload';
  get diagnostics n_cat = row_count;
  raise notice '077: 대표 칭호 % 명 비움, 받은 칭호 % 줄, 알림 % 줄, 도감 % 줄을 지웠습니다.', n_main, n_owned, n_notes, n_cat;
end $$;

-- ---------------------------------------------------------------------
-- 5. grant_kept_titles: first_upload 조건을 뺀다 (나머지는 076 그대로)
-- ---------------------------------------------------------------------
create or replace function public.grant_kept_titles(p_user uuid, p_quiet boolean default false)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  t text;
  k integer;
  n integer := 0;
  nm text;
begin
  if p_user is null or not exists (select 1 from public.profiles where id = p_user and role <> 'admin') then
    return 0;  -- 탈퇴했거나 운영자 (칭호 없음)
  end if;
  foreach t in array array_remove(array[
    -- (077: 076의 「첫 발자국」 조건은 폐지)
    -- 빌드 설계자: 공개 빌드 수 (숨김·대기 빌드, 숨긴 상대법의 빌드 제외)
    case when (select count(*) from public.builds b join public.counters c on c.id = b.counter_id
                where b.author_id = p_user and b.status = 'approved' and c.status = 'approved')
              >= coalesce(public.xp_rule('title_builder'), 10)
         then 'builder' end
  ], null) loop
    -- 도감에서 지워졌거나 유지 칭호가 아니면 주지 않는다 (외래 키 오류로 빌드 등록이 실패하지 않게)
    continue when not exists (select 1 from public.title_catalog c where c.key = t and c.permanent);
    insert into public.user_titles (user_id, title_key) values (p_user, t) on conflict do nothing;
    get diagnostics k = row_count;
    if k > 0 then
      n := n + 1;
      if not p_quiet then
        nm := public.title_name(t);
        insert into public.notifications (user_id, kind, message)
        values (p_user, 'title_earned',
                format('칭호 ''%s''%s 얻었습니다. [마이페이지]에서 대표 칭호로 고를 수 있습니다.', nm, public.title_josa(nm, '을', '를')));
      end if;
    end if;
  end loop;
  return n;
end;
$$;
-- create or replace는 권한을 그대로 두지만, 076과 같게 한 번 더 확인한다
revoke all on function public.grant_kept_titles(uuid, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 6. 첫 발자국에만 쓰이던 트리거
-- ---------------------------------------------------------------------
drop trigger if exists edit_proposals_kept_titles on public.edit_proposals;

commit;

-- ===== 4. 결과 =====
select t.ok('first_upload: 도감 0 / 받은 줄 0 / 대표 칭호 0 / 그 문장의 알림 0',
  not exists (select 1 from public.title_catalog where key = 'first_upload')
  and not exists (select 1 from public.user_titles where title_key = 'first_upload')
  and not exists (select 1 from public.profiles where main_title = 'first_upload')
  and not exists (select 1 from public.notifications where kind = 'title_earned'
                   and message = '칭호 ''첫 발자국''을 얻었습니다. [마이페이지]에서 대표 칭호로 고를 수 있습니다.'));
select t.ok('지운 알림은 정확히 3줄(읽은 것 포함), 나머지 알림 수 그대로', (select count(*) from public.notifications) = :notes_all0 - 3);
select t.ok('A 대표 칭호는 비워짐, B 대표 칭호(빌드 설계자)는 그대로',
  (select main_title from public.profiles where id = :'A') is null and (select main_title from public.profiles where id = :'B') = 'builder');
select t.ok('다른 칭호의 받은 줄·대표 칭호·모든 다른 알림(비슷한 이름 「첫 발자국 기념」 포함)·빌드·도감·xp_rules가 한 줄도 안 바뀜',
  pg_temp.others() = :'oth0'
  and exists (select 1 from public.notifications where user_id = :'E' and message like '칭호 ''첫 발자국 기념''%')
  and pg_temp.has(:'E', 'lim_foot') and pg_temp.has(:'A', 'top_addict') and pg_temp.has(:'B', 'builder'));
select t.ok('grant_kept_titles만 077 본문(3370625…)으로, 나머지 함수 지문은 그대로(sync_rewards 포함)',
  (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'public.grant_kept_titles(uuid, boolean)'::regprocedure) = '3370625539c7ce4bd794a96b4609b03f'
  and pg_temp.fn_fp() = :'fn77'
  and (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'public.sync_rewards(uuid, boolean)'::regprocedure) = 'd31e09d02d8344c09ec4adc3a2a00992');
select t.ok('grant_kept_titles 모양·권한 그대로 (integer, security definer, search_path, 아무도 실행 못 함)',
  (select pg_get_function_result(oid) = 'integer' and prosecdef and proconfig = array['search_path=""'] and array_to_string(proacl, ',') = 'postgres=X/postgres'
     from pg_proc where oid = 'public.grant_kept_titles(uuid, boolean)'::regprocedure));
select t.ok('트리거: 제안 트리거 삭제, 빌드·상대법 트리거 그대로', not exists (select 1 from pg_trigger where tgname = 'edit_proposals_kept_titles')
  and (select count(*) from pg_trigger where tgname in ('builds_kept_titles', 'counters_kept_titles')) = 2);
select t.ok('쓰기 함수 103 / 첫 줄 검사 30 / 허용 목록 함수 73 / 읽기 함수 66 / 허용 목록 지문 그대로 (' || pg_temp.counts() || ')',
  pg_temp.counts() = :'cnt0' and pg_temp.counts() like '103/30/73/66/%');
select t.ok('모든 사람 × 모든 알림 종류의 푸시 판정 지문 그대로', pg_temp.push_fp() = :'push0');
select t.ok('지우는 동안 휴대폰 알림 호출 없음', (select count(*) from net.calls) = :calls0);

-- ===== 5. 077 뒤 동작 =====
begin;
alter table public.builds disable trigger builds_check_new;
select pg_temp.mk(:'D', 'approved', 1);
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
commit;
insert into public.edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Riven', :'E', :'doc', t.build());
select t.ok('처음 올려도(빌드·옛 제안) 첫 발자국 없음, 알림 없음', not pg_temp.has(:'D', 'first_upload') and not pg_temp.has(:'E', 'first_upload')
  and not exists (select 1 from public.notifications where message like '칭호 ''첫 발자국''을%'));
select t.fails('first_upload는 더 이상 받을 수 없음(도감에 없음 → 외래 키)',
  $$insert into public.user_titles (user_id, title_key) values ('00000000-0000-0000-0000-0000000000e4', 'first_upload')$$, 'user_titles_title_key_fkey');
begin;
alter table public.builds disable trigger builds_check_new;
select pg_temp.mk(:'D', 'approved', 9);
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
commit;
select t.ok('빌드 설계자는 그대로: D 공개 10개 → 받음 + 알림 1줄', pg_temp.has(:'D', 'builder')
  and (select count(*) from public.notifications where user_id = :'D' and message like '칭호 ''빌드 설계자''%') = 1);
select public.grant_kept_titles(:'B') as gb \gset
select t.ok('이미 받은 빌드 설계자는 다시 안 줌', :gb = 0 and (select count(*) from public.user_titles where user_id = :'B' and title_key = 'builder') = 1);
