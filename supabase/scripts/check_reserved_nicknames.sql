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
             E'[{<\u3014\u3010\u3008\u300A\u300C\u300E\u3016\uFE59\u207D\u208D\u2768\u276A\u276C\u276E\u2770\u2772\u2774\u27E6\u27E8\u27EA\u27EC\u2985\u3018\u301A\uFE5B\uFE5D\uFF1C', pg_catalog.repeat('(', 30)),
           E']}>\u3015\u3011\u3009\u300B\u300D\u300F\u3017\uFE5A\u207E\u208E\u2769\u276B\u276D\u276F\u2771\u2773\u2775\u27E7\u27E9\u27EB\u27ED\u2986\u3019\u301B\uFE5C\uFE5E\uFF1E', pg_catalog.repeat(')', 30)) as folded
  from public.profiles
  where nickname is not null
)
select id, nickname as "닉네임", role as "역할", is_guest as "비회원", folded as "정리한 모양"
from norm
where folded ~ '\([운감]\)'
order by role, nickname;
