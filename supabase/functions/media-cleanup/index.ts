// 사진 정리 (SPEC 6-13 023, 6-71 062): pg_cron이 매일 한 번 부른다. 버킷마다 아래를 한다.
//   board-media (커뮤니티 사진):  media_cleanup_list / media_cleanup_done
//   profile-photos (장인 프로필 사진, 062): profile_photo_cleanup_list / profile_photo_cleanup_done
//   1) DB *_cleanup_list() → 지울 경로 (빠진 파일 대기열 + 안 쓴 채 24시간 지난 파일)
//   2) Storage API로 그 파일들을 지운다 (Supabase는 SQL로 Storage 파일을 지우지 못하게 막아 둠)
//   3) DB *_cleanup_done(경로) → 대기열에서 뺀다. 버킷마다 한 번에 100개씩, 최대 20번(2,000개)
//   062를 실행하기 전 DB라 profile_photo_* 함수가 없으면 그 버킷만 건너뛴다(커뮤니티 사진 정리는 그대로).
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

export type Target = { bucket: string; cleaner: Cleaner; optional?: boolean };

const BATCH = 100;
const ROUNDS = 20;
const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json; charset=utf-8' } });

/** 함수가 아직 없다는 오류인가 (062 전 DB: PostgREST PGRST202 / Postgres 42883) */
const missingFunction = (message: string) => /PGRST202|42883|could not find the function|does not exist/i.test(message);

type Outcome = { removed: number; error?: string; skipped?: boolean };

async function cleanBucket({ bucket, cleaner, optional }: Target): Promise<Outcome> {
  let removed = 0;
  for (let round = 0; round < ROUNDS; round++) {
    const { data: paths, error } = await cleaner.list(BATCH);
    if (error) {
      if (optional && round === 0 && missingFunction(error.message)) {
        console.log(JSON.stringify({ event: 'media_cleanup_skip', bucket, reason: error.message }));
        return { removed, skipped: true };
      }
      console.error(`media-cleanup(${bucket}): 목록 실패`, error.message);
      return { removed, error: error.message };
    }
    if (!paths || paths.length === 0) break;
    const gone = await cleaner.remove(paths);
    if (gone.error) {
      console.error(`media-cleanup(${bucket}): Storage 삭제 실패`, gone.error.message);
      return { removed, error: gone.error.message };
    }
    const marked = await cleaner.done(paths);
    if (marked.error) {
      console.error(`media-cleanup(${bucket}): 대기열 정리 실패`, marked.error.message);
      return { removed, error: marked.error.message };
    }
    removed += paths.length;
    if (paths.length < BATCH) break;
  }
  return { removed };
}

export async function handleCleanup(req: Request, env: Env, targets: Target[]): Promise<Response> {
  if (req.method !== 'POST') return json({ error: '허용되지 않는 요청이에요.' }, 405);
  const secret = env.get('MEDIA_CLEANUP_SECRET');
  if (!secret) {
    console.error('media-cleanup: MEDIA_CLEANUP_SECRET 비밀 값이 없어요');
    return json({ error: '설정이 덜 됐어요.' }, 500);
  }
  if (req.headers.get('x-cleanup-secret') !== secret) return json({ error: '권한이 없어요.' }, 401);

  // 한 버킷이 실패해도 다른 버킷은 정리한다
  const buckets: Record<string, Outcome> = {};
  for (const t of targets) buckets[t.bucket] = await cleanBucket(t);
  const removed = Object.values(buckets).reduce((n, o) => n + o.removed, 0);
  const failed = Object.entries(buckets).filter(([, o]) => o.error);
  console.log(JSON.stringify({ event: 'media_cleanup', removed, buckets }));
  if (failed.length > 0) return json({ error: failed.map(([b, o]) => `${b}: ${o.error}`).join(' / '), removed, buckets }, 500);
  return json({ ok: true, removed, buckets }, 200);
}

if (typeof Deno !== 'undefined') {
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const bucketCleaner = (bucket: string, list: string, done: string): Cleaner => ({
    list: (limit) => admin.rpc(list, { p_limit: limit }),
    remove: (paths) => admin.storage.from(bucket).remove(paths),
    done: (paths) => admin.rpc(done, { p_paths: paths }),
  });
  Deno.serve((req) =>
    handleCleanup(req, Deno.env, [
      { bucket: 'board-media', cleaner: bucketCleaner('board-media', 'media_cleanup_list', 'media_cleanup_done') },
      { bucket: 'profile-photos', cleaner: bucketCleaner('profile-photos', 'profile_photo_cleanup_list', 'profile_photo_cleanup_done'), optional: true },
    ]));
}
