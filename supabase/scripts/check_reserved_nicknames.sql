-- =====================================================================
-- 닉네임 예약어 확인 (읽기만 — 아무것도 바꾸지 않는다). 029 실행 "전"에 돌려 보고, 실행 뒤에도 한 번 더 돌려 본다.
-- 결과가 비어 있으면 걸리는 닉네임이 없는 것.
--   · role = 'admin' 줄은 029가 "(운)"을 떼어 주므로 괜찮다 (실행 뒤에는 나오지 않아야 한다).
--   · role = 'user' 줄이 나오면 그 사람이 이미 (운)·(감)이 들어간 닉네임을 쓰고 있다 → 닉네임을 바꿔 달라고 해야 한다.
--     (029는 이 사람들을 바꾸지 않는다. 다른 정보를 고치는 건 막지 않고, 닉네임을 새로 바꿀 때만 검사한다.)
-- 029와 상관없이 이 파일만으로 실행된다 (029의 nickname_reserved 함수를 쓰지 않고 같은 기준을 직접 계산).
-- =====================================================================
with norm as (
  select id, nickname, role, is_guest,
         pg_catalog.translate(
           pg_catalog.translate(
             pg_catalog.regexp_replace(normalize(nickname, NFKC), '[\s\u00AD\u034F\u115F\u1160\u17B4\u17B5\u180E\u200B-\u200F\u2028-\u202F\u2060-\u206F\u3164\uFEFF\uFFA0\u0300-\u036F]', '', 'g'),
             '[{<〔【〈《「『〖﹙⁽₍❨❪❬❮❰❲❴⟦⟨⟪⟬⦅〘〚﹛﹝＜', pg_catalog.repeat('(', 30)),
           ']}>〕】〉》」』〗﹚⁾₎❩❫❭❯❱❳❵⟧⟩⟫⟭⦆〙〛﹜﹞＞', pg_catalog.repeat(')', 30)) as folded
  from public.profiles
  where nickname is not null
)
select id, nickname as "닉네임", role as "역할", is_guest as "비회원", folded as "정리한 모양"
from norm
where folded ~ '\([운감]\)'
order by role, nickname;
