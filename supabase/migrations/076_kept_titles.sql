-- =====================================================================
-- 076: 칭호 개편 - 한 번 얻으면 유지하는 활동 칭호 2개 (2026-11-25, SPEC 6-109, 1.3 패치 2-C)
--      칸 1개 + 설정값 1줄 + 도감 2줄 + 내부 함수 2개(실행 권한 없음) + 트리거 3개 + 기존 함수 1개(sync_rewards) 본문 한 줄.
--
-- 새 칭호 (도감 title_catalog, 종류 activity = 지금 활동 칭호 6개와 같은 칸에 보이고 대표 칭호로 고를 수 있음):
--   first_upload 「첫 발자국」 : 상대법 또는 빌드를 처음 올림 (대기·공개·거절·재검토 요청 모두 "올림", 숨김 처리된 것만 세지 않음)
--   builder      「빌드 설계자」: 공개 빌드 xp_rules.title_builder(10)개
--                 공개 빌드 = builds.status = 'approved' and counters.status = 'approved' (075 member_page·장인 페이지와 같은 기준, 숨김 제외)
--   두 칭호는 title_catalog.permanent = true: 한 번 얻으면 나중에 빌드를 지우거나 숨겨도 회수하지 않는다.
--   같은 사람이 두 번 받지 않는다: user_titles 기본 키 (user_id, title_key) + insert ... on conflict do nothing.
--   운영자(role admin)는 지금처럼 칭호가 없다(sync_rewards·user_titles_skip_operator와 같음).
--
-- 기존 칭호 체계와의 관계 = 병행 (대체 아님). 기존 활동 6개·장인·한정판, 이미 준 칭호·대표 칭호·알림은 그대로 둔다(지우지 않음).
--   기존 6개는 sync_rewards가 조건이 깨지면 회수하고, 새 2개는 회수하지 않는 점만 다르다.
--
-- 알림: 기존 종류 title_earned(「칭호 'X'를 얻었습니다. [마이페이지]에서 대표 칭호로 고를 수 있습니다.」, sync_rewards와 같은 문장)를
--   앱 안 알림 목록에 넣는다. title_earned는 push_group = null(묶음 없음) → push_wanted = false → 휴대폰 알림이 나가지 않는다.
--   push_group·push_wanted·push_on_notification은 고치지 않는다(새 알림 종류·새 묶음 없음 → 기존 푸시 판정 그대로).
--
-- 언제 주나 (트랜잭션 끝, 014의 보상 트리거와 같은 deferrable 방식 - 함수가 여러 표를 바꿔도 최종 상태로 판단):
--   builds 새 줄·상태/작성자/상대법 바뀜 → 그 작성자 / counters 새 줄·상태 바뀜 → 제안자 + 그 상대법의 빌드 작성자 전원 /
--   edit_proposals 새 줄(새 상대법 제안) → 제안자.  지우기(delete)에는 반응하지 않는다(회수 없음).
-- 소급: 이 파일 끝에서 운영자가 아닌 모든 사람에게 한 번 실행한다(조건을 이미 채운 기존 사용자도 받고, 알림도 한 줄씩 - 푸시 없음).
--   확인: check_kept_titles_before.sql이 받을 사람 수를 미리 세고, check_kept_titles_after.sql이 실제로 받은 수와 맞는지 본다.
--
-- 고친 기존 함수 (1개): sync_rewards(uuid, boolean) - 본문 한 줄만(053과 같은 replace 방식, 정확히 한 번 나와야 바꿈).
--   왜: sync_rewards는 "지금 조건에 맞지 않는 활동 칭호"를 회수한다. 새 2개도 활동 칭호(화면·대표 칭호 규칙을 그대로 쓰려고)라
--       그대로 두면 다음 계산 때 회수된다. 회수 반복문에 "and not c.permanent"를 더해 한 번 얻으면 유지하는 칭호를 뺀다.
--   전: for t in select ut.title_key ... where ut.user_id = p_user and c.kind = 'activity' and not (ut.title_key = any (want)) loop  -- 053: 활동 칭호만 회수
--   후: for t in select ut.title_key ... where ut.user_id = p_user and c.kind = 'activity' and not c.permanent and not (ut.title_key = any (want)) loop  -- 053: 활동 칭호만 회수, 076: 유지 칭호 제외
--   기존 6개는 permanent = false라 지급·회수 결과가 전과 같다. 이름·인자·반환·보안·search_path·권한 그대로.
--
-- 바꾸지 않는 것: 다른 기존 함수 전부(push_group·push_wanted·title_name·my_title_book·public_title_info·member_page 포함), 기존 표 줄,
--   기존 트리거·정책·권한. 새 함수 2개는 실행 권한을 모두 회수(anon·authenticated·public) → 쓰기 함수 103 / 30 / 73, 읽기 함수 수 그대로.
-- 옛 앱 1.1·1.2: 새 칭호는 activity라 칭호판에 칭호로 보이고(이름·얻는 방법은 DB에서 읽음), 대표로 고를 수 있다. 알림도 기존 종류.
--   기존 6개처럼 칭호별 색(CSS)이 없어 기본 훈장 색으로 보인다.
--
-- 실행 전 supabase/scripts/check_kept_titles_before.sql, 실행 뒤 check_kept_titles_after.sql.
-- 075까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 075 상태로 돌아간다.
--    !! 새 칭호 2개를 받은 기록(user_titles)과 그 칭호를 대표 칭호로 단 것(대표 칭호는 비워짐), 그 칭호의 title_earned 알림은 지워진다.
--    sync_rewards는 아래 replace로 076 전 본문(053 줄)으로 돌아간다. 되돌린 뒤 check_kept_titles_before.sql 1번이 「075 본문」이면 정상.
--     begin;
--     drop trigger if exists builds_kept_titles on public.builds;
--     drop trigger if exists counters_kept_titles on public.counters;
--     drop trigger if exists edit_proposals_kept_titles on public.edit_proposals;
--     drop function if exists public.kept_titles_on_change();
--     drop function if exists public.grant_kept_titles(uuid, boolean);
--     do $r$
--     declare
--       old_def text := pg_get_functiondef('public.sync_rewards'::regproc);
--       new_def text;
--     begin
--       new_def := replace(old_def,
--         $s$and c.kind = 'activity' and not c.permanent and not (ut.title_key = any (want)) loop  -- 053: 활동 칭호만 회수, 076: 유지 칭호 제외$s$,
--         $s$and c.kind = 'activity' and not (ut.title_key = any (want)) loop  -- 053: 활동 칭호만 회수$s$);
--       if new_def = old_def then
--         raise exception 'sync_rewards에서 되돌릴 부분을 찾지 못했습니다.';
--       end if;
--       execute new_def;
--     end $r$;
--     delete from public.notifications where kind = 'title_earned'
--        and (message like '칭호 ''첫 발자국''%' or message like '칭호 ''빌드 설계자''%');
--     delete from public.user_titles where title_key in ('first_upload', 'builder');  -- 대표 칭호였으면 외래 키가 비운다
--     delete from public.title_catalog where key in ('first_upload', 'builder');
--     alter table public.title_catalog drop column if exists permanent;
--     delete from public.xp_rules where key = 'title_builder';
--     commit;
-- =====================================================================
begin;

