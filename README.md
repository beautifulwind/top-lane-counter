# 탑신병자 — 롤 탑 상대법 위키

상대 탑 라이너를 고르면 **그 챔피언을 이기는 상대법 목록**과 **상대법 공략**(레벨별 딜교, 특이사항, 빌드)을 보여 주는 **참여형 위키**입니다.
이용자가 상대법과 빌드를 바로 등록·수정하고(승인 없음), 운영진이 기록을 보고 숨기거나 되돌립니다. 사이트 이름은 "탑신병자", 부제는 "탑은 라인전이 전부"입니다.

> 설계의 기준은 [SPEC.md](./SPEC.md)입니다. 화면·권한·DB·설정 순서가 모두 그 문서에 있고, 기능을 바꿀 때는 SPEC.md도 함께 고칩니다.

## 주요 기능

- **챔피언 → 상대법 → 매치업 문서**: 전체 챔피언 대상, 초성 검색(`ㄷㄹㅇㅅ` → 다리우스), 운영자가 정한 상대법 순서
- **참여형 위키**: 상대법(플레이할 챔피언 vs 상대) 하나에 빌드(룬·아이템·선마·레벨별 딜교법·특이사항 한 벌) 여러 개. 새 상대법·새 빌드·빌드 수정은 승인 없이 바로 공개되고(남의 빌드는 구글·카카오 회원만 수정), 수정 기록(운영자만, 1년)과 기여자 목록이 남습니다. 예전 승인 제도 화면은 지우지 않고 꺼 두었습니다(`src/lib/features.js`·DB `xp_rules.approval_on`)
- **빌드**: 룬·소환사 주문·시작/핵심 아이템·선마 스킬을 아이콘으로 고르고, 추천/비추천으로 정렬 (게임 데이터는 Riot Data Dragon)
- **레벨·경험치·칭호**: 새 상대법·새 빌드 등록(하루 한도)과 예전 승인 기여로 쌓이고, 칭호는 대표 하나를 골라 닉네임 옆에 표시
- **자유게시판·문서 댓글**: 글·댓글·사진/GIF, 신고, 운영진 숨김·삭제. 고치기·지우기·신고·숨기기는 글·댓글마다 ⋮ 메뉴. 지운 글·댓글은 바로 모든 화면에서 사라지고(글을 지우면 달린 댓글도), 1년 동안 운영자만 볼 수 있게 보관한 뒤 자동으로 지웁니다
- **문의하기**: 운영진에게 문의(오류 신고·건의·계정·탈퇴·기타)를 보내고 답변을 알림으로 받기
- **로그인**: 구글·카카오·비회원(익명), 닉네임 설정, 회원 탈퇴
- **운영자·감독관**: `/admin`에서 숨긴 상대법·빌드, 신고·문의 처리. 새 상대법·새 빌드·문의·신고가 들어오면 운영진에게 알림이 가고, ☰ 메뉴 [관리] 옆에 처리 대기 건수가 보입니다. 운영자는 가입자 수와 닉네임으로 찾은 회원의 가입일·가입 방식·레벨·활동 수를 볼 수 있습니다(이메일·로그인 ID는 볼 수 없고, 감독관에게는 보이지 않음). 운영자 한 명이 감독관을 지정하고, 권한 검사는 모두 DB(RLS와 함수)에서 합니다.
- 모바일 우선 반응형 다크 테마, 모든 화면 하단에 Riot 팬사이트 고지

- **휴대폰 알림(웹 푸시)**: [계정 설정]에서 기기마다 켜면 운영진은 새 상대법·새 빌드·문의·신고를(누르면 그 상대법의 그 빌드로, 신고는 신고 화면으로), 작성자는 숨겨졌던 내 상대법·빌드가 다시 공개된 소식을 폰 잠금 화면 알림으로 받습니다. 받을 종류도 고를 수 있습니다. 안드로이드는 크롬에서, 아이폰·아이패드는 iOS 16.4 이상에서 홈 화면에 추가한 앱으로 열었을 때 켤 수 있습니다. 기기 알림 주소는 본인만 읽고 쓸 수 있고(RLS), 끄기·로그아웃·탈퇴·만료 때 지웁니다.
- **홈 화면 설치(PWA)**: 안드로이드 크롬·아이폰에서 ☰ 메뉴의 [앱 설치]로 앱처럼 설치합니다. 화면 파일(JS·CSS·아이콘)만 저장하고, 새 버전이 배포되면 "새 버전이 있습니다" 알림이 뜹니다. 서비스 워커는 프로덕션 빌드에서만 켜집니다(`npm run build` 뒤 `npm run preview`로 확인).

## 기술 스택

| 영역 | 사용 |
|---|---|
| 프런트엔드 | React 18 + Vite |
| 백엔드·DB·인증 | Supabase (Postgres, Auth, Row Level Security, Storage, Edge Functions) |
| 게임 데이터 | Riot Data Dragon (`ko_KR`) — DB에 복사하지 않음 |
| 배포 | Cloudflare Pages |
| 테스트 | Vitest + Testing Library, DB는 Docker의 Postgres로 검사 |

화면은 Supabase를 직접 부르지 않고 `src/api/` 모듈을 거칩니다. 클라이언트에는 `service_role`·secret 키를 쓰지 않습니다.

## 로컬에서 실행하기

