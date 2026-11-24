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
// 앱 푸시 (1.3 패치 P-2, SPEC 6-102 - 없으면 그 플랫폼만 건너뛰고 경고 한 줄, 웹 푸시는 그대로):
//   APNS_KEY_P8               : Apple Developer → Keys에서 받은 APNs 키(.p8) 파일 내용 전체
//   APNS_KEY_ID               : 그 키의 Key ID (10자리)
//   APNS_TEAM_ID              : Apple 팀 ID (10자리)
//   FCM_SERVICE_ACCOUNT_JSON  : Firebase 프로젝트 설정 → 서비스 계정 → 새 비공개 키로 받은 JSON 파일 내용 전체
//   (APNs 주제 = 앱 번들 ID는 아래 APP_BUNDLE_ID 상수)
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
  /** P-2 앱(iOS·Android) 발송. 없으면 웹만 (P-2 전과 같음) */
  app?: AppDeps;
  /** 앱 발송을 응답 뒤로 미룰 수 있으면 미루고 true (Supabase EdgeRuntime.waitUntil). 없거나 false면 끝날 때까지 기다린 뒤 응답 */
  defer?(work: Promise<void>): boolean;
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
  // 062: 프로필 사진 신고(문장이 "(프로필 사진)")는 "프로필 사진 신고" 탭 — 화면 reportsPath(src/lib/notifications.js)와 같은 규칙
  report_received: (n) => (String(n.message ?? '').includes('(프로필 사진)') ? '/admin/reports?tab=photos' : '/admin/reports'),
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
  profile_photo_removed: { title: '프로필 사진', url: '/me' }, // 062: 운영자가 프로필 사진 삭제 → 마이페이지
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
// 051 공지 (푸시 묶음 notice): 화면(src/lib/notifications.js NOTICE_TITLE·noticeSubject)과 같은 제목. 본문은 공지 제목, 누르면 그 공지
// 052 장인 새 팔로워 (푸시 묶음 new_followers, 기본 꺼짐): 본문은 DB 문장 그대로(숫자만, 누가 팔로우했는지 없음), 누르면 내 팔로워 목록
export const NOTICE_TITLE = '새 공지가 올라왔습니다';
export const NEW_FOLLOWERS_PATH = '/me/followers';
export function noticeSubject(message: string | null): string | null {
  const m = /「(.*)」\s*$/.exec(String(message ?? '').trim());
  return m ? m[1] : null;
}
const withoutOperatorId = (s: string) =>
  s.replaceAll('운영자 계정 {운영자 닉네임}으로', '운영자 계정으로').replaceAll('{운영자 닉네임}으로', '운영자 계정으로').replaceAll('{운영자 닉네임}', '운영자 계정');