do $$
begin
  if to_regprocedure('public.member_page(text, integer)') is null then
    raise exception '075가 아직 실행되지 않았습니다. 075를 먼저 실행해 주세요.';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'title_catalog' and column_name = 'permanent')
     or exists (select 1 from public.title_catalog where key in ('first_upload', 'builder'))
     or exists (select 1 from public.xp_rules where key = 'title_builder') then
    raise exception '076을 이미 실행했습니다.';
  end if;
  -- 076 전 sync_rewards 본문(마지막으로 고친 곳 이후 그대로인 본문)일 때만 (CR 뺀 지문)
  if md5(replace((select prosrc from pg_proc where oid = 'public.sync_rewards(uuid, boolean)'::regprocedure), E'\r', ''))
     <> 'c405f7913721afcaf02a560d0427dd40' then
    raise exception 'sync_rewards 본문이 예상(c405f791…)과 다릅니다. 실행을 멈춥니다. check_kept_titles_before.sql 1번을 알려 주세요.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. 설정값 / 도감 칸 / 도감 2줄
-- ---------------------------------------------------------------------
insert into public.xp_rules (key, value, note)
values ('title_builder', 10, '빌드 설계자(076): 공개 빌드 수 (숨김 제외, 한 번 얻으면 유지)');

alter table public.title_catalog add column permanent boolean not null default false;
comment on column public.title_catalog.permanent is
  '076: true면 한 번 얻으면 유지(sync_rewards가 회수하지 않음). grant_kept_titles가 조건을 채우면 준다';

