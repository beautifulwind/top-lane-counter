-- =====================================================================
-- 065: 빌드 스킬 순서 상세 입력 (2026-11-22, SPEC 6-80)
--
-- 1. builds.skill_sequence: 1렙부터 찍는 스킬을 차례로 적은 글자 줄 ("QEWQQRE..."), Q/W/E/R 1~18글자, 없으면 null.
--    선마(max_skill Q/W/E)는 그대로 필수이고, 상세 순서는 선택 - 둘 다 쓸 수 있다.
--    1단 검사(표 규칙 builds_skill_sequence_format): 어느 길로 넣어도 Q/W/E/R 1~18글자만.
-- 2. 2단 검사(등록·수정·되돌리기): skill_sequence_problem(순서, 플레이할 챔피언)
--    기본 규칙 - Q·W·E 각 5번, R 3번(첫 R 6렙·두 번째 11렙·세 번째 16렙부터), Q·W·E는 그 레벨/2 올림 번까지.
--    예외 표 skill_sequence_mode(화면 src/lib/skillSequence.js SEQ_EXCEPTIONS와 같음):
--      hidden(상세 순서 받지 않음) - Aphelios / loose(형식만 검사) - Udyr, Jayce, Elise, Nidalee, Karma.
--    수정·되돌리기는 순서가 바뀐 때만 검사한다 (게임 규칙이 바뀌어도 옛 빌드의 다른 칸 수정이 막히지 않게).
-- 3. 수정 기록: wiki_snapshot에 skill_sequence -> 순서만 고쳐도 기록이 남고 되돌릴 수 있다 (065 전 기록은 키 없음 = 순서 없음).
--    "똑같은 빌드" 판정(build_signature)에는 넣지 않는다 -> 순서만 다른 빌드는 같은 빌드로 보고 막는다.
--    순서만 고치면 글만 고친 것처럼 패치 번호 그대로. 추천·기여자·수정 횟수 규칙은 그대로.
-- 4. 옛 앱(1.1 이하) 호환: edit_build에 skill_sequence 키가 아예 없으면 원래 순서를 그대로 둔다. 키가 null이면 지운다.
--    등록(create_matchup·create_build)은 wiki_insert_build로 넣으므로 그 함수만 바꾼다 (두 함수 본문은 그대로).
--    되돌리기는 안쪽 함수 revert_build_unchecked만 바꾼다 (revert_build는 운영자 확인 뒤 그것을 부른다).
-- 5. 기존 제안·승인 흐름(clean_build, build_json, build_signature)과 RLS·권한은 건드리지 않는다. 새 표·알림·pg_cron 없음.
--
-- 실행 전 supabase/scripts/check_skill_sequence_before.sql, 실행 뒤 check_skill_sequence_after.sql.
-- 064까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 실행한다. 두 번 실행해도 결과는 같다.
-- 반드시 웹 화면 push보다 "먼저" 실행한다 (새 화면은 builds.skill_sequence 칸을 읽는다 - 칸이 없으면 빌드를 못 불러온다).
-- 지금 화면(065 전)과 옛 앱은 이 칸을 모르고 보내지도 않으므로 SQL만 먼저 실행해도 그대로 동작한다.
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 064 상태로 돌아간다.
--    되돌릴 수 없는 것: 그동안 적은 스킬 순서는 지워진다. 수정 기록(build_revisions)의 내용에 남은 skill_sequence 키는
--    그대로 두지만 옛 함수는 그 키를 보지 않으므로 문제없다.
--     begin;
--     -- 1) 바꾼 함수를 064 상태(038·043 내용)로 (새 칸을 쓰지 않게 먼저)
--     create or replace function public.wiki_snapshot(b public.builds)
--     returns jsonb language sql stable set search_path = ''
--     as $$
--       select public.build_json(b) || jsonb_build_object(
--         'name', b.name, 'summary', b.summary, 'level_notes', b.level_notes, 'lane_cautions', coalesce(b.lane_cautions, ''));
--     $$;
--     create or replace function public.clean_wiki_build(p jsonb)
--     returns jsonb language plpgsql stable set search_path = ''
--     as $$
--     declare
--       b jsonb := public.clean_build(p);
--       d jsonb := public.clean_doc_content(jsonb_build_object(
--         'summary', p -> 'summary', 'level_notes', p -> 'level_notes', 'lane_cautions', p -> 'lane_cautions'));
--       nm text := nullif(btrim(coalesce(p ->> 'name', '')), '');
--     begin
--       if char_length(nm) > 20 then
--         raise exception '빌드 이름은 20자 이하로 적어 주세요.' using errcode = '23514';
--       end if;
--       return b || d || jsonb_build_object('name', nm);
--     end;
--     $$;
--     create or replace function public.wiki_insert_build(p_counter bigint, p_author uuid, c jsonb)
--     returns bigint language plpgsql security definer set search_path = ''
--     as $$
--     declare
--       nb public.builds;
--       spells text[] := array(select jsonb_array_elements_text(c -> 'summoner_spells'));
--       core text[] := array(select jsonb_array_elements_text(c -> 'core_items'));
--     begin
--       -- 바로 공개되는 줄은 트리거가 핵심 템트리·강타 검사를 건너뛰므로(예전 승인 빌드용 예외) 여기서 한다
--       perform public.check_core_items(core);
--       perform public.check_no_smite(spells);
--       insert into public.builds
--         (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch, status,
--          name, summary, level_notes, lane_cautions, wiki, updated_by)
--       values (
--         p_counter, p_author, c -> 'runes', spells, array(select jsonb_array_elements_text(c -> 'starting_items')), core,
--         c ->> 'max_skill', c ->> 'patch', 'approved',
--         c ->> 'name', c ->> 'summary', c -> 'level_notes', c ->> 'lane_cautions', true, p_author
--       )
--       returning * into nb;  -- check_new_build가 상대법 공개 여부·시작 골드·똑같은 공개 빌드를 검사한다
--       insert into public.build_revisions (build_id, counter_id, editor_id, kind, before, after, version)
--       values (nb.id, nb.counter_id, p_author, 'create', null, public.wiki_snapshot(nb), nb.version);
--       return nb.id;
--     end;
--     $$;
--     create or replace function public.edit_build(p_id bigint, p_version integer, p_build jsonb)
--     returns integer language plpgsql security definer set search_path = ''
--     as $$
--     declare
--       me uuid := public.board_writer();
--       b public.builds;
--       nb public.builds;
--       c jsonb;
--       before jsonb;
--       same_build boolean;
--     begin
--       select * into b from public.builds where id = p_id for update;
--       if not found then
--         raise exception '빌드를 찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       perform public.build_edit_check(b, me);  -- 043: 공개 여부·비회원 규칙 (잠금이 들어올 자리)
--       if p_version is distinct from b.version then
--         raise exception '다른 분이 먼저 수정했습니다. 최신 내용을 확인해 주세요.' using errcode = 'TL412';
--       end if;
--       c := public.clean_wiki_build(p_build);
--       before := public.wiki_snapshot(b);
--       if c - 'patch' = before - 'patch' then
--         raise exception '바뀐 내용이 없습니다.' using errcode = '23514';
--       end if;
--       same_build := c - 'patch' - 'name' - 'summary' - 'level_notes' - 'lane_cautions' = public.build_signature(b);
--       if not same_build and exists (
--         select 1 from public.builds x
--          where x.counter_id = b.counter_id and x.id <> b.id and x.status = 'approved'
--            and public.build_signature(x) = c - 'patch' - 'name' - 'summary' - 'level_notes' - 'lane_cautions'
--       ) then
--         raise exception '똑같은 빌드가 이미 공개돼 있습니다. 그 빌드를 추천해 주세요.' using errcode = '23514';
--       end if;
--       perform public.wiki_throttle('edit');
--
--       update public.builds
--          set runes = c -> 'runes',
--              summoner_spells = array(select jsonb_array_elements_text(c -> 'summoner_spells')),
--              starting_items = array(select jsonb_array_elements_text(c -> 'starting_items')),
--              core_items = array(select jsonb_array_elements_text(c -> 'core_items')),
--              max_skill = c ->> 'max_skill',
--              patch = case when same_build then b.patch else c ->> 'patch' end,  -- 글만 고치면 패치 그대로
--              name = c ->> 'name', summary = c ->> 'summary', level_notes = c -> 'level_notes', lane_cautions = c ->> 'lane_cautions',
--              version = b.version + 1, updated_at = now(), updated_by = me
--        where id = b.id
--        returning * into nb;  -- 핵심 템트리·강타·시작 골드는 바뀐 칸만 트리거가 검사
--       insert into public.build_revisions (build_id, counter_id, editor_id, kind, before, after, version)
--       values (b.id, b.counter_id, me, 'edit', before, public.wiki_snapshot(nb), nb.version);
--       if me is distinct from b.author_id then
--         insert into public.build_editors (build_id, user_id) values (b.id, me)
--         on conflict (build_id, user_id) do update set last_at = now(), edits = public.build_editors.edits + 1;
--       end if;
--       return nb.version;  -- 수정마다 알림은 보내지 않는다. 경험치도 없다
--     end;
--     $$;
--     create or replace function public.revert_build_unchecked(p_build bigint, p_revision bigint, p_version integer, p_note text)
--     returns jsonb language plpgsql security definer set search_path = ''
--     as $$
--     declare
--       me uuid := (select auth.uid());
--       note text := public.require_note(p_note, '되돌리는 사유');
--       b public.builds;
--       nb public.builds;
--       rv public.build_revisions;
--       c jsonb;
--       before jsonb;
--       same_build boolean;
--       e record;
--       ed public.build_editors;
--       removed integer := 0;
--     begin
--       select * into b from public.builds where id = p_build for update;
--       if not found then
--         raise exception '빌드를 찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       if b.status not in ('approved', 'hidden') then
--         raise exception '공개됐거나 숨긴 빌드만 되돌릴 수 있습니다.' using errcode = '23514';
--       end if;
--       if p_version is distinct from b.version then
--         raise exception '다른 분이 먼저 수정했습니다. 최신 내용을 확인해 주세요.' using errcode = 'TL412';
--       end if;
--       select * into rv from public.build_revisions where id = p_revision and build_id = b.id;
--       if not found then
--         raise exception '되돌릴 수정 기록을 찾지 못했습니다. (보관 기간이 지나 지워졌을 수 있습니다)' using errcode = 'P0002';
--       end if;
--       c := public.clean_wiki_build(rv.after);  -- 지금 규칙으로 다시 검사 (없어진 아이템 등은 여기나 트리거에서 오류)
--       before := public.wiki_snapshot(b);
--       if c = before then
--         raise exception '지금 내용과 같습니다.' using errcode = '23514';
--       end if;
--       same_build := c - 'patch' - 'name' - 'summary' - 'level_notes' - 'lane_cautions' = public.build_signature(b);
--       if not same_build and exists (
--         select 1 from public.builds x
--          where x.counter_id = b.counter_id and x.id <> b.id and x.status = 'approved'
--            and public.build_signature(x) = c - 'patch' - 'name' - 'summary' - 'level_notes' - 'lane_cautions'
--       ) then
--         raise exception '되돌리면 다른 공개 빌드와 똑같아집니다. 둘 중 하나를 숨겨 주세요.' using errcode = '23514';
--       end if;
--
--       update public.builds
--          set runes = c -> 'runes',
--              summoner_spells = array(select jsonb_array_elements_text(c -> 'summoner_spells')),
--              starting_items = array(select jsonb_array_elements_text(c -> 'starting_items')),
--              core_items = array(select jsonb_array_elements_text(c -> 'core_items')),
--              max_skill = c ->> 'max_skill', patch = c ->> 'patch',
--              name = c ->> 'name', summary = c ->> 'summary', level_notes = c -> 'level_notes', lane_cautions = c ->> 'lane_cautions',
--              version = b.version + 1, updated_at = now(), updated_by = me
--        where id = b.id
--        returning * into nb;  -- 편집 중이던 사람은 저장할 때 버전이 달라 TL412
--       insert into public.build_revisions (build_id, counter_id, editor_id, kind, before, after, version, revert_of)
--       values (b.id, b.counter_id, me, 'revert', before, public.wiki_snapshot(nb), nb.version, rv.id);
--
--       -- 기여자 정리: 되돌린 범위(기준 기록 뒤)의 수정만 한 사람은 빼고, 그 전에도 고친 사람은 횟수만 줄인다.
--       --   "그 전에도 고침" = 기여자 줄의 첫 기여 시각(first_at)이 범위의 첫 수정보다 앞섬.
--       --   (예전에 되돌려져 기여자에서 빠졌던 수정은 세지 않는다 — 빠질 때 줄이 지워지고 다음 수정 때 새로 생기므로)
--       for e in
--         select r.editor_id as uid, count(*)::integer as n, min(r.created_at) as first_in_range
--           from public.build_revisions r
--          where r.build_id = b.id and r.id > rv.id and r.kind in ('edit', 'migrate')
--            and r.editor_id is not null and r.editor_id is distinct from b.author_id
--          group by r.editor_id
--       loop
--         select * into ed from public.build_editors where build_id = b.id and user_id = e.uid for update;
--         continue when not found;
--         if ed.first_at < e.first_in_range then
--           update public.build_editors set edits = greatest(edits - e.n, 1) where build_id = b.id and user_id = e.uid;
--         else
--           delete from public.build_editors where build_id = b.id and user_id = e.uid;
--           removed := removed + 1;
--         end if;
--       end loop;
--
--       perform public.log_moderation('revert', 'build', b.id::text, note);
--       return jsonb_build_object('version', nb.version, 'removed_contributors', removed);  -- 알림·경험치 변화 없음
--     end;
--     $$;
--     -- 2) 새 함수와 칸 지우기
--     drop function if exists public.check_skill_sequence(text, bigint);
--     drop function if exists public.skill_sequence_problem(text, text);
--     drop function if exists public.skill_sequence_mode(text);
--     alter table public.builds drop constraint if exists builds_skill_sequence_format;
--     alter table public.builds drop column if exists skill_sequence;
--     commit;
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 새 칸 + 1단 형식 검사 (어느 길로 넣어도 Q·W·E·R 1~18글자만)
-- ---------------------------------------------------------------------
alter table public.builds add column if not exists skill_sequence text;
alter table public.builds drop constraint if exists builds_skill_sequence_format;
alter table public.builds add constraint builds_skill_sequence_format
  check (skill_sequence ~ '^[QWER]{1,18}$');
