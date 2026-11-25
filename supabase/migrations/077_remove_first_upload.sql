-- =====================================================================
-- 077: 칭호 「첫 발자국」(first_upload) 완전 삭제 (2026-11-25, SPEC 6-110, 1.3 패치 칭호 정리)
--      076의 「첫 칭호」 규칙을 폐지한다. 「빌드 설계자」(builder, 공개 빌드 xp_rules.title_builder개)는 그대로 동작한다.
--
-- 지우는 것 (데이터 - 되살릴 수 없음):
--   1. profiles.main_title = 'first_upload' → null (대표 칭호 비움)
--   2. user_titles의 first_upload 줄 전부
--   3. 그 칭호 획득 알림: kind = 'title_earned' 이고 message가 076이 만든 문장과 "정확히" 같은 줄
--        「칭호 '첫 발자국'을 얻었습니다. [마이페이지]에서 대표 칭호로 고를 수 있습니다.」
--      알림 표에는 칭호 키 칸이 없다(id·user_id·kind·proposal_id·message·created_at·read_at·build_id·post_id·counter_id).
--      그래서 문장으로만 구분한다. 문장이 정확히 같아야 지우므로 다른 칭호(기존 6개·빌드 설계자·한정판)의 알림은 지워지지 않는다.
--      first_upload는 회수되지 않는 칭호라 title_revoked 알림은 원래 없다(실행 전 확인 3번).
--   4. title_catalog의 first_upload 줄
-- 바꾸는 것 (로직):
--   5. grant_kept_titles(uuid, boolean) 본문: first_upload를 주는 조건(case 한 덩어리)을 뺀다. 빌드 설계자 조건·중복 방지·알림 문장·
--      도감 확인·운영자 제외는 076 그대로. 이름·인자·반환·volatile·security definer·search_path·권한(실행 권한 없음)·소유자 그대로.
--      왜: 도감 줄만 지워도 함수의 "도감에 없으면 주지 않음" 줄 때문에 더는 주지 않지만, 나중에 같은 키로 도감 줄을 다시 넣으면
--          되살아나고 빌드 등록 때마다 쓸모없는 조회를 하므로 조건 자체를 뺀다.
--   6. 트리거 edit_proposals_kept_titles 삭제: 옛 방식 새 상대법 제안은 첫 발자국에만 쓰였다(제안은 공개 빌드를 만들지 않음).
--      builds_kept_titles·counters_kept_titles(빌드 설계자용)와 kept_titles_on_change()는 그대로 둔다
--      (kept_titles_on_change의 edit_proposals 갈래는 더는 불리지 않음 - 본문을 고치지 않으려고 남김).
-- 그대로인 것: sync_rewards(076의 「유지 칭호 제외」 줄 - builder가 있으므로), title_catalog.permanent 칸, xp_rules(first_upload 전용 값은 원래 없음),
--   기존 활동 칭호 6개·builder·한정판의 받은 줄·알림, push 함수(title_earned는 원래 푸시 없음), 쓰기 함수 103/30/73, 읽기 함수 66.
-- 옛 앱 1.1·1.2: 칭호 키를 코드에 고정하지 않고(고정 목록은 기존 6개뿐) 도감·public_title_info에서 읽으므로 줄이 빠지면 칭호판에서 사라질 뿐이다.
--   대표 칭호를 비우므로 닉네임 옆 배지도 없어진다(모르는 키를 남기지 않음).
--
-- 실행 전 supabase/scripts/check_remove_first_upload_before.sql, 실행 뒤 check_remove_first_upload_after.sql.
-- 076까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다. 실행 결과 NOTICE에 지운 수가 나온다.
--
-- >> 되돌리기 (rollback) - SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). "로직"만 076 상태로 돌아간다.
--    !! 지운 데이터(받은 칭호 줄·earned_at, 대표 칭호, 알림)는 복구할 수 없다(백업이 없다).
--       로직을 되돌린 뒤 조건을 채운 사람에게 다시 주려면 맨 끝의 소급 블록을 함께 실행한다(새 획득 시각·새 알림으로 다시 생김).
--     begin;
--     insert into public.title_catalog (key, name, how_to, kind, equippable, permanent, sort_order)
--     values ('first_upload', '첫 발자국', '상대법 또는 빌드를 처음 올리기 (한 번 얻으면 유지)', 'activity', true, true, 5);
--     create or replace function public.grant_kept_titles(p_user uuid, p_quiet boolean default false)
--     returns integer
--     language plpgsql security definer set search_path = ''
--     as $f$
--     declare
--       t text;
--       k integer;
--       n integer := 0;
--       nm text;
--     begin
--       if p_user is null or not exists (select 1 from public.profiles where id = p_user and role <> 'admin') then
--         return 0;  -- 탈퇴했거나 운영자 (칭호 없음)
--       end if;
--       foreach t in array array_remove(array[
--         -- 첫 발자국: 상대법 또는 빌드를 올린 적이 있음 (숨김 처리된 것은 세지 않음)
--         case when exists (select 1 from public.builds b where b.author_id = p_user and b.status <> 'hidden')
--                or exists (select 1 from public.counters c where c.proposed_by = p_user and c.status <> 'hidden')
--                or exists (select 1 from public.edit_proposals ep
--                            where ep.proposer_id = p_user and ep.type = 'new_counter' and ep.status <> 'revoked')
--              then 'first_upload' end,
--         -- 빌드 설계자: 공개 빌드 수 (숨김·대기 빌드, 숨긴 상대법의 빌드 제외)
--         case when (select count(*) from public.builds b join public.counters c on c.id = b.counter_id
--                     where b.author_id = p_user and b.status = 'approved' and c.status = 'approved')
--                   >= coalesce(public.xp_rule('title_builder'), 10)
--              then 'builder' end
--       ], null) loop
--         -- 도감에서 지워졌거나 유지 칭호가 아니면 주지 않는다 (외래 키 오류로 빌드 등록이 실패하지 않게)
--         continue when not exists (select 1 from public.title_catalog c where c.key = t and c.permanent);
--         insert into public.user_titles (user_id, title_key) values (p_user, t) on conflict do nothing;
--         get diagnostics k = row_count;
--         if k > 0 then
--           n := n + 1;
--           if not p_quiet then
--             nm := public.title_name(t);
--             insert into public.notifications (user_id, kind, message)
--             values (p_user, 'title_earned',
--                     format('칭호 ''%s''%s 얻었습니다. [마이페이지]에서 대표 칭호로 고를 수 있습니다.', nm, public.title_josa(nm, '을', '를')));
--           end if;
--         end if;
--       end loop;
--       return n;
--     end;
--     $f$;
--     create constraint trigger edit_proposals_kept_titles after insert on public.edit_proposals
--       deferrable initially deferred for each row when (new.type = 'new_counter') execute function public.kept_titles_on_change();
--     -- (선택) 소급: 조건을 채운 사람에게 다시 주기 - 알림도 다시 생긴다(푸시 없음)
--     do $r$ declare u uuid; begin
--       for u in select id from public.profiles where role <> 'admin' order by created_at, id loop perform public.grant_kept_titles(u); end loop;
--     end $r$;
--     commit;
--    되돌린 뒤 grant_kept_titles 지문(CR 뺌)이 55a61ba9297a02073f7b09756c7d4360이면 076 본문이다(check_remove_first_upload_before.sql 1번).
-- =====================================================================
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