insert into public.title_catalog (key, name, how_to, kind, equippable, permanent, sort_order) values
  ('first_upload', '첫 발자국',   '상대법 또는 빌드를 처음 올리기 (한 번 얻으면 유지)', 'activity', true, true, 5),
  ('builder',      '빌드 설계자', '공개 빌드 {n}개 (숨김 처리된 빌드는 세지 않음, 한 번 얻으면 유지)', 'activity', true, true, 65);

-- ---------------------------------------------------------------------
-- 2. sync_rewards: 회수 반복문에서 유지 칭호를 뺀다 (지금 본문에서 한 줄만. 정확히 한 번 나와야 바꾼다)
-- ---------------------------------------------------------------------
do $$
declare
  old_def text := pg_get_functiondef('public.sync_rewards'::regproc);
  target text := $s$and c.kind = 'activity' and not (ut.title_key = any (want)) loop  -- 053: 활동 칭호만 회수$s$;
  repl text := $s$and c.kind = 'activity' and not c.permanent and not (ut.title_key = any (want)) loop  -- 053: 활동 칭호만 회수, 076: 유지 칭호 제외$s$;
  n integer;
begin
  n := (char_length(old_def) - char_length(replace(old_def, target, ''))) / char_length(target);
  if n <> 1 then
    raise exception 'sync_rewards에서 바꿀 줄이 %번 나왔습니다(1번이어야 함). 실행을 멈춥니다.', n;
  end if;
  execute replace(old_def, target, repl);
end $$;

-- ---------------------------------------------------------------------
-- 3. 유지 칭호 주기 (내부 함수 - 클라이언트는 부를 수 없음). 돌려주는 값: 새로 준 칭호 수
-- ---------------------------------------------------------------------
create function public.grant_kept_titles(p_user uuid, p_quiet boolean default false)
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
$$;
comment on function public.grant_kept_titles(uuid, boolean) is
  '076 유지 칭호(title_catalog.permanent) 주기 - 조건을 채웠고 아직 없으면 user_titles + title_earned 알림(푸시 없음). 회수하지 않음';
revoke all on function public.grant_kept_titles(uuid, boolean) from public, anon, authenticated;

create function public.kept_titles_on_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  u uuid;
begin
  if tg_table_name = 'builds' then
    perform public.grant_kept_titles(new.author_id);
  elsif tg_table_name = 'edit_proposals' then
    perform public.grant_kept_titles(new.proposer_id);
  elsif tg_table_name = 'counters' then
    for u in
      select new.proposed_by
      union select b.author_id from public.builds b where b.counter_id = new.id
    loop
      perform public.grant_kept_titles(u);
    end loop;
  end if;
  return null;
end;
$$;
revoke all on function public.kept_titles_on_change() from public, anon, authenticated;

create constraint trigger builds_kept_titles after insert or update of status, author_id, counter_id on public.builds
  deferrable initially deferred for each row execute function public.kept_titles_on_change();
create constraint trigger counters_kept_titles after insert or update of status on public.counters
  deferrable initially deferred for each row execute function public.kept_titles_on_change();
create constraint trigger edit_proposals_kept_titles after insert on public.edit_proposals
  deferrable initially deferred for each row when (new.type = 'new_counter') execute function public.kept_titles_on_change();

-- ---------------------------------------------------------------------
-- 4. 소급: 이미 조건을 채운 사람 (운영자 제외, 알림 한 줄씩 - 푸시 없음)
-- ---------------------------------------------------------------------
do $$
declare
  u uuid;
  n integer := 0;
  g integer := 0;
begin
  for u in select id from public.profiles where role <> 'admin' order by created_at, id loop
    g := g + public.grant_kept_titles(u);
    n := n + 1;
  end loop;
  raise notice '076 소급: %명을 확인해 칭호 %개를 줬습니다.', n, g;
end $$;

commit;