comment on column public.builds.skill_sequence is
  '스킬 찍는 순서 (065): 1렙부터 차례로 Q/W/E/R 1~18글자, 없으면 null. 선마(max_skill)와 따로 (둘 다 쓸 수 있음)';

-- ---------------------------------------------------------------------
-- 2. 2단 레벨 규칙 (화면 src/lib/skillSequence.js와 같은 규칙·같은 예외 표)
-- ---------------------------------------------------------------------
-- 챔피언(Data Dragon id)별 검사 방식: strict(기본 규칙) / loose(형식만) / hidden(상세 순서 받지 않음)
-- 예외 표가 실제 게임과 조금 달라도 정상 빌드를 막지 않게, 예외 챔피언은 레벨 규칙을 보지 않는다(loose).
-- 새 예외가 생기면 여기와 화면 SEQ_EXCEPTIONS에 한 줄씩 더한다.
create or replace function public.skill_sequence_mode(p_champion text)
returns text language sql immutable set search_path = ''
as $$
  select case p_champion
    when 'Aphelios' then 'hidden'  -- Q·W·E를 직접 찍지 않음
    when 'Udyr' then 'loose'       -- 궁이 따로 없고 네 스킬을 1렙부터
    when 'Jayce' then 'loose'      -- 변신(R)을 1렙부터
    when 'Elise' then 'loose'      -- 변신(R)을 1렙부터
    when 'Nidalee' then 'loose'    -- 변신(R)을 1렙부터
    when 'Karma' then 'loose'      -- 만트라(R)를 1렙부터
    else 'strict'
  end;
