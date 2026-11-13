// 웹 푸시 보내기 (SPEC 6-24, 037): 폰 잠금 화면 알림.
//   GET  → { publicKey } : 화면이 기기 알림을 켤 때 쓰는 VAPID 공개 키 (비밀 값 VAPID_PUBLIC_KEY에서 읽음)
//   POST → DB 트리거(notifications_push)가 pg_net으로 부른다. 본문 { notification_id }, 헤더 x-push-secret.
//     1) DB push_targets(알림 번호) → 알림 내용과 받을 기기 (보낼 대상인지는 DB가 다시 판단 — 설정·운영자 모드)
//     2) 기기마다 web-push로 보낸다 (내용은 브라우저 푸시 서버를 지나는 동안 암호화돼 있음)
//     3) 푸시 서버가 404·410(만료·구독 취소)이라고 하면 DB push_forget(기기 번호들)로 지운다
//
// 배포: Supabase 대시보드 → Edge Functions → 이름 web-push, 이 파일 내용 그대로. "Verify JWT"는 끈다
//   (DB 트리거는 로그인 토큰 없이 부르므로, 대신 x-push-secret 헤더를 비밀 값 PUSH_WEBHOOK_SECRET과 비교한다.
//    GET은 공개 키만 돌려준다)
// 비밀 값 (대시보드 → Edge Functions → Secrets — 코드·.env·저장소·대화에 쓰지 않는다):
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY : `npx web-push generate-vapid-keys`로 만든 한 쌍
//   VAPID_SUBJECT                        : 연락처 (mailto:운영자 이메일 또는 https://사이트 주소)
//   PUSH_WEBHOOK_SECRET                  : 아무 긴 임의 문자열 (같은 값을 Vault의 push_webhook_secret에도)
// SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY는 Supabase가 자동으로 넣어 준다.
import { createClient } from 'npm:@supabase/supabase-js@2.49.1';
import webpush from 'npm:web-push@3.6.7';

type Env = { get(key: string): string | undefined };
type Result<T> = Promise<{ data: T | null; error: { message: string } | null }>;

export type PushNotice = {
  id: number; kind: string; message: string | null; proposal_id: number | null; build_id: number | null;
  // 038 push_targets가 더 준다 (새 상대법·새 빌드 알림이 그 상대법으로 가도록). 옛 DB면 없다
  counter_id?: number | null; target_champion?: string | null; counter_champion?: string | null;
  // 042 push_targets가 더 준다 (새 글 알림이 그 글로 가도록). 옛 DB면 없다
  post_id?: number | null;
  // 050 팔로우한 장인의 새 빌드: 빌드를 만든 장인 (handlePush가 deps.buildAuthor로 채운다 — DB push_targets는 그대로)
  author_id?: string | null;
};
export type PushTarget = { id: number; endpoint: string; p256dh: string; auth: string };
export type PushDeps = {
  targets(notificationId: number): Result<{ notification: PushNotice | null; subscriptions: PushTarget[] }>;
  forget(ids: number[]): Result<number>;
  /** 한 기기로 보내기. 실패하면 statusCode가 붙은 오류를 던진다 (web-push와 같은 모양) */
  send(target: PushTarget, payload: string): Promise<unknown>;
  /** 050: 빌드를 만든 사람 id (팔로우한 장인의 새 빌드 알림이 장인 페이지로 가도록). 없으면 상대법으로 */
  buildAuthor?(buildId: number): Result<string>;
};

const CORS = {
  'access-control-allow-origin': '*', // GET은 공개 키만 돌려준다. POST는 비밀 값 헤더가 있어야 한다
  'access-control-allow-headers': 'authorization, x-client-info, apikey, content-type',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
};
const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'content-type': 'application/json; charset=utf-8' } });

