// 카카오 "연결 끊기 알림" 받기 (SPEC 6-8)
// 이용자가 카카오 쪽(카카오톡 설정 → 연결된 서비스 관리 등)에서 이 사이트와 연결을 끊으면 카카오가 이 주소를 부른다.
//   → DB 함수 kakao_unlinked: 구글도 연결돼 있으면 카카오 연결만 떼고, 카카오만 있으면 탈퇴 처리 (운영자는 지우지 않음)
//
// 배포: Supabase 대시보드 → Edge Functions → 이름 kakao-unlink, 이 파일 내용 그대로. "Verify JWT"는 끈다
//   (카카오는 Supabase 토큰을 보내지 않는다 — 대신 아래에서 카카오 어드민 키를 확인한다)
// 비밀 값: KAKAO_ADMIN_KEY (대시보드 → Edge Functions → Secrets). 코드·.env·저장소에 넣지 않는다.
// SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY는 Supabase가 자동으로 넣어 준다.
import { createClient } from 'npm:@supabase/supabase-js@2.49.1';

type Env = { get(key: string): string | undefined };
type Rpc = (kakaoId: string) => Promise<{ data: unknown; error: { message: string } | null }>;

/** 길이와 상관없이 같은 시간에 비교 (키를 한 글자씩 맞혀 보는 것 방지) */
export function sameText(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

const text = (body: string, status: number) => new Response(body, { status, headers: { 'content-type': 'text/plain; charset=utf-8' } });

/** 카카오가 보낸 요청 하나 처리. 테스트를 위해 환경·DB 호출을 밖에서 받는다 */
export async function handleUnlink(req: Request, env: Env, rpc: Rpc): Promise<Response> {
  const adminKey = env.get('KAKAO_ADMIN_KEY');
  if (!adminKey) {
    console.error('kakao-unlink: KAKAO_ADMIN_KEY 비밀 값이 없어요');
    return text('not configured', 500);
  }
  if (!sameText(req.headers.get('authorization') ?? '', `KakaoAK ${adminKey}`)) return text('unauthorized', 401);

  // 카카오 콘솔에서 GET/POST 중 무엇을 골라도 받는다 (POST는 form 형식)
  let params: URLSearchParams;
  if (req.method === 'GET') params = new URL(req.url).searchParams;
  else if (req.method === 'POST') params = new URLSearchParams(await req.text());
  else return text('method not allowed', 405);

  const userId = params.get('user_id') ?? '';
  if (!/^\d{1,20}$/.test(userId)) return text('bad request', 400);
  const appId = env.get('KAKAO_APP_ID'); // 선택: 넣어 두면 다른 앱의 알림은 거절
  if (appId && params.get('app_id') !== appId) return text('wrong app', 400);

  const { data, error } = await rpc(userId);
  if (error) {
    console.error('kakao-unlink: DB 처리 실패', error.message);
    return text('error', 500); // 카카오에 실패로 알려 둔다
  }
  // 로그에는 결과와 이유만 (카카오 회원번호·이메일 등은 남기지 않는다)
  console.log(JSON.stringify({ event: 'kakao_unlink', result: data, referrer: params.get('referrer_type') }));
  return text('ok', 200);
}

if (typeof Deno !== 'undefined') {
  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  Deno.serve((req) => handleUnlink(req, Deno.env, (kakaoId) => db.rpc('kakao_unlinked', { p_kakao_id: kakaoId })));
}
