-- 로컬 검사 전용 데이터 (supabase/tests/run.sh가 마이그레이션 뒤, 검사 파일 전에 넣는다). 실제 Supabase에서 실행하지 말 것.
-- 예전 schema.sql 초기 데이터와 같은 다리우스 상대 퀸 (카운터 1 + 문서 1 + 빌드 2).
-- 빌드 작성자는 비워 둔다 (= 탈퇴한 유저). 검사 트리거를 거치지 않도록 트리거를 잠깐 끄고 넣는다.
\set ON_ERROR_STOP 1
\set QUIET 1
begin;
alter table public.builds disable trigger builds_check_new;
with c as (
  insert into public.counters (target_champion, counter_champion, sort_order, status)
  values ('Darius', 'Quinn', 1, 'approved')
  returning id
),
d as (
  insert into public.matchup_docs (counter_id, summary, level_notes, lane_cautions)
  select c.id,
    '사거리로 일방적인 견제, 다리우스 W·E만 피하면 라인전 압승',
    jsonb_build_object(
      '1',  '퀸 쪽이 사거리가 길다. 다리우스에게 붙지 말고 미니언 뒤에서 평타로만 견제한다.',
      '2',  '상대가 2레벨을 먼저 찍으면 바로 뒤로 빠진다. 웨이브를 먼저 밀어 2레벨 선점을 노린다.',
      '3',  '핵심 스킬 3개가 모두 생기는 구간. 상대 주요 스킬이 빠진 걸 보고 짧게 딜교한다.',
      '4',  '첫 귀환 전 체력을 깎아 두면 다리우스가 CS를 포기하게 된다.',
      '6',  '궁극기 유무가 가장 중요하다. 상대 궁 각이 보이면 체력을 반 이상 유지한다.',
      '9',  '주력 스킬 마스터. 짧은 교환을 여러 번 하는 쪽이 유리하다.',
      '11', '궁극기 2레벨. 사이드 운영으로 상대를 라인에 묶어둔다.'
    ),
    E'다리우스 E(포획) 사거리 안에서 오래 머무르지 않는다.\n출혈 5중첩 + 궁극기 각이 나오면 바로 빠진다.\n상대 정글이 탑에 오면 다리우스 혼자서도 킬각이 나오므로 와드 필수.'
  from c
  returning counter_id
)
insert into public.builds
  (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch, status)
select c.id, null, b.runes, b.spells, b.starting, b.core, b.skills ->> 0, b.patch, 'approved'
from c, (values
  ( '{"primaryPath":8000,"keystone":8005,"primary":[9111,9104,8014],"secondaryPath":8100,"secondary":[8143,8106],"shards":[5005,5008,5011]}'::jsonb,
    array['SummonerFlash','SummonerTeleport'], array['1055','2003'], array['6672','3006','3031','3036'],
    '["Q","E","W"]'::jsonb, '16.21.1' ),
  ( '{"primaryPath":8000,"keystone":8021,"primary":[9111,9104,8299],"secondaryPath":8400,"secondary":[8444,8451],"shards":[5005,5008,5011]}'::jsonb,
    array['SummonerFlash','SummonerDot'], array['1055','2003'], array['3153','3006','3124','3031'],
    '["Q","W","E"]'::jsonb, '14.1.1' )
) as b (runes, spells, starting, core, skills, patch);

-- 014의 경험치 트리거(트랜잭션 끝에 실행)가 기다리는 중이면 표를 못 바꾸니 먼저 실행해 둔다
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
-- 문서의 "처음 버전" 기록 (예전에는 004의 백필이 만들어 줬다) → 되돌리기 검사용
with r as (
  insert into public.doc_revisions (counter_id, content, kind, created_at)
  select d.counter_id, jsonb_build_object('summary', d.summary, 'level_notes', d.level_notes, 'lane_cautions', d.lane_cautions),
         'create', d.updated_at
  from public.matchup_docs d
  returning id, counter_id
)
update public.matchup_docs d set revision_id = r.id from r where d.counter_id = r.counter_id;
commit;

-- 검사 파일이 쓰는 "올바른 빌드" (새 카운터 제안·다시 제출용). 바꿀 칸만 넘긴다.
create function t.build(core text[] default array['6631','3047','3053'], patch text default '16.21.1')
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'runes', '{"primaryPath":8000,"keystone":8010,"primary":[9111,9104,8299],"secondaryPath":8400,"secondary":[8444,8242],"shards":[5005,5008,5011]}'::jsonb,
    'summoner_spells', '["SummonerFlash","SummonerTeleport"]'::jsonb, 'starting_items', '["1055","2003"]'::jsonb,
    'core_items', to_jsonb(core), 'max_skill', 'Q', 'patch', patch);
$$;
grant execute on function t.build(text[], text) to anon, authenticated;

-- 013: 운영자 처리 함수가 받는 "화면이 본 버전" = 지금 버전 (검사에서는 늘 최신을 본 셈)
create function t.pv(p_id bigint) returns integer language sql stable security definer as $$
  select version from public.edit_proposals where id = p_id;
$$;
create function t.bv(p_id bigint) returns integer language sql stable security definer as $$
  select version from public.builds where id = p_id;
$$;
grant execute on function t.pv(bigint), t.bv(bigint) to anon, authenticated;

-- 039가 승인 제도를 끈다. 예전 승인 기능 검사(*_test.sql)는 켠 채로 하고, 끈 상태는 approval_off_test.sql이 다시 끄고 본다.
-- (039가 실제로 0으로 바꿨는지는 바꾸기 전 값을 남겨 두고 approval_off_test.sql에서 확인)
create table t.approval_after_039 as select value from public.xp_rules where key = 'approval_on';
grant select on t.approval_after_039 to anon, authenticated;
update public.xp_rules set value = 1 where key = 'approval_on';
