-- =====================================================================
-- 029: "자주 쓰는 아이템" 없애기 + 닉네임에 (운)·(감) 금지 (2026-11-07)
-- 1. 028의 frequent_items 표와 add_frequent_item·remove_frequent_item을 지운다.
--    (item_prices.kind, check_core_items 트리거, set_item_prices는 그대로)
-- 2. 운영자 표시 "(운)"은 이제 화면이 role을 보고 닉네임 앞에 붙인다. 그래서 운영자 닉네임에 들어 있던 "(운)"을 떼어낸다.
--    (닉네임 바꾸기 간격 검사·변경 기록은 건너뛴다. 떼고 나서 다른 사람과 닉네임이 겹치면 오류로 멈추고 아무것도 바뀌지 않는다.)
-- 3. 누구도 닉네임에 "(운)"·"(감)"을 쓸 수 없다. 전각 괄호·대괄호 같은 괄호 모양, 띄어쓰기·보이지 않는 글자를 바꾼 변형도 막는다.
--    nickname_reserved(text): 화면의 src/lib/nickname.js hasReservedMark와 같은 기준.
--    닉네임이 새로 정해지거나 바뀔 때만 검사한다 (이미 가입한 사람의 다른 정보 수정은 막지 않는다).
-- 028까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 자주 쓰는 아이템 삭제
-- ---------------------------------------------------------------------
drop function if exists public.add_frequent_item(text, text);
drop function if exists public.remove_frequent_item(text, text);
drop table if exists public.frequent_items;

-- ---------------------------------------------------------------------
-- 2. 운영자 닉네임의 "(운)" 떼기
-- ---------------------------------------------------------------------
alter table public.profiles disable trigger profiles_keep_nickname;

do $$
declare
  r record;
  stripped text;
begin
  for r in
    select id, nickname from public.profiles
    where role = 'admin' and nickname ~ '\(\s*운\s*\)'
  loop
    stripped := btrim(regexp_replace(r.nickname, '\s*\(\s*운\s*\)\s*', '', 'g'));
    if stripped = '' then
      raise exception '운영자 닉네임이 "(운)"뿐이라 떼면 비게 됩니다. 먼저 닉네임을 정해 주세요. (%)', r.nickname;
    end if;
    if exists (select 1 from public.profiles where id <> r.id and lower(nickname) = lower(stripped)) then
      raise exception '"%" 닉네임을 쓰는 사람이 이미 있어 운영자 닉네임 "%"에서 (운)을 뗄 수 없습니다.', stripped, r.nickname;
    end if;
    update public.profiles set nickname = stripped where id = r.id;
  end loop;
end;
$$;

alter table public.profiles enable trigger profiles_keep_nickname;

-- ---------------------------------------------------------------------
-- 3. 닉네임 예약어 (운)·(감)
-- ---------------------------------------------------------------------
create function public.nickname_reserved(p text)
returns boolean language plpgsql immutable set search_path = ''
as $$
declare
  n text := normalize(coalesce(p, ''), NFKC);
  open_chars constant text := '[{<〔【〈《「『〖﹙⁽₍❨❪❬❮❰❲❴⟦⟨⟪⟬⦅〘〚﹛﹝＜';
  close_chars constant text := ']}>〕】〉》」』〗﹚⁾₎❩❫❭❯❱❳❵⟧⟩⟫⟭⦆〙〛﹜﹞＞';
begin
  -- 공백류·제로폭·방향 표시·소프트 하이픈·한글 채움·결합 기호는 지운다
  n := pg_catalog.regexp_replace(n, '[\s\u00AD\u034F\u115F\u1160\u17B4\u17B5\u180E\u200B-\u200F\u2028-\u202F\u2060-\u206F\u3164\uFEFF\uFFA0\u0300-\u036F]', '', 'g');
  -- 괄호 모양은 모두 ( ) 로
  n := pg_catalog.translate(n, open_chars, pg_catalog.repeat('(', pg_catalog.char_length(open_chars)));
  n := pg_catalog.translate(n, close_chars, pg_catalog.repeat(')', pg_catalog.char_length(close_chars)));
  return n ~ '\([운감]\)';
end;
$$;

create function public.check_nickname_reserved()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.nickname is not null
     and (tg_op = 'INSERT' or new.nickname is distinct from old.nickname)
     and public.nickname_reserved(new.nickname) then
    raise exception '닉네임에는 (운)·(감)을 쓸 수 없습니다.' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger profiles_nickname_reserved before insert or update of nickname on public.profiles
  for each row execute function public.check_nickname_reserved();

revoke execute on function public.nickname_reserved(text) from public, anon, authenticated;
revoke execute on function public.check_nickname_reserved() from public, anon, authenticated;

commit;
