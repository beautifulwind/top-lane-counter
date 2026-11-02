-- =====================================================================
-- 레벨별 딜교법 필수 레벨: 1/2/3/6/9/11 → 1/2/3/6
-- - 9·11레벨은 필수가 아니고 기본 칸도 없다. 다른 레벨(4·5·7 …)처럼 원하면 추가할 수 있다 (1~18).
-- - 이미 있는 문서·제안·수정 기록의 9·11레벨 내용은 그대로 둔다 (추가 레벨로 보인다).
--   지우고 싶으면 문서 수정 제안에서 [9레벨 칸 빼기]로 뺀다.
-- 009_counter_needs_build.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. matchup_docs.level_notes 표 제약 (schema.sql의 이름 없는 check)을 내용으로 찾아 바꾼다
-- ---------------------------------------------------------------------
do $$
declare
  r record;
  n int := 0;
begin
  for r in
    select conname
    from pg_constraint
    where contype = 'c'
      and conrelid = 'public.matchup_docs'::regclass
      and pg_get_constraintdef(oid) ~ 'level_notes \?&'
  loop
    execute format('alter table public.matchup_docs drop constraint %I', r.conname);
    n := n + 1;
  end loop;
  if n <> 1 then
    raise exception 'matchup_docs의 level_notes 제약을 찾지 못했어요 (찾은 개수: %)', n;
  end if;
end;
$$;

alter table public.matchup_docs
  add constraint matchup_docs_level_notes_check
  check (jsonb_typeof(level_notes) = 'object' and level_notes ?& array['1', '2', '3', '6']);
comment on column public.matchup_docs.level_notes is '{"1": "...", ...} 필수 1/2/3/6 + 추가 레벨(1~18)';

-- ---------------------------------------------------------------------
-- 2. 제안·다시 제출·승인 때 쓰는 문서 검사 (004의 함수에서 필수 레벨만 바꿈)
-- ---------------------------------------------------------------------
create or replace function public.clean_doc_content(c jsonb)
returns jsonb language plpgsql immutable set search_path = ''
as $$
declare
  summary text;
  cautions text;
  notes jsonb := '{}'::jsonb;
  k text;
  v jsonb;
  lv int;
  req int;
begin
  if c is null or jsonb_typeof(c) <> 'object' then
    raise exception '문서 내용 형식이 잘못됐어요.' using errcode = '23514';
  end if;

  summary := btrim(coalesce(c ->> 'summary', ''));
  if summary = '' then
    raise exception '한 줄 요약을 적어 주세요.' using errcode = '23514';
  end if;
  if char_length(summary) > 100 then
    raise exception '한 줄 요약은 100자 이하로 적어 주세요.' using errcode = '23514';
  end if;

  cautions := btrim(coalesce(c ->> 'lane_cautions', ''));
  if char_length(cautions) > 3000 then
    raise exception '라인전 주의사항은 3000자 이하로 적어 주세요.' using errcode = '23514';
  end if;

  if jsonb_typeof(c -> 'level_notes') is distinct from 'object' then
    raise exception '레벨별 딜교법 형식이 잘못됐어요.' using errcode = '23514';
  end if;
  for k, v in select * from jsonb_each(c -> 'level_notes') loop
    if k !~ '^[0-9]{1,2}$' or k::int not between 1 and 18 then
      raise exception '레벨은 1~18 사이 숫자만 쓸 수 있어요. (%)', k using errcode = '23514';
    end if;
    lv := k::int;
    if jsonb_typeof(v) <> 'string' then
      raise exception '%레벨 내용 형식이 잘못됐어요.', lv using errcode = '23514';
    end if;
    if char_length(btrim(v #>> '{}')) > 1000 then
      raise exception '%레벨 내용은 1000자 이하로 적어 주세요.', lv using errcode = '23514';
    end if;
    if btrim(v #>> '{}') <> '' then
      notes := notes || jsonb_build_object(lv::text, btrim(v #>> '{}'));  -- "06" 같은 키도 "6"으로
    end if;
  end loop;

  foreach req in array array[1, 2, 3, 6] loop
    if not notes ? req::text then
      raise exception '%레벨 딜교법은 꼭 적어야 해요.', req using errcode = '23514';
    end if;
  end loop;

  return jsonb_build_object('summary', summary, 'level_notes', notes, 'lane_cautions', cautions);
end;
$$;

-- create or replace는 권한을 그대로 두지만, 004와 같게 한 번 더 막아 둔다
revoke execute on function public.clean_doc_content(jsonb) from public, anon, authenticated;

commit;
