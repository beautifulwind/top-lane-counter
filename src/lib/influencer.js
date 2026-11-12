// 장인 인증 (046, SPEC 6-32 · 6-33) — 화면 문구 상수는 여기 한 곳에만 둔다. 화면 글자는 "장인", 코드 이름은 influencer.
import { josa } from './josa';
import { INFLUENCER_KINDS } from './nickname';

/**
 * ★ 운영자의 장인 인증 전용 라이엇 계정 (닉네임#태그). 그랜드마스터 이상 신청자가 이 계정으로 친구 요청을 보낸다.
 * 정해지면 이 값 한 줄만 바꾸면 된다 → 신청 화면 안내·복사 버튼·알림 목록 문장·운영자 심사 화면에 모두 반영된다.
 * DB에는 두지 않는다 (알림 문장에는 "{운영자 닉네임}" 자리표시만 저장되고 화면이 이 값으로 채운다).
 * 휴대폰 잠금 화면 알림(web-push)은 이 값을 모르므로 "운영자 계정으로"라고만 보낸다 — 누르면 신청 화면에서 이 값을 본다.
 */
export const OPERATOR_RIOT_ID = '탑신병자#1188';

/** 알림 문장 속 "{운영자 닉네임}" 자리표시 */
export const OPERATOR_PLACEHOLDER = '{운영자 닉네임}';

/** 알림 문장의 자리표시를 운영자 라이엇 닉네임으로 채운다 (조사 으로/로는 josa.js) */
export const fillOperatorId = (message, id = OPERATOR_RIOT_ID) =>
  String(message ?? '')
    .replaceAll(`${OPERATOR_PLACEHOLDER}으로`, josa(id, '으로/로'))
    .replaceAll(OPERATOR_PLACEHOLDER, id);

/** 유형 고르기 순서와 설명 */
export const KIND_CHOICES = [
  { kind: 'creator', label: INFLUENCER_KINDS.creator, hint: '방송·영상 채널이 있는 분 (티어 무관) — 채널 링크 + 공식 이메일 회신' },
  { kind: 'pro', label: INFLUENCER_KINDS.pro, hint: '프로·아마추어 팀 선수 (티어 무관) — 채널·팀 페이지 링크 + 공식 이메일 회신' },
  { kind: 'grandmaster', label: INFLUENCER_KINDS.grandmaster, hint: '지금 그랜드마스터 이상인 분 (채널 없어도 됨) — 라이엇 닉네임 + 친구 요청' },
];

/** (a) 이메일 회신 방식인가 (크리에이터·프로게이머) */
export const byEmail = (kind) => kind === 'creator' || kind === 'pro';

/** 신청 상태 이름 (접수·확인 중 / 승인 / 반려 / 만료 / 취소 / 해제 / 탈퇴) */
export const STATUS_LABEL = {
  pending: '확인 중', approved: '승인', rejected: '반려', expired: '만료', cancelled: '취소', revoked: '인증 해제', withdrawn: '탈퇴',
};

/** 운영자가 (a) 신청자의 공식 이메일로 보내는 확인 메일 (심사 화면 복사 버튼) */
export const confirmMail = (nickname) => ({
  subject: '탑신병자 가입자 본인 확인 이메일입니다',
  body:
    '안녕하세요, 탑신병자입니다.\n\n'
    + `탑신병자에서 "${nickname}" 닉네임으로 장인 인증을 신청하신 본인이 맞으시면, 이 메일에 "본인입니다"라고 회신해 주세요.\n`
    + '신청하신 적이 없다면 이 메일을 무시하셔도 됩니다.\n\n'
    + '회신은 14일 안에 부탁드립니다. 감사합니다.',
});

/** 신청서 칸 검사 (DB apply_influencer와 같은 기준을 먼저 알려 준다). 문제가 있으면 안내, 없으면 null */
export function applicationProblem(v) {
  if (!INFLUENCER_KINDS[v.kind]) return '유형을 골라 주세요.';
  if (byEmail(v.kind)) {
    if (!/^https?:\/\/[^\s/]+\.[^\s]+$/i.test(v.channelUrl.trim())) return '채널·방송 링크를 https://로 시작하는 주소로 적어 주세요.';
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v.email.trim())) return '공식 이메일을 적어 주세요. (채널 소개란이나 팀 공식 페이지에 공개된 이메일)';
  } else {
    if (!/^[^#]+#[^#]+$/.test(v.riotId.trim()) || [...v.riotId.trim()].length > 30) return '라이엇 닉네임#태그를 적어 주세요. (예: 닉네임#KR1)';
    if (!/^https?:\/\/([a-z0-9-]+\.)*op\.gg(\/\S*)?$/i.test(v.opggUrl.trim())) return 'op.gg 링크를 적어 주세요. (https://op.gg/…)';
  }
  return null;
}
