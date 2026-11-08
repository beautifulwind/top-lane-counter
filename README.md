# 탑신병자 — 롤 탑 카운터 위키

상대 탑 라이너를 고르면 **그 챔피언을 이기는 카운터 목록**과 **카운터 공략**(레벨별 딜교, 특이사항, 빌드)을 보여 주는 **참여형 위키**입니다.
이용자가 수정을 제안하고, 운영자가 승인하면 반영됩니다. 사이트 이름은 "탑신병자", 부제는 "탑은 라인전이 전부"입니다.

> 설계의 기준은 [SPEC.md](./SPEC.md)입니다. 화면·권한·DB·설정 순서가 모두 그 문서에 있고, 기능을 바꿀 때는 SPEC.md도 함께 고칩니다.

## 주요 기능

- **챔피언 → 카운터 → 매치업 문서**: 전체 챔피언 대상, 초성 검색(`ㄷㄹㅇㅅ` → 다리우스), 운영자가 정한 카운터 순서
- **참여형 위키**: 새 카운터·문서 수정·빌드를 제안하면 운영자가 승인·거절·재검토 요청 (모든 변경은 승인 뒤 반영, 수정 기록과 되돌리기)
- **빌드**: 룬·소환사 주문·시작/핵심 아이템·선마 스킬을 아이콘으로 고르고, 추천/비추천으로 정렬 (게임 데이터는 Riot Data Dragon)
- **레벨·경험치·칭호**: 승인된 기여 중심으로 쌓이고, 칭호는 대표 하나를 골라 닉네임 옆에 표시
- **자유게시판·문서 댓글**: 글·댓글·사진/GIF, 신고, 운영진 숨김
- **문의하기**: 운영진에게 문의(오류 신고·건의·계정·탈퇴·기타)를 보내고 답변을 알림으로 받기
- **로그인**: 구글·카카오·비회원(익명), 닉네임 설정, 회원 탈퇴
- **운영자·감독관**: `/admin`에서 승인 대기·신고·문의 처리. 새 제안·빌드·문의가 들어오면 알림이 가고, ☰ 메뉴 [관리] 옆에 처리 대기 건수가 보입니다. 제안은 고쳐서 승인할 수 있습니다(처리 기록에 남음). 운영자 한 명이 감독관을 지정하고, 권한 검사는 모두 DB(RLS와 함수)에서 합니다.
- 모바일 우선 반응형 다크 테마, 모든 화면 하단에 Riot 팬사이트 고지

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
- 테스트 데이터 비우기 스크립트도 `supabase/scripts/`에 있습니다 (정식 공개 직전 등).

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
  functions/                Edge Functions (탈퇴, 카카오 연결 끊기, 사진 정리)
  tests/                    DB 권한·함수 검사 (Docker, 로컬 전용)
```

## 라이선스와 고지

[LICENSE](./LICENSE)를 따릅니다. 이 사이트는 Riot Games가 보증하거나 후원하지 않으며, League of Legends 및 Riot Games는 Riot Games, Inc.의 상표 또는 등록 상표입니다.
