// 장인 외부 링크 (047, SPEC 6-34). 규칙의 기준은 DB(ext_link_parse) — 화면은 같은 기준으로 먼저 쉬운 말로 알려 줄 뿐이다.

/** 사이트 이름 (허용 표의 이름이 우선, 없으면 이 표, 그래도 없으면 주소의 사이트 이름) */
const SITE_NAMES = {
  'youtube.com': '유튜브', 'youtu.be': '유튜브', 'chzzk.naver.com': '치지직', 'sooplive.co.kr': '숲', 'afreecatv.com': '숲',
  'instagram.com': '인스타그램', 'twitch.tv': '트위치', 'x.com': 'X', 'twitter.com': 'X',
};

/** 사이트 이름 하나만 짧게: "www.youtube.com" → "유튜브". domains = [{ domain, label }] (my_links의 허용 사이트, 없어도 됨) */
export function siteName(host, domains = []) {
  const h = String(host ?? '').toLowerCase();
  const hit = (d) => h === d || h.endsWith(`.${d}`);
  const fixed = Object.keys(SITE_NAMES).find(hit);
  if (fixed) return SITE_NAMES[fixed];
  const listed = domains.find((d) => hit(d.domain));
  if (listed) return listed.label.replace(/\s*\(.*\)\s*$/, '');
  return h.replace(/^www\./, '');
}

/** 주소에서 사이트 이름(host)만 (모양이 틀리면 '') */
export function hostOf(url) {
  const m = /^https:\/\/([^/?#]*)/i.exec(String(url ?? '').trim());
  return m ? m[1].toLowerCase() : '';
}

/**
 * 올리기 전에 주소를 먼저 살펴 쉬운 말로 이유를 알려 준다 (DB와 같은 기준). 괜찮으면 null.
 * domains = 허용 사이트 [{ domain, label }]
 */
export function linkProblem(raw, domains = []) {
  const u = String(raw ?? '').trim();
  if (!u) return '주소를 적어 주세요.';
  if (u.length > 300) return '주소가 너무 깁니다. 300자 이하로 적어 주세요.';
  if (!/^https:\/\//i.test(u)) {
    if (/^http:\/\//i.test(u)) return '보안 연결(https://) 주소만 올릴 수 있습니다. 주소 앞의 http://를 https://로 바꿔 보세요.';
    return 'https://로 시작하는 주소를 적어 주세요. 브라우저 주소창의 주소를 그대로 복사하면 됩니다.';
  }
  if (!/^[A-Za-z0-9._~:/?#@&+,;=%-]+$/.test(u)) {
    return '주소에 쓸 수 없는 글자(띄어쓰기·한글·특수 기호 등)가 들어 있습니다. 브라우저 주소창의 주소를 그대로 복사해 주세요.';
  }
  if (/%(?![0-9A-Fa-f]{2})/.test(u) || /%(0[0-9a-f]|1[0-9a-f]|7f)/i.test(u)) {
    return '주소에 쓸 수 없는 글자가 들어 있습니다. 브라우저 주소창의 주소를 그대로 복사해 주세요.';
  }
  const authority = /^https:\/\/([^/?#]*)/i.exec(u)[1];
  const tail = u.slice(8 + authority.length);
  if (authority.includes('@')) return '주소 앞부분에 계정 정보(@)가 들어 있습니다. 채널이나 영상의 원래 주소를 올려 주세요.';
  if (authority.includes(':')) return '포트 번호(:숫자)가 붙은 주소는 올릴 수 없습니다.';
  const h = authority.toLowerCase();
  if (!/^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24}$/.test(h) || /(^|\.)xn--/.test(h)) return '주소의 사이트 이름이 올바르지 않습니다.';
  if (domains.length && !domains.some((d) => h === d.domain || h.endsWith(`.${d.domain}`))) {
    return `허용된 사이트(${domains.map((d) => siteName(d.domain, domains)).filter((v, i, a) => a.indexOf(v) === i).join('·')})의 주소만 올릴 수 있습니다.`;
  }
  if (/^(l|lm|link|links|out|go|redirect|r)\./.test(h)
    || /^\/(redirect|attribution_link|away|out|l)([/?#]|$)/i.test(tail)
    || /(:\/\/|%3a%2f%2f|%3a\/%2f|:%2f%2f|%3a\/\/)/i.test(tail)) {
    return '다른 주소로 넘겨주는 주소(단축·우회 주소)는 올릴 수 없습니다. 채널이나 영상의 원래 주소를 올려 주세요.';
  }
  return null;
}

/** 링크를 열 때 붙이는 rel (SPEC 6-34) */
export const LINK_REL = 'noopener noreferrer nofollow ugc';

/** 이동 확인 창 문구 */
export const LEAVE_TEXT = '탑신병자를 떠나 외부 사이트로 이동합니다. 주소를 확인하세요.';