// 화면의 알림 목록(src/lib/notifications.js describeNotification)과 같은 제목·이동 주소. 테스트(src/test/push.test.js)가 둘을 맞춰 본다
const RESULT: Record<string, { title: string; memo: string }> = {
  proposal_approved: { title: '제안이 승인됐습니다', memo: '승인 메모' },
  proposal_rejected: { title: '제안이 거절됐습니다', memo: '거절 사유' },
  build_approved: { title: '빌드가 공개됐습니다', memo: '승인 메모' },
  build_rejected: { title: '빌드가 거절됐습니다', memo: '거절 사유' },
  build_restored: { title: '숨겨졌던 내 빌드가 다시 공개됐습니다', memo: '메모' },
  revision_request: { title: '재검토 요청을 받았습니다', memo: '운영자 메모' },
  counter_restored: { title: '숨겨졌던 내 상대법이 다시 공개됐습니다', memo: '메모' },
};
const STAFF: Record<string, (n: PushNotice) => string> = {
  proposal_submitted: (n) => (n.proposal_id ? `/admin/proposals/${n.proposal_id}` : '/admin'),
  build_submitted: (n) => (n.build_id ? `/admin/builds/${n.build_id}` : '/admin'),
  inquiry_received: () => '/admin/inquiries',
  // 038: 승인 없이 바로 공개된 새 상대법·새 빌드 → 그 상대법 화면, 그 빌드를 고른 채로 (상대법 정보가 없으면 알림 목록)
  matchup_created: (n) => matchupUrl(n),
  build_created: (n) => matchupUrl(n),
  // 042: 자유게시판 새 글 → 그 글 (글 번호가 없으면 알림 목록)
  post_created: (n) => (n.post_id ? `/board/${n.post_id}` : '/notifications'),
  // 043: 상대법·빌드 오류 신고 → 신고 화면 "오류 신고" 탭 (처리 결과 error_report_handled는 휴대폰 알림을 보내지 않는다)
  error_reported: () => '/admin/reports?tab=wiki',
  // 045: 게시판 신고(글·댓글·문서 댓글) → 신고 화면 "글·댓글 신고" 탭 (기본 탭)
  report_received: () => '/admin/reports',
  // 046: 새 장인 인증 신청 (운영자만) → 장인 인증 심사 화면
  influencer_applied: () => '/admin/influencers',
};
// 046 장인 인증 (신청자·겹친 회원, 푸시 묶음 my_results): 화면의 INFLUENCER_NOTICE(src/lib/notifications.js)와 같은 주소.
// 운영자 라이엇 닉네임은 화면 상수(src/lib/influencer.js OPERATOR_RIOT_ID)에만 있으므로 잠금 화면에는 "운영자 계정으로"라고만 보낸다
const INFLUENCER: Record<string, { title: string; url: string }> = {
  influencer_received: { title: '장인 인증', url: '/me/influencer' },
  influencer_expiring: { title: '장인 인증', url: '/me/influencer' },
  influencer_approved: { title: '장인 인증', url: '/me/influencer' },
  influencer_rejected: { title: '장인 인증', url: '/me/influencer' },
  influencer_expired: { title: '장인 인증', url: '/me/influencer' },
  influencer_revoked: { title: '장인 인증', url: '/me/influencer' },
  nickname_reset_soon: { title: '닉네임 안내', url: '/me/settings' },
  nickname_reset: { title: '닉네임 안내', url: '/me/settings' },
  link_removed: { title: '장인 링크', url: '/me/links' }, // 3b: 링크 관리로
};
// 050 팔로우한 장인의 새 빌드 (푸시 묶음 follow_builds): 화면 followedBuildTitle(src/lib/notifications.js)과 같은 규칙.
// DB 문장 "팔로우한 장인 {닉네임}의 새 빌드가 (N개 )올라왔습니다."에서 닉네임·개수를 읽는다. 누르면 그 장인 페이지
const FOLLOWED_BUILD_MESSAGE = /^팔로우한 장인 (.+)의 새 빌드가 (?:(\d+)개 )?올라왔습니다\.?$/;
export function followedBuildTitle(message: string | null): string {
  const m = FOLLOWED_BUILD_MESSAGE.exec(String(message ?? '').trim());
  if (!m) return message || '팔로우한 장인의 새 빌드가 올라왔습니다';
  const count = m[2] ? Number(m[2]) : 1;
  return count > 1 ? `${m[1]} 님의 새 빌드가 ${count}개 올라왔습니다` : `${m[1]} 님이 새 빌드를 올렸습니다`;
}
const withoutOperatorId = (s: string) =>
  s.replaceAll('운영자 계정 {운영자 닉네임}으로', '운영자 계정으로').replaceAll('{운영자 닉네임}으로', '운영자 계정으로').replaceAll('{운영자 닉네임}', '운영자 계정');
function matchupUrl(n: PushNotice): string {
  if (!n.target_champion || !n.counter_champion) return '/notifications';
  const path = `/champion/${encodeURIComponent(n.target_champion)}/counter/${encodeURIComponent(n.counter_champion)}`;
  return n.build_id ? `${path}?build=${n.build_id}` : path;
}
const BODY_MAX = 120;
const cut = (s: string) => ([...s].length > BODY_MAX ? `${[...s].slice(0, BODY_MAX - 1).join('')}…` : s);