$$;

-- 고쳐야 할 점 (없으면 null). 기본 규칙: Q·W·E 각 5번, R 3번(6·11·16렙부터), Q·W·E는 레벨/2 올림까지
create or replace function public.skill_sequence_problem(p_seq text, p_champion text)
returns text language plpgsql immutable set search_path = ''
as $$
declare
  mode text := public.skill_sequence_mode(p_champion);
  lv integer;
  k text;
  n integer;
  cap integer;
  need integer;
begin
  if p_seq is null then
    return null;
  end if;
  if p_seq !~ '^[QWER]{1,18}$' then
    return E'스킬 순서는 Q\u00B7W\u00B7E\u00B7R만 1~18칸까지 적을 수 있습니다.';
  end if;
  if mode = 'hidden' then
    return '이 챔피언은 스킬을 직접 찍지 않아 상세 순서를 적을 수 없습니다.';
  end if;
  if mode = 'loose' then
    return null;
  end if;
  for lv in 1 .. char_length(p_seq) loop
    k := substr(p_seq, lv, 1);
    n := lv - char_length(replace(left(p_seq, lv), k, ''));  -- 이번 칸까지 k를 찍은 횟수
    if k = 'R' then
      if n > 3 then
        return format('스킬 순서 %s렙: R은 3번까지 찍을 수 있습니다.', lv);
      end if;
      need := (array[6, 11, 16])[n];
      if lv < need then
        return format('스킬 순서 %s렙: %sR은 %s렙부터 찍을 수 있습니다.',
          lv, case n when 1 then '' when 2 then '두 번째 ' else '세 번째 ' end, need);
      end if;
    else
      if n > 5 then
        return format('스킬 순서 %s렙: %s는 5번까지 찍을 수 있습니다.', lv, k);
      end if;
      cap := (lv + 1) / 2;
      if n > cap then
        return format('스킬 순서 %s렙: %s렙에는 %s를 %s번까지 찍을 수 있습니다.', lv, lv, k, cap);
      end if;
    end if;
  end loop;
  return null;