function matchupUrl(n: PushNotice): string {
  if (!n.target_champion || !n.counter_champion) return '/notifications';
  const path = `/champion/${encodeURIComponent(n.target_champion)}/counter/${encodeURIComponent(n.counter_champion)}`;
  return n.build_id ? `${path}?build=${n.build_id}` : path;
}
// 074 댓글·답글 (푸시 묶음 comments, SPEC 6-107): 화면 알림 목록(src/lib/notifications.js describeNotification의 게시판·문서 댓글)과 같은 규칙.
//   본문 = DB 문장(" 메모: " 앞까지) 그대로 - 안 읽은 알림에 댓글이 더 달리면 DB가 문장을 「새 댓글 N개」로 고치므로 보낼 때의 문장이 곧 개수다.
//   누르면: 문서 댓글(doc_comment)과 문서의 답글(comment_reply인데 글 번호 없음) → 그 상대법 화면의 댓글 칸(#comments),
//   그 밖(글 댓글·글의 답글) → 그 글. 갈 곳을 모르면 알림 목록.
export const COMMENT_TITLE: Record<string, string> = { post_comment: '새 댓글', doc_comment: '새 댓글', comment_reply: '새 답글' };
export function commentPath(n: PushNotice): string {
  const onDoc = n.kind === 'doc_comment' || (n.kind === 'comment_reply' && n.post_id == null);
  if (onDoc) {
    if (!n.target_champion || !n.counter_champion) return '/notifications';
    return `/champion/${encodeURIComponent(n.target_champion)}/counter/${encodeURIComponent(n.counter_champion)}#comments`;
  }
  return n.post_id ? `/board/${n.post_id}` : '/notifications';
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
  if (n.kind === 'notice_posted') {
    const subject = noticeSubject(n.message);
    return { title: NOTICE_TITLE, body: cut(subject ? `「${subject}」` : '눌러서 공지를 확인해 주세요.'), url: n.post_id ? `/board/${n.post_id}` : '/notifications', tag };
  }
  if (n.kind === 'new_followers') {
    return { title: '새 팔로워', body: cut(n.message ?? '오늘 새 팔로워가 생겼습니다.'), url: NEW_FOLLOWERS_PATH, tag };
  }
  const ct = COMMENT_TITLE[n.kind];
  if (ct) {
    const line = String(n.message ?? '').split(' 메모: ')[0].trim();
    return { title: ct, body: cut(line || '눌러서 확인해 주세요.'), url: commentPath(n), tag };
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

  // P-2: 웹 발송(아래 webPush - 예전과 같은 동작·같은 응답)이 끝난 뒤 앱 발송. 앱 쪽 실패는 웹 응답에 닿지 않고,
  // 웹 쪽이 실패해도 push_targets가 알림 내용을 줬으면 앱 발송은 한다. deps.app이 없으면(테스트·설정 전) 예전과 똑같다
  const shared: WebShared = {};
  try {
    return await webPush(id, deps, shared);
  } finally {
    const raw = shared.notice;
    if (deps.app && raw) {
      const ready = shared.enriched;
      const work = sendAppPush(id, () => (ready ? Promise.resolve(ready) : withAuthor(raw, deps)), deps.app)
        .then(() => undefined, (e) => console.error('app-push: 예상하지 못한 오류', e instanceof Error ? e.name : 'unknown'));
      if (!deps.defer?.(work)) await work;
    }
  }
}

type WebShared = { notice?: PushNotice; enriched?: PushNotice };

/** 050: 장인 페이지 주소를 만들려고 빌드 작성자를 읽는다. 못 읽으면 상대법으로 (알림은 그대로 보낸다) */
async function withAuthor(n: PushNotice, deps: PushDeps): Promise<PushNotice> {
  let notice = n;
  if (notice.kind === 'followed_build_created' && notice.build_id && deps.buildAuthor) {
    const a = await deps.buildAuthor(notice.build_id).catch((e) => ({ data: null, error: { message: String(e) } }));
    if (a.error) console.error('web-push: 빌드 작성자 조회 실패', a.error.message);
    if (a.data) notice = { ...notice, author_id: a.data };
  }
  return notice;
}

/** 웹 푸시 발송 (037~). P-2 전 handlePush의 POST 처리 그대로 - 응답·로그·지우기 규칙 같음 */
async function webPush(id: number, deps: PushDeps, shared: WebShared): Promise<Response> {
  const { data, error } = await deps.targets(id);
  if (error) {
    console.error('web-push: 대상 조회 실패', error.message);
    return json({ error: error.message }, 500);
  }
  const subs = data?.subscriptions ?? [];
  if (data?.notification) shared.notice = data.notification;
  if (!data?.notification || subs.length === 0) return json({ ok: true, sent: 0 }, 200);

  const notice = await withAuthor(data.notification, deps);
  shared.enriched = notice;
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

// =====================================================================
// 앱 푸시 (1.3 패치 P-2, SPEC 6-102): 072 device_push_tokens(service_role 읽기·지우기)의 기기 토큰으로 보낸다.
//   iOS     → APNs 토큰 방식(.p8 키로 만든 ES256 JWT), https://api.push.apple.com HTTP/2 (Supabase Edge 런타임 fetch가 HTTP/2로 붙는다)
//   Android → FCM HTTP v1, 서비스 계정 JSON으로 만든 RS256 JWT → OAuth 액세스 토큰(scope firebase.messaging)
// 제목·본문·이동 주소는 웹 푸시와 같은 describePush 값 그대로. 토큰·비밀 값·이메일은 로그에 남기지 않는다(실행당 요약 한 줄).
// =====================================================================
export const APP_BUNDLE_ID = 'com.topsinbyeongja.app'; // capacitor.config.json appId = APNs apns-topic
export const APNS_ORIGIN = 'https://api.push.apple.com';
export const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
export const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
export const APP_PUSH = {
  timeoutMs: 8000, // 외부 호출 하나의 최대 시간
  concurrency: 4, // 플랫폼마다 동시에 보내는 수
  apnsJwtMs: 50 * 60_000, // APNs JWT를 다시 만드는 간격 (Apple: 1시간 안 · 20분보다 자주 바꾸지 말 것)
  fcmTokenMs: 55 * 60_000, // FCM 액세스 토큰 재사용 시간 (Google 토큰은 1시간)
  maxAgeMs: 60 * 60_000, // push_targets와 같은 1시간 규칙: 이보다 오래된 알림은 보내지 않는다
};

export type AppToken = { id: number; platform: string; token: string };
export type AppMessage = { title: string; body: string; url: string; notificationId: number };
export type SendResult = { ok: true } | { ok: false; remove: boolean; code: string };
export type AppSender = (token: string, msg: AppMessage) => Promise<SendResult>;
/** 보낼 수 있으면 { send }, 비밀 값이 없거나 형식이 틀리면 { skip: 경고 문장 } */
export type AppChannel = { send: AppSender } | { skip: string };
export type AppDeps = {
  /** 알림 번호 → 받는 사람·만든 시각 (service_role로 notifications를 읽는다). 없으면 data null */
  recipient(notificationId: number): Result<{ user_id: string; created_at: string }>;
  tokens(userId: string): Result<AppToken[]>;
  /** 무효 토큰 지우기 (device_push_tokens id) */
  forget(ids: number[]): Result<unknown>;
  ios: AppChannel;
  android: AppChannel;
  now?: () => number;
};
type PlatformSummary = { tokens: number; sent: number; failed: number; removed: number; skipped?: boolean; codes?: Record<string, number> };
export type AppSummary = { skipped?: string; ios?: PlatformSummary; android?: PlatformSummary };

const enc = new TextEncoder();
const b64url = (bytes: Uint8Array) => {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};
const b64urlJson = (v: unknown) => b64url(enc.encode(JSON.stringify(v)));

/** PEM(.p8·서비스 계정 private_key) → PKCS#8 바이트. 머리·꼬리 줄, 따옴표, 공백·줄바꿈, 글자 그대로의 \n·\r을 지우고 base64만 읽는다 */
export function pkcs8FromPem(text: string): Uint8Array {
  const body = text.replace(/-----(BEGIN|END)[^-]*-----/g, '').replace(/\\[nr]/g, '').replace(/["'\s]/g, '');
  if (!body || !/^[A-Za-z0-9+/]+={0,2}$/.test(body)) throw new Error('키 형식 오류'); // 키 내용은 절대 출력하지 않는다
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

async function signJwt(header: Record<string, unknown>, claims: Record<string, unknown>, key: CryptoKey, algorithm: AlgorithmIdentifier | EcdsaParams): Promise<string> {
  const input = `${b64urlJson(header)}.${b64urlJson(claims)}`;
  // WebCrypto ECDSA 서명은 r||s 64바이트 (JWS ES256 모양 그대로), RSASSA-PKCS1-v1_5는 그대로 RS256
  const sig = new Uint8Array(await crypto.subtle.sign(algorithm, key, enc.encode(input)));
  return `${input}.${b64url(sig)}`;
}

const failure = (e: unknown): SendResult => ({
  ok: false, remove: false,
  code: (e as { name?: string })?.name === 'TimeoutError' || (e as { name?: string })?.name === 'AbortError' ? 'timeout' : 'network',
});

/** APNs 요청 본문: 잠금 화면 제목·본문 + 소리, 누르면 갈 주소(url)·알림 번호는 aps 밖 사용자 칸 (앱이 data로 받는다) */
export function apnsPayload(msg: AppMessage) {
  return { aps: { alert: { title: msg.title, body: msg.body }, sound: 'default' }, url: msg.url, notification_id: String(msg.notificationId) };
}
/** FCM HTTP v1 요청 본문 (data 값은 모두 글자여야 한다) */
export function fcmMessage(token: string, msg: AppMessage) {
  return {
    message: {
      token,
      notification: { title: msg.title, body: msg.body },
      data: { url: msg.url, notification_id: String(msg.notificationId) },
      android: { priority: 'HIGH' },
    },
  };
}

/**
 * iOS(APNs) 보내기. 비밀 값 APNS_KEY_P8(.p8 내용)·APNS_KEY_ID·APNS_TEAM_ID가 하나라도 없으면 skip.
 * JWT는 50분 칸에 맞춘 iat로 만들어 그 칸 안에서는 다시 쓴다(여러 인스턴스가 떠도 같은 iat → Apple의 잦은 교체 거절을 피함, 최대 50분 묵음).
 * 지우는 경우: 410(Unregistered 등), 400 BadDeviceToken·DeviceTokenNotForTopic. 그 밖(403·429·5xx·시간 초과·네트워크)은 남긴다.
 */
export function apnsChannel(env: Env, fetcher: typeof fetch, now: () => number = Date.now): AppChannel {
  const p8 = env.get('APNS_KEY_P8');
  const keyId = env.get('APNS_KEY_ID')?.trim();
  const teamId = env.get('APNS_TEAM_ID')?.trim();
  if (!p8?.trim() || !keyId || !teamId) return { skip: 'app-push: APNS_KEY_P8·APNS_KEY_ID·APNS_TEAM_ID 비밀 값이 모두 있어야 iOS 알림을 보냅니다 - iOS는 건너뜀' };
  let key: Promise<CryptoKey> | null = null;
  let cached: { jwt: string; slot: number } | null = null;
  const jwt = async () => {
    const slot = Math.floor(now() / APP_PUSH.apnsJwtMs);
    if (cached && cached.slot === slot) return cached.jwt;
    key ??= crypto.subtle.importKey('pkcs8', pkcs8FromPem(p8) as BufferSource, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
    const token = await signJwt({ alg: 'ES256', kid: keyId }, { iss: teamId, iat: Math.floor((slot * APP_PUSH.apnsJwtMs) / 1000) }, await key,
      { name: 'ECDSA', hash: 'SHA-256' });
    cached = { jwt: token, slot };
    return token;
  };
  const send: AppSender = async (token, msg) => {
    let auth: string;
    try {
      auth = await jwt();
    } catch {
      key = null; // 다음 실행에서 다시 읽어 본다
      return { ok: false, remove: false, code: 'apns_key' };
    }
    let res: Response;
    try {
      res = await fetcher(`${APNS_ORIGIN}/3/device/${encodeURIComponent(token)}`, {
        method: 'POST',
        headers: {
          authorization: `bearer ${auth}`, 'apns-topic': APP_BUNDLE_ID, 'apns-push-type': 'alert', 'apns-priority': '10',
          'content-type': 'application/json',
        },
        body: JSON.stringify(apnsPayload(msg)),
        signal: AbortSignal.timeout(APP_PUSH.timeoutMs),
      });
    } catch (e) {
      return failure(e);
    }
    if (res.status === 200) return { ok: true };
    const reason = await res.json().then((b) => (typeof b?.reason === 'string' ? b.reason.slice(0, 40) : ''), () => '');
    if (reason === 'ExpiredProviderToken' || reason === 'InvalidProviderToken') cached = null;
    const remove = res.status === 410 || (res.status === 400 && (reason === 'BadDeviceToken' || reason === 'DeviceTokenNotForTopic'));
    return { ok: false, remove, code: reason ? `${res.status} ${reason}` : String(res.status) };
  };
  return { send };
}

/**
 * Android(FCM HTTP v1) 보내기. 비밀 값 FCM_SERVICE_ACCOUNT_JSON(서비스 계정 JSON 전체)이 없거나 project_id·client_email·private_key가 없으면 skip.
 * 액세스 토큰은 55분 재사용(동시에 여러 번 받지 않게 한 번만 요청). 401이면 버리고 다음에 새로 받는다.
 * 지우는 경우: 404 UNREGISTERED, 400 INVALID_ARGUMENT 중 토큰 칸(message.token) 오류. 그 밖(403·429·5xx·인증 실패·시간 초과)은 남긴다.
 */
export function fcmChannel(env: Env, fetcher: typeof fetch, now: () => number = Date.now): AppChannel {
  const raw = env.get('FCM_SERVICE_ACCOUNT_JSON');
  if (!raw?.trim()) return { skip: 'app-push: FCM_SERVICE_ACCOUNT_JSON 비밀 값이 없어 Android 알림을 건너뜀' };
  let sa: { project_id?: unknown; client_email?: unknown; private_key?: unknown } | null = null;
  try {
    sa = JSON.parse(raw);
  } catch { /* 아래에서 skip */ }
  const projectId = typeof sa?.project_id === 'string' ? sa.project_id : '';
  const email = typeof sa?.client_email === 'string' ? sa.client_email : '';
  const pem = typeof sa?.private_key === 'string' ? sa.private_key : '';
  if (!projectId || !email || !pem) return { skip: 'app-push: FCM_SERVICE_ACCOUNT_JSON 형식이 맞지 않아(project_id·client_email·private_key) Android 알림을 건너뜀' };
  const sendUrl = `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`;
  let cached: { token: string; at: number } | null = null;
  let pending: Promise<string> | null = null;
  const access = (): Promise<string> => {
    if (cached && now() - cached.at < APP_PUSH.fcmTokenMs) return Promise.resolve(cached.token);
    pending ??= (async () => {
      const at = now();
      const iat = Math.floor(at / 1000);
      const key = await crypto.subtle.importKey('pkcs8', pkcs8FromPem(pem) as BufferSource, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
      const assertion = await signJwt({ alg: 'RS256', typ: 'JWT' }, { iss: email, scope: FCM_SCOPE, aud: GOOGLE_TOKEN_URL, iat, exp: iat + 3600 }, key,
        { name: 'RSASSA-PKCS1-v1_5' });
      const res = await fetcher(GOOGLE_TOKEN_URL, {
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }).toString(),
        signal: AbortSignal.timeout(APP_PUSH.timeoutMs),
      });
      const body = await res.json().catch(() => null);
      if (!res.ok || typeof body?.access_token !== 'string') throw Object.assign(new Error('fcm_auth'), { status: res.status });
      cached = { token: body.access_token, at };
      return body.access_token as string;
    })().finally(() => { pending = null; });
    return pending;
  };
  const send: AppSender = async (token, msg) => {
    let auth: string;
    try {
      auth = await access();
    } catch (e) {
      const status = (e as { status?: number })?.status;
      return { ok: false, remove: false, code: status ? `fcm_auth ${status}` : failure(e).code === 'timeout' ? 'fcm_auth timeout' : 'fcm_auth' };
    }
    let res: Response;
    try {
      res = await fetcher(sendUrl, {
        method: 'POST',
        headers: { authorization: `Bearer ${auth}`, 'content-type': 'application/json' },
        body: JSON.stringify(fcmMessage(token, msg)),
        signal: AbortSignal.timeout(APP_PUSH.timeoutMs),
      });
    } catch (e) {
      return failure(e);
    }
    if (res.ok) return { ok: true };
    if (res.status === 401) cached = null;
    const err = await res.json().then((b) => b?.error ?? null, () => null);
    const details: { errorCode?: unknown; fieldViolations?: { field?: unknown }[] }[] = Array.isArray(err?.details) ? err.details : [];
    const errorCode = details.map((d) => d?.errorCode).find((c) => typeof c === 'string') as string | undefined;
    const status = typeof err?.status === 'string' ? err.status : '';
    const tokenField = details.some((d) => Array.isArray(d?.fieldViolations) && d.fieldViolations.some((v) => v?.field === 'message.token'))
      || /registration token/i.test(typeof err?.message === 'string' ? err.message : '');
    const remove = (res.status === 404 && (errorCode === 'UNREGISTERED' || status === 'NOT_FOUND'))
      || (res.status === 400 && (errorCode === 'INVALID_ARGUMENT' || status === 'INVALID_ARGUMENT') && tokenField);
    const label = (errorCode ?? status).slice(0, 40);
    return { ok: false, remove, code: label ? `${res.status} ${label}` : String(res.status) };
  };
  return { send };
}

/** 동시에 limit개까지만 돌린다 */
async function mapLimit<T, R>(items: T[], limit: number, fn: (item: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let next = 0;
  const worker = async () => {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i]);
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return out;
}

/**
 * 앱 발송 한 번: 알림 번호 → 받는 사람·만든 시각(1시간 넘으면 안 보냄) → 그 사람의 기기 토큰 → iOS·Android 따로(한쪽 실패가 다른 쪽에 닿지 않음)
 * → 확실한 무효 토큰만 지움 → 요약 로그 한 줄(토큰이 있을 때만). 이 함수는 던지지 않는다.
 */
export async function sendAppPush(notificationId: number, getNotice: () => Promise<PushNotice>, app: AppDeps): Promise<AppSummary> {
  const now = app.now?.() ?? Date.now();
  const r = await app.recipient(notificationId).catch((e) => ({ data: null, error: { message: String(e) } }));
  if (r.error) {
    console.error('app-push: 받는 사람 조회 실패', r.error.message);
    return { skipped: 'recipient_error' };
  }
  if (!r.data) return { skipped: 'no_notification' };
  const created = Date.parse(r.data.created_at);
  if (!Number.isFinite(created) || now - created > APP_PUSH.maxAgeMs) return { skipped: 'old' };
  const t = await app.tokens(r.data.user_id).catch((e) => ({ data: null, error: { message: String(e) } }));
  if (t.error) {
    console.error('app-push: 기기 토큰 조회 실패', t.error.message);
    return { skipped: 'tokens_error' };
  }
  const all = t.data ?? [];
  if (all.length === 0) return { skipped: 'no_tokens' };

  const notice = await getNotice();
  const d = describePush(notice);
  const msg: AppMessage = { title: d.title, body: d.body, url: d.url, notificationId };
  const removeIds: number[] = [];
  const runPlatform = async (platform: 'ios' | 'android'): Promise<PlatformSummary | undefined> => {
    const list = all.filter((x) => x.platform === platform);
    if (list.length === 0) return undefined;
    const ch = app[platform];
    const s: PlatformSummary = { tokens: list.length, sent: 0, failed: 0, removed: 0 };
    if ('skip' in ch) {
      console.warn(ch.skip);
      return { ...s, skipped: true };
    }
    const results = await mapLimit(list, APP_PUSH.concurrency, (x) => ch.send(x.token, msg).catch((e): SendResult => failure(e)));
    results.forEach((res, i) => {
      if (res.ok) {
        s.sent += 1;
        return;
      }
      if (res.remove) {
        s.removed += 1;
        removeIds.push(list[i].id);
      } else s.failed += 1;
      s.codes ??= {};
      s.codes[res.code] = (s.codes[res.code] ?? 0) + 1; // 상태 코드·이유 이름만 (토큰 없음)
    });
    return s;
  };
  const [ios, android] = await Promise.allSettled([runPlatform('ios'), runPlatform('android')]);
  const summary: AppSummary = {};
  if (ios.status === 'fulfilled' && ios.value) summary.ios = ios.value;
  if (android.status === 'fulfilled' && android.value) summary.android = android.value;
  if (removeIds.length) {
    const f = await app.forget(removeIds).catch((e) => ({ data: null, error: { message: String(e) } }));
    if (f.error) console.error('app-push: 무효 토큰 지우기 실패', f.error.message);
  }
  console.log(JSON.stringify({ event: 'app_push', kind: notice.kind, ...summary }));
  return summary;
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
  // P-2 앱 발송: 키·액세스 토큰 보관(캐시)은 이 인스턴스가 떠 있는 동안 이어진다. 토큰 표는 service_role로 읽기·지우기만
  const app: AppDeps = {
    recipient: async (id) => {
      const { data, error } = await admin.from('notifications').select('user_id, created_at').eq('id', id).maybeSingle();
      return { data: (data as { user_id: string; created_at: string } | null) ?? null, error };
    },
    tokens: async (userId) => {
      const { data, error } = await admin.from('device_push_tokens').select('id, platform, token').eq('user_id', userId).order('id').limit(20);
      return { data: (data as AppToken[] | null) ?? [], error };
    },
    forget: async (ids) => {
      const { error } = await admin.from('device_push_tokens').delete().in('id', ids);
      return { data: ids.length, error };
    },
    ios: apnsChannel(Deno.env, fetch),
    android: fcmChannel(Deno.env, fetch),
  };
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
      app,
      // 응답(웹 결과)을 먼저 돌려주고 앱 발송은 뒤에서 (DB 트리거의 pg_net 기다림 5초와 무관하게). 런타임에 없으면 기다린 뒤 응답
      defer: (work) => {
        const rt = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } }).EdgeRuntime;
        if (typeof rt?.waitUntil !== 'function') return false;
        rt.waitUntil(work);
        return true;
      },
    }));
}