/** 잠금 화면에 보일 내용: { title, body, url, tag } (url = 누르면 갈 사이트 안 주소) */
export function describePush(n: PushNotice): { title: string; body: string; url: string; tag: string } {
  const tag = `n-${n.id}`;
  const r = RESULT[n.kind];
  if (r) {
    const url = n.proposal_id ? `/me/proposals/${n.proposal_id}` : n.build_id ? `/me/builds/${n.build_id}` : '/notifications';
    return { title: r.title, body: n.message ? cut(`${r.memo}: ${n.message}`) : '눌러서 확인해 주세요.', url, tag };
  }
  if (n.kind === 'followed_build_created') {
    const url = n.author_id ? `/u/${encodeURIComponent(n.author_id)}` : matchupUrl(n);
    return { title: followedBuildTitle(n.message), body: '눌러서 새 빌드를 확인해 주세요.', url, tag };
  }
  const inf = INFLUENCER[n.kind];
  if (inf) return { title: inf.title, body: cut(withoutOperatorId(n.message ?? '눌러서 확인해 주세요.')), url: inf.url, tag };
  const s = STAFF[n.kind];
  if (s) return { title: '운영진 알림', body: cut(n.message ?? '새 알림이 있습니다.'), url: s(n), tag };
  return { title: '탑신병자', body: cut(n.message ?? '새 알림이 있습니다.'), url: '/notifications', tag };
}

export async function handlePush(req: Request, env: Env, deps: PushDeps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method === 'GET') {
    const publicKey = env.get('VAPID_PUBLIC_KEY');
    if (!publicKey) return json({ error: '알림 설정이 아직 끝나지 않았습니다.' }, 503);
    return json({ publicKey }, 200);
  }
  if (req.method !== 'POST') return json({ error: '허용되지 않는 요청입니다.' }, 405);
  const secret = env.get('PUSH_WEBHOOK_SECRET');
  if (!secret) {
    console.error('web-push: PUSH_WEBHOOK_SECRET 비밀 값이 없습니다');
    return json({ error: '설정이 덜 됐습니다.' }, 500);
  }
  if (req.headers.get('x-push-secret') !== secret) return json({ error: '권한이 없습니다.' }, 401);

  let id = 0;
  try {
    id = Number((await req.json())?.notification_id);
  } catch { /* 아래에서 거절 */ }
  if (!Number.isSafeInteger(id) || id <= 0) return json({ error: '요청 형식이 잘못됐습니다.' }, 400);

  const { data, error } = await deps.targets(id);
  if (error) {
    console.error('web-push: 대상 조회 실패', error.message);
    return json({ error: error.message }, 500);
  }
  const subs = data?.subscriptions ?? [];
  if (!data?.notification || subs.length === 0) return json({ ok: true, sent: 0 }, 200);

  let notice = data.notification;
  if (notice.kind === 'followed_build_created' && notice.build_id && deps.buildAuthor) {
    // 050: 장인 페이지 주소를 만들려고 빌드 작성자를 읽는다. 못 읽으면 상대법으로 (알림은 그대로 보낸다)
    const a = await deps.buildAuthor(notice.build_id).catch((e) => ({ data: null, error: { message: String(e) } }));
    if (a.error) console.error('web-push: 빌드 작성자 조회 실패', a.error.message);
    if (a.data) notice = { ...notice, author_id: a.data };
  }
  const payload = JSON.stringify(describePush(notice));
  let sent = 0;
  let failed = 0;
  const gone: number[] = [];
  await Promise.all(subs.map(async (s) => {
    try {
      await deps.send(s, payload);
      sent += 1;
    } catch (e) {
      const status = (e as { statusCode?: number })?.statusCode;
      if (status === 404 || status === 410) gone.push(s.id);
      else {
        failed += 1;
        console.error('web-push: 보내기 실패', status ?? String(e)); // 기기 주소는 남기지 않는다
      }
    }
  }));
  if (gone.length) {
    const r = await deps.forget(gone);
    if (r.error) console.error('web-push: 만료 주소 지우기 실패', r.error.message);
  }
  console.log(JSON.stringify({ event: 'web_push', kind: data.notification.kind, sent, failed, expired: gone.length }));
  return json({ ok: true, sent, failed, expired: gone.length }, 200);
}

if (typeof Deno !== 'undefined') {
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const pub = Deno.env.get('VAPID_PUBLIC_KEY');
  const priv = Deno.env.get('VAPID_PRIVATE_KEY');
  const subject = Deno.env.get('VAPID_SUBJECT');
  const ready = Boolean(pub && priv && subject);
  if (ready) webpush.setVapidDetails(subject!, pub!, priv!);
  else console.error('web-push: VAPID_PUBLIC_KEY·VAPID_PRIVATE_KEY·VAPID_SUBJECT 비밀 값이 모두 있어야 보낼 수 있습니다');
  Deno.serve((req) =>
    handlePush(req, Deno.env, {
      targets: (id) => admin.rpc('push_targets', { p_notification_id: id }),
      forget: (ids) => admin.rpc('push_forget', { p_ids: ids }),
      buildAuthor: async (buildId) => {
        const { data, error } = await admin.from('builds').select('author_id').eq('id', buildId).maybeSingle();
        return { data: (data?.author_id as string | null) ?? null, error };
      },
      send: (s, payload) => {
        if (!ready) return Promise.reject(new Error('VAPID 비밀 값 없음'));
        return webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          payload,
          { TTL: 60 * 60 * 24, urgency: 'high' },
        );
      },
    }));
}
