// 자유게시판 사진 정리 (SPEC 6-13, 023): pg_cron이 매일 한 번 부른다.
//   1) DB media_cleanup_list() → 지울 경로 (글·댓글에서 빠진 파일 대기열 + 글에 안 붙은 채 24시간 지난 파일)
//   2) Storage API로 그 파일들을 지운다 (Supabase는 SQL로 Storage 파일을 지우지 못하게 막아 둠)
//   3) DB media_cleanup_done(경로) → 대기열에서 뺀다. 한 번에 100개씩, 최대 20번(2,000개)
//
// 배포: Supabase 대시보드 → Edge Functions → 이름 media-cleanup, 이 파일 내용 그대로. "Verify JWT"는 끈다
//   (pg_cron은 로그인 토큰 없이 부르므로, 대신 x-cleanup-secret 헤더를 비밀 값 MEDIA_CLEANUP_SECRET과 비교한다)
// 비밀 값: MEDIA_CLEANUP_SECRET (대시보드 → Edge Functions → Secrets, 같은 값을 Vault의 media_cleanup_secret에도).
// SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY는 Supabase가 자동으로 넣어 준다.
import { createClient } from 'npm:@supabase/supabase-js@2.49.1';

type Env = { get(key: string): string | undefined };
type Result<T> = Promise<{ data: T | null; error: { message: string } | null }>;
export type Cleaner = {
  list(limit: number): Result<string[]>;
  remove(paths: string[]): Result<unknown>;
  done(paths: string[]): Result<number>;
};

const BUCKET = 'board-media';
const BATCH = 100;
const ROUNDS = 20;
const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json; charset=utf-8' } });

export async function handleCleanup(req: Request, env: Env, cleaner: Cleaner): Promise<Response> {
  if (req.method !== 'POST') return json({ error: '허용되지 않는 요청이에요.' }, 405);
  const secret = env.get('MEDIA_CLEANUP_SECRET');
  if (!secret) {
    console.error('media-cleanup: MEDIA_CLEANUP_SECRET 비밀 값이 없어요');
    return json({ error: '설정이 덜 됐어요.' }, 500);
  }
  if (req.headers.get('x-cleanup-secret') !== secret) return json({ error: '권한이 없어요.' }, 401);

  let removed = 0;
  for (let round = 0; round < ROUNDS; round++) {
    const { data: paths, error } = await cleaner.list(BATCH);
    if (error) {
      console.error('media-cleanup: 목록 실패', error.message);
      return json({ error: error.message, removed }, 500);
    }
    if (!paths || paths.length === 0) break;
    const gone = await cleaner.remove(paths);
    if (gone.error) {
      console.error('media-cleanup: Storage 삭제 실패', gone.error.message);
      return json({ error: gone.error.message, removed }, 500);
    }
    const marked = await cleaner.done(paths);
    if (marked.error) {
      console.error('media-cleanup: 대기열 정리 실패', marked.error.message);
      return json({ error: marked.error.message, removed }, 500);
    }
    removed += paths.length;
    if (paths.length < BATCH) break;
  }
  console.log(JSON.stringify({ event: 'media_cleanup', removed }));
  return json({ ok: true, removed }, 200);
}

if (typeof Deno !== 'undefined') {
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  Deno.serve((req) =>
    handleCleanup(req, Deno.env, {
      list: (limit) => admin.rpc('media_cleanup_list', { p_limit: limit }),
      remove: (paths) => admin.storage.from(BUCKET).remove(paths),
      done: (paths) => admin.rpc('media_cleanup_done', { p_paths: paths }),
    }));
}
