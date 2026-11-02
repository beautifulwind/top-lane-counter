// 회원 탈퇴 (SPEC 6-8): /me의 [탈퇴]가 로그인한 사람의 토큰으로 부른다.
//   1) 그 사람 권한으로 DB 함수 delete_my_account(확인 문구) → 계정 삭제 (운영자 불가, 닉네임 확인은 DB가 한다)
//   2) 카카오가 연결돼 있었으면 카카오 "연결 끊기" API → 카카오의 "연결된 서비스" 목록에서도 빠진다.
//      이 단계가 실패해도 탈퇴는 이미 끝났으므로 로그만 남긴다 (카카오가 보내는 연결 끊기 알림은 'not_found'로 끝남)
//
// 배포: Supabase 대시보드 → Edge Functions → 이름 delete-account, 이 파일 내용 그대로. "Verify JWT"는 켠다 (기본값)
// 비밀 값: KAKAO_ADMIN_KEY (kakao-unlink와 같은 값, 대시보드 → Edge Functions → Secrets). 코드·.env·저장소에 넣지 않는다.
// SUPABASE_URL, SUPABASE_ANON_KEY는 Supabase가 자동으로 넣어 준다.
import { createClient } from 'npm:@supabase/supabase-js@2.49.1';

type Env = { get(key: string): string | undefined };
type DeleteRpc = (authorization: string, confirm: string) => Promise<{ data: unknown; error: { message: string } | null }>;

const CORS = {
  'access-control-allow-origin': '*', // 로그인 토큰이 있어야만 동작하므로 출처는 따지지 않는다
  'access-control-allow-headers': 'authorization, x-client-info, apikey, content-type',
  'access-control-allow-methods': 'POST, OPTIONS',
};
const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'content-type': 'application/json; charset=utf-8' } });

export async function handleDelete(req: Request, env: Env, deleteRpc: DeleteRpc, fetcher: typeof fetch): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: '허용되지 않는 요청이에요.' }, 405);
  const authorization = req.headers.get('authorization') ?? '';
  if (!authorization.startsWith('Bearer ')) return json({ error: '로그인해 주세요.' }, 401);

  let confirm = '';
  try {
    confirm = String((await req.json())?.confirm ?? '');
  } catch {
    return json({ error: '요청 형식이 잘못됐어요.' }, 400);
  }

  const { data: kakaoId, error } = await deleteRpc(authorization, confirm);
  if (error) return json({ error: error.message }, 400); // DB가 정한 문구 그대로 (운영자 불가, 닉네임 다름 등)

  let kakao = 'none';
  if (typeof kakaoId === 'string' && kakaoId) {
    const adminKey = env.get('KAKAO_ADMIN_KEY');
    if (!adminKey) {
      kakao = 'skipped';
      console.error('delete-account: KAKAO_ADMIN_KEY 비밀 값이 없어 카카오 연결 끊기를 못 했어요');
    } else {
      try {
        const res = await fetcher('https://kapi.kakao.com/v1/user/unlink', {
          method: 'POST',
          headers: { authorization: `KakaoAK ${adminKey}`, 'content-type': 'application/x-www-form-urlencoded;charset=utf-8' },
          body: new URLSearchParams({ target_id_type: 'user_id', target_id: kakaoId }),
        });
        kakao = res.ok ? 'unlinked' : `failed ${res.status}`;
      } catch (e) {
        kakao = 'failed';
        console.error('delete-account: 카카오 연결 끊기 요청 실패', String(e));
      }
    }
  }
  console.log(JSON.stringify({ event: 'account_deleted', kakao })); // 누가 탈퇴했는지는 남기지 않는다
  return json({ ok: true }, 200);
}

if (typeof Deno !== 'undefined') {
  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  Deno.serve((req) =>
    handleDelete(
      req,
      Deno.env,
      (authorization, confirm) =>
        createClient(url, anon, {
          global: { headers: { Authorization: authorization } },
          auth: { persistSession: false, autoRefreshToken: false },
        }).rpc('delete_my_account', { p_confirm: confirm }),
      fetch,
    ));
}