end;
$$;

-- 규칙에 안 맞으면 오류 (상대법 id로 플레이할 챔피언을 찾는다)
create or replace function public.check_skill_sequence(p_seq text, p_counter bigint)
returns void language plpgsql stable security definer set search_path = ''
as $$
declare
  problem text := public.skill_sequence_problem(
    p_seq, (select counter_champion from public.counters where id = p_counter));
begin
  if problem is not null then
    raise exception '%', problem using errcode = '23514';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. 수정 기록 내용에 스킬 순서 (순서만 고쳐도 기록·되돌리기). 065 전 기록에는 이 키가 없다 = 순서 없음
-- ---------------------------------------------------------------------
create or replace function public.wiki_snapshot(b public.builds)
returns jsonb language sql stable set search_path = ''
as $$
  select public.build_json(b) || jsonb_build_object(
    'name', b.name, 'summary', b.summary, 'level_notes', b.level_notes, 'lane_cautions', coalesce(b.lane_cautions, ''),
    'skill_sequence', b.skill_sequence);
$$;

-- 화면이 보낸 빌드 검사 + 스킬 순서 형식 (레벨 규칙은 챔피언을 아는 곳에서 check_skill_sequence)
-- 칸이 없거나 null·빈 글자면 null. 옛 앱이 칸을 아예 안 보냈는지는 edit_build가 p_build ? 'skill_sequence'로 따로 본다
create or replace function public.clean_wiki_build(p jsonb)
returns jsonb language plpgsql stable set search_path = ''
as $$
declare
  b jsonb := public.clean_build(p);
  d jsonb := public.clean_doc_content(jsonb_build_object(
    'summary', p -> 'summary', 'level_notes', p -> 'level_notes', 'lane_cautions', p -> 'lane_cautions'));
  nm text := nullif(btrim(coalesce(p ->> 'name', '')), '');
  sq jsonb := p -> 'skill_sequence';
  seq text;
