import { useEffect, useRef } from 'react';

const SCRIPT = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
let loading = null;

function loadTurnstile() {
  if (window.turnstile) return Promise.resolve(window.turnstile);
  if (!loading) {
    loading = new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = SCRIPT;
      s.async = true;
      s.onload = () => resolve(window.turnstile);
      s.onerror = () => { loading = null; reject(new Error('자동 가입 방지 확인을 불러오지 못했어요. 인터넷 연결을 확인해 주세요.')); };
      document.head.appendChild(s);
    });
  }
  return loading;
}

/** Turnstile 사이트 키 (.env의 VITE_TURNSTILE_SITE_KEY). 없으면 캡차 없이 진행 (Supabase에서도 캡차를 꺼 둔 개발 환경) */
export const captchaSiteKey = () => import.meta.env.VITE_TURNSTILE_SITE_KEY || null;

/**
 * 봇 가입 방지 확인 (Cloudflare Turnstile). 통과하면 onToken(토큰), 만료·실패하면 onToken(null).
 * 토큰은 Supabase가 직접 확인한다 (Auth → Attack Protection → Captcha). 앱(Expo)에서는 WebView로 같은 위젯을 띄운다.
 */
export default function Captcha({ onToken, onError }) {
  const box = useRef(null);
  const siteKey = captchaSiteKey();

  useEffect(() => {
    if (!siteKey) return undefined;
    let alive = true;
    let widget = null;
    loadTurnstile().then((ts) => {
      if (!alive || !box.current) return;
      widget = ts.render(box.current, {
        sitekey: siteKey,
        language: 'ko',
        callback: (token) => onToken(token),
        'expired-callback': () => onToken(null),
        'error-callback': () => onToken(null),
      });
    }, (e) => alive && onError?.(e.message));
    return () => {
      alive = false;
      if (widget !== null) window.turnstile?.remove?.(widget);
    };
  }, [siteKey]); // eslint-disable-line react-hooks/exhaustive-deps -- 위젯은 한 번만 그린다

  if (!siteKey) return null;
  return <div ref={box} className="captcha" aria-label="자동 가입 방지 확인" />;
}
