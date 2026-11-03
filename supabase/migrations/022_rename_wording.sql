-- =====================================================================
-- 022: 이름·문구·화면 바꾸기 (사이트 이름 "탑신병자") 중 DB 부분
-- 1. 소환사 주문 강타(SummonerSmite)는 새로 고를 수 없다.
--    - 막는 때: 빌드를 새로 등록할 때(승인 대기로 들어올 때), 빌드의 주문을 바꿀 때(수정·다시 제출·고쳐서 승인),
--      새 카운터 제안의 빌드를 넣거나 그 주문을 바꿀 때.
--    - 이미 공개·등록된 예전 빌드는 그대로 둔다 (숨겼다가 다시 공개·승인 대기 빌드를 그대로 승인해도 막지 않음).
-- 2. 칭호 알림 문구: 칭호 이름을 따옴표로 묶는다 ("칭호 '단단묵직'") — 사이트 이름 "탑신병자"와 헷갈리지 않게.
--    지금 DB에 있는 sync_rewards 본문을 그대로 고쳐 다시 만든다 (019와 같은 방식). 이미 쌓인 알림 글자도 같이 바꾼다.
-- 021_report_reasons_hide_log.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 강타 막기
-- ---------------------------------------------------------------------
create function public.check_no_smite(arr text[])
returns void language plpgsql immutable set search_path = ''
as $$
begin
  if 'SummonerSmite' = any(coalesce(arr, '{}')) then
    raise exception '강타는 고를 수 없어요. 다른 소환사 주문을 골라 주세요.' using errcode = '23514';
  end if;
end;
$$;

-- 빌드: 유저가 새로 등록할 때(승인된 제안에서 바로 공개되는 빌드는 제안 단계에서 이미 검사됨), 주문이 바뀔 때
create function public.check_build_spells()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if (tg_op = 'INSERT' and new.status <> 'approved')
     or (tg_op = 'UPDATE' and new.summoner_spells is distinct from old.summoner_spells) then
    perform public.check_no_smite(new.summoner_spells);
  end if;
  return new;
end;
$$;
create trigger builds_no_smite before insert or update of summoner_spells on public.builds
  for each row execute function public.check_build_spells();

-- 새 카운터 제안: 빌드를 넣을 때, 빌드의 주문이 바뀔 때
create function public.check_proposal_spells()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if jsonb_typeof(new.build) = 'object'
     and (tg_op = 'INSERT' or (new.build -> 'summoner_spells') is distinct from (old.build -> 'summoner_spells'))
     and coalesce(new.build -> 'summoner_spells', '[]'::jsonb) @> '["SummonerSmite"]'::jsonb then
    perform public.check_no_smite(array['SummonerSmite']);
  end if;
  return new;
end;
$$;
create trigger edit_proposals_no_smite before insert or update of build on public.edit_proposals
  for each row execute function public.check_proposal_spells();

revoke execute on function public.check_no_smite(text[]) from public, anon, authenticated;
revoke execute on function public.check_build_spells() from public, anon, authenticated;
revoke execute on function public.check_proposal_spells() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. 칭호 알림 문구
--    칭호를 얻었어요: 단단묵직 — [마이페이지]에서 …  →  칭호 '단단묵직'을 얻었어요. [마이페이지]에서 …
--    칭호가 회수됐어요: 단단묵직 (승인 취소·…)      →  칭호 '단단묵직'이 회수됐어요. (승인 취소·…)
--    조사(을/를, 이/가)는 칭호 이름 끝 글자 받침으로 고른다 (public.title_josa)
-- ---------------------------------------------------------------------
create function public.title_josa(p_name text, p_with text, p_without text)
returns text language sql immutable set search_path = ''
as $$
  -- 한글 음절이면 받침 유무로, 아니면 받침 없는 쪽
  select case
    when ascii(right(p_name, 1)) between 44032 and 55203 and (ascii(right(p_name, 1)) - 44032) % 28 <> 0 then p_with
    else p_without
  end;
$$;
revoke execute on function public.title_josa(text, text, text) from public, anon, authenticated;

do $$
declare
  f record;
  def text;
  fixed text;
  n integer := 0;
begin
  for f in
    select p.oid from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
      and (p.prosrc like '%칭호를 얻었어요: %s%' or p.prosrc like '%칭호가 회수됐어요: %s%')
  loop
    def := pg_get_functiondef(f.oid);
    fixed := replace(
      def,
      $r$format('칭호를 얻었어요: %s — [마이페이지]에서 대표 칭호로 고를 수 있어요.', public.title_name(t))$r$,
      $r$format('칭호 ''%s''%s 얻었어요. [마이페이지]에서 대표 칭호로 고를 수 있어요.', public.title_name(t), public.title_josa(public.title_name(t), '을', '를'))$r$
    );
    fixed := replace(
      fixed,
      $r$format('칭호가 회수됐어요: %s (승인 취소·삭제 등으로 조건이 깨졌어요)', public.title_name(t))$r$,
      $r$format('칭호 ''%s''%s 회수됐어요. (승인 취소·삭제 등으로 조건이 깨졌어요)', public.title_name(t), public.title_josa(public.title_name(t), '이', '가'))$r$
    );
    if fixed <> def then
      execute fixed;
      n := n + 1;
    end if;
  end loop;
  if exists (
    select 1 from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
      and (p.prosrc like '%칭호를 얻었어요: %s%' or p.prosrc like '%칭호가 회수됐어요: %s%')
  ) then
    raise exception '칭호 알림 문구 정리가 덜 됐어요 (함수에 옛 문구가 남음).';
  end if;
  raise notice '문구를 고친 함수: %개', n;
end;
$$;

-- 이미 쌓인 알림
update public.notifications n
   set message = format('칭호 ''%s''%s 얻었어요. [마이페이지]에서 대표 칭호로 고를 수 있어요.',
                        m[1], public.title_josa(m[1], '을', '를'))
  from (select id, regexp_match(message, '^칭호를 얻었어요: (.+?) — ') as m from public.notifications where kind = 'title_earned') x
 where n.id = x.id and x.m is not null;
update public.notifications n
   set message = format('칭호 ''%s''%s 회수됐어요. (승인 취소·삭제 등으로 조건이 깨졌어요)',
                        m[1], public.title_josa(m[1], '이', '가'))
  from (select id, regexp_match(message, '^칭호가 회수됐어요: (.+?) \(') as m from public.notifications where kind = 'title_revoked') x
 where n.id = x.id and x.m is not null;

commit;