필요한 것: Node.js (npm 포함). DB 검사에는 Docker도 필요합니다.

```bash
npm install        # 의존성 설치
npm start          # 개발 서버 (http://localhost:3000, 포트가 쓰이고 있으면 바로 실패합니다)
npm test           # 화면·로직 테스트 (Vitest)
npm run build      # 배포용 빌드 → dist/
```

DB 권한·함수 검사 (실제 Supabase에는 아무것도 하지 않고, 로컬 Docker Postgres에 깨끗한 DB를 만들어 검사합니다):

```bash
sh supabase/tests/run.sh
```

GitHub Codespaces에서는 열면 개발 서버가 자동으로 3000번에서 시작됩니다. 서버를 한 개 더 띄우지 마세요.

### 환경 변수

프로젝트 루트의 `.env`에 넣습니다 (`.env`는 git에 올라가지 않습니다). Vite는 서버를 **시작할 때만** 읽으므로 바꾼 뒤에는 개발 서버를 다시 시작해야 합니다. 값은 이 저장소 어디에도 적지 않습니다.

| 이름 | 용도 |
|---|---|
| `VITE_SUPABASE_URL` | Supabase 프로젝트 주소 |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | Supabase의 Publishable(공개) 키 |
| `VITE_TURNSTILE_SITE_KEY` | 비회원 시작의 자동 가입 방지(Cloudflare Turnstile) 사이트 키. 없으면 캡차 없이 시작합니다(개발용) |

## Supabase 준비

새 프로젝트를 만들 때의 설정(지역, 로그인 제공자, URL, Edge Functions, 비밀 값, 예약 작업)과 **SQL을 실행하는 순서**는 [SPEC.md 11장](./SPEC.md)에 정리되어 있습니다.

- DB 변경은 `supabase/schema.sql` → `supabase/migrations/*.sql`을 번호 순서대로 SQL Editor에서 **파일마다 한 번씩** 실행합니다.
- 실행 뒤 확인용 조회는 `supabase/scripts/`에 있습니다.
- Edge Functions(`supabase/functions/`)는 대시보드에서 배포하고, 비밀 값은 Supabase의 Secrets에만 둡니다.
- 테스트 데이터 비우기 스크립트도 `supabase/scripts/`에 있습니다 (정식 공개 직전 등). 되돌릴 수 없으니 백업 확인 → `reset_test_data_preview.sql`(지울 개수 확인) → `reset_test_data.sql` 순서로 실행합니다. 계정(운영자·운영자 모드 포함)은 지우지 않습니다.
- 웹 푸시(037)는 Edge Function `web-push`와 비밀 값(`VAPID_PUBLIC_KEY`·`VAPID_PRIVATE_KEY`·`VAPID_SUBJECT`·`PUSH_WEBHOOK_SECRET`), Vault 두 값(`push_function_url`·`push_webhook_secret`)이 필요합니다. 순서와 방법은 SPEC.md 11-11.
- 오래된 기록 자동 삭제(알림 90일·문의 180일·처리 기록 1년·처리한 오류 신고 1년(043))는 pg_cron으로 매일 새벽에 돕니다. 장인 인증 하루 작업(046 `influencer-daily` — 만료·만료 전 알림·임시 닉네임·1년 정리)은 매일 한국 시간 정오에 돕니다. 035(처리 기록 1년)는 마이그레이션을 실행한 뒤 파일 맨 아래 일정 등록 SQL을 한 번 따로 실행해야 합니다.

## 배포

Cloudflare Pages로 배포합니다.

- 빌드 명령: `npm run build`
- 출력 폴더: `dist`
- 환경 변수: Cloudflare Pages의 Settings → Environment variables에 위 세 이름을 Production·Preview 둘 다 입력합니다. 값은 빌드할 때 코드에 들어가므로 바꾼 뒤에는 다시 배포해야 합니다.
- 순서: DB 변경(SQL)을 먼저 실행하고, 확인한 뒤 코드를 push합니다. 마이그레이션은 이전 버전 화면과도 동작하도록 더하기 위주로 만듭니다.

공개 직전에 해야 할 일(운영자 이메일·시행일 채우기 등)은 SPEC.md 8장의 "공개 전 체크리스트"에 있습니다.

## 폴더 구조

```
src/
  api/         Supabase·Data Dragon 접근 (화면은 여기만 부릅니다)
  components/  공통 부품
  lib/         순수 로직 (초성 검색, 조사, 빌드 검사 등)
  pages/       화면 (pages/admin = 운영자·감독관)
  styles/      tokens.css — 모든 색은 이 파일의 변수로만 정합니다
  test/        화면 테스트와 가짜 Supabase
supabase/
  schema.sql, migrations/   DB 정의와 변경 (번호 순서대로 실행)
  scripts/                  확인용 조회, 테스트 데이터 비우기
  functions/                Edge Functions (탈퇴, 카카오 연결 끊기, 사진 정리, 웹 푸시 보내기)
  tests/                    DB 권한·함수 검사 (Docker, 로컬 전용)
```

## 라이선스와 고지

[LICENSE](./LICENSE)를 따릅니다. 이 사이트는 Riot Games가 보증하거나 후원하지 않으며, League of Legends 및 Riot Games는 Riot Games, Inc.의 상표 또는 등록 상표입니다.