begin
  if char_length(nm) > 20 then
    raise exception '빌드 이름은 20자 이하로 적어 주세요.' using errcode = '23514';
  end if;
  if sq is not null and jsonb_typeof(sq) <> 'null' then
    if jsonb_typeof(sq) <> 'string' then
      raise exception '스킬 순서 형식이 잘못됐습니다.' using errcode = '23514';
    end if;
    seq := nullif(sq #>> '{}', '');
    if seq !~ '^[QWER]{1,18}$' then
      raise exception E'스킬 순서는 Q\u00B7W\u00B7E\u00B7R만 1~18칸까지 적을 수 있습니다.' using errcode = '23514';
    end if;
  end if;
  return b || d || jsonb_build_object('name', nm, 'skill_sequence', seq);
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 등록 (create_matchup·create_build가 모두 이 함수로 넣는다 -> 두 함수는 그대로)
-- ---------------------------------------------------------------------
create or replace function public.wiki_insert_build(p_counter bigint, p_author uuid, c jsonb)
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
  perform public.check_skill_sequence(c ->> 'skill_sequence', p_counter);  -- 065: 플레이할 챔피언 기준 레벨 규칙
  insert into public.builds
    (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch, status,
     name, summary, level_notes, lane_cautions, wiki, updated_by, skill_sequence)
  values (
    p_counter, p_author, c -> 'runes', spells, array(select jsonb_array_elements_text(c -> 'starting_items')), core,
    c ->> 'max_skill', c ->> 'patch', 'approved',
    c ->> 'name', c ->> 'summary', c -> 'level_notes', c ->> 'lane_cautions', true, p_author, c ->> 'skill_sequence'
  )
  returning * into nb;  -- check_new_build가 상대법 공개 여부·시작 골드·똑같은 공개 빌드를 검사한다
  insert into public.build_revisions (build_id, counter_id, editor_id, kind, before, after, version)
  values (nb.id, nb.counter_id, p_author, 'create', null, public.wiki_snapshot(nb), nb.version);
  return nb.id;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. 수정: 칸을 안 보내면(옛 앱 1.1 이하) 원래 순서 그대로, null을 보내면 지움. 순서가 바뀐 때만 레벨 규칙 검사.
--    "똑같은 빌드"·패치 유지 판정(build_signature)에는 순서를 넣지 않는다 -> 순서만 고치면 글만 고친 것과 같다
-- ---------------------------------------------------------------------
create or replace function public.edit_build(p_id bigint, p_version integer, p_build jsonb)
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
  perform public.build_edit_check(b, me);  -- 043: 공개 여부·비회원 규칙 (잠금이 들어올 자리)
  if p_version is distinct from b.version then
    raise exception '다른 분이 먼저 수정했습니다. 최신 내용을 확인해 주세요.' using errcode = 'TL412';
  end if;
  c := public.clean_wiki_build(p_build);
  if not (p_build ? 'skill_sequence') then  -- 065: 옛 앱은 이 칸을 모른다 -> 지우지 않고 그대로
    c := c || jsonb_build_object('skill_sequence', b.skill_sequence);
  end if;
  if (c ->> 'skill_sequence') is distinct from b.skill_sequence then
    perform public.check_skill_sequence(c ->> 'skill_sequence', b.counter_id);
  end if;
  before := public.wiki_snapshot(b);
  if c - 'patch' = before - 'patch' then
    raise exception '바뀐 내용이 없습니다.' using errcode = '23514';
  end if;
  same_build := c - 'patch' - 'name' - 'summary' - 'level_notes' - 'lane_cautions' - 'skill_sequence' = public.build_signature(b);
  if not same_build and exists (
    select 1 from public.builds x
     where x.counter_id = b.counter_id and x.id <> b.id and x.status = 'approved'
       and public.build_signature(x) = c - 'patch' - 'name' - 'summary' - 'level_notes' - 'lane_cautions' - 'skill_sequence'
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
         patch = case when same_build then b.patch else c ->> 'patch' end,  -- 글·스킬 순서만 고치면 패치 그대로
         name = c ->> 'name', summary = c ->> 'summary', level_notes = c -> 'level_notes', lane_cautions = c ->> 'lane_cautions',
         skill_sequence = c ->> 'skill_sequence',
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

-- ---------------------------------------------------------------------
-- 6. 되돌리기 (운영자, revert_build가 부르는 안쪽 함수). 기록의 순서로 되돌림 — 065 전 기록이면 순서 없음(null).
--    순서가 바뀌는 때만 지금 규칙으로 검사
-- ---------------------------------------------------------------------
create or replace function public.revert_build_unchecked(p_build bigint, p_revision bigint, p_version integer, p_note text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  note text := public.require_note(p_note, '되돌리는 사유');
  b public.builds;
  nb public.builds;
  rv public.build_revisions;
  c jsonb;
  before jsonb;
  same_build boolean;
  e record;
  ed public.build_editors;
  removed integer := 0;
begin
  select * into b from public.builds where id = p_build for update;
  if not found then
    raise exception '빌드를 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if b.status not in ('approved', 'hidden') then
    raise exception '공개됐거나 숨긴 빌드만 되돌릴 수 있습니다.' using errcode = '23514';
  end if;
  if p_version is distinct from b.version then
    raise exception '다른 분이 먼저 수정했습니다. 최신 내용을 확인해 주세요.' using errcode = 'TL412';
  end if;
  select * into rv from public.build_revisions where id = p_revision and build_id = b.id;
  if not found then
    raise exception '되돌릴 수정 기록을 찾지 못했습니다. (보관 기간이 지나 지워졌을 수 있습니다)' using errcode = 'P0002';
  end if;
  c := public.clean_wiki_build(rv.after);  -- 지금 규칙으로 다시 검사 (없어진 아이템 등은 여기나 트리거에서 오류)
  if (c ->> 'skill_sequence') is distinct from b.skill_sequence then
    perform public.check_skill_sequence(c ->> 'skill_sequence', b.counter_id);
  end if;
  before := public.wiki_snapshot(b);
  if c = before then
    raise exception '지금 내용과 같습니다.' using errcode = '23514';
  end if;
  same_build := c - 'patch' - 'name' - 'summary' - 'level_notes' - 'lane_cautions' - 'skill_sequence' = public.build_signature(b);
  if not same_build and exists (
    select 1 from public.builds x
     where x.counter_id = b.counter_id and x.id <> b.id and x.status = 'approved'
       and public.build_signature(x) = c - 'patch' - 'name' - 'summary' - 'level_notes' - 'lane_cautions' - 'skill_sequence'
  ) then
    raise exception '되돌리면 다른 공개 빌드와 똑같아집니다. 둘 중 하나를 숨겨 주세요.' using errcode = '23514';
  end if;

  update public.builds
     set runes = c -> 'runes',
         summoner_spells = array(select jsonb_array_elements_text(c -> 'summoner_spells')),
         starting_items = array(select jsonb_array_elements_text(c -> 'starting_items')),
         core_items = array(select jsonb_array_elements_text(c -> 'core_items')),
         max_skill = c ->> 'max_skill', patch = c ->> 'patch',
         name = c ->> 'name', summary = c ->> 'summary', level_notes = c -> 'level_notes', lane_cautions = c ->> 'lane_cautions',
         skill_sequence = c ->> 'skill_sequence',
         version = b.version + 1, updated_at = now(), updated_by = me
   where id = b.id
   returning * into nb;  -- 편집 중이던 사람은 저장할 때 버전이 달라 TL412
  insert into public.build_revisions (build_id, counter_id, editor_id, kind, before, after, version, revert_of)
  values (b.id, b.counter_id, me, 'revert', before, public.wiki_snapshot(nb), nb.version, rv.id);

  -- 기여자 정리: 되돌린 범위(기준 기록 뒤)의 수정만 한 사람은 빼고, 그 전에도 고친 사람은 횟수만 줄인다.
  --   "그 전에도 고침" = 기여자 줄의 첫 기여 시각(first_at)이 범위의 첫 수정보다 앞섬.
  --   (예전에 되돌려져 기여자에서 빠졌던 수정은 세지 않는다 — 빠질 때 줄이 지워지고 다음 수정 때 새로 생기므로)
  for e in
    select r.editor_id as uid, count(*)::integer as n, min(r.created_at) as first_in_range
      from public.build_revisions r
     where r.build_id = b.id and r.id > rv.id and r.kind in ('edit', 'migrate')
       and r.editor_id is not null and r.editor_id is distinct from b.author_id
     group by r.editor_id
  loop
    select * into ed from public.build_editors where build_id = b.id and user_id = e.uid for update;
    continue when not found;
    if ed.first_at < e.first_in_range then
      update public.build_editors set edits = greatest(edits - e.n, 1) where build_id = b.id and user_id = e.uid;
    else
      delete from public.build_editors where build_id = b.id and user_id = e.uid;
      removed := removed + 1;
    end if;
  end loop;

  perform public.log_moderation('revert', 'build', b.id::text, note);
  return jsonb_build_object('version', nb.version, 'removed_contributors', removed);  -- 알림·경험치 변화 없음
end;
$$;

-- ---------------------------------------------------------------------
-- 7. 권한: 새 함수는 아무도 직접 못 부른다 (안쪽에서만). 바꾼 함수는 create or replace라 원래 권한 그대로
-- ---------------------------------------------------------------------
revoke execute on function public.skill_sequence_mode(text) from public, anon, authenticated;
revoke execute on function public.skill_sequence_problem(text, text) from public, anon, authenticated;
revoke execute on function public.check_skill_sequence(text, bigint) from public, anon, authenticated;

commit;
