-- =====================================================================
-- 매치업 문서 "라인전 주의사항" 칸 → "특이사항" (주의할 점 + 이 매치업만의 특징·팁)
-- - DB 칸 이름(lane_cautions)과 저장된 JSON 키는 그대로 둔다 (화면에 보이지 않는 내부 이름).
-- - 바꾸는 것은 화면에 그대로 나갈 수 있는 오류 문구 하나뿐 (010의 함수에서 문구만 바꿈).
-- 010_fewer_required_levels.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

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
    raise exception '특이사항은 3000자 이하로 적어 주세요.' using errcode = '23514';
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

revoke execute on function public.clean_doc_content(jsonb) from public, anon, authenticated;
comment on column public.matchup_docs.lane_cautions is '특이사항 (화면 이름). 주의할 점, 이 매치업만의 특징·팁';

commit;
