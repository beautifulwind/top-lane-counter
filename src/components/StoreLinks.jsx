import { useEffect, useRef, useState } from 'react';
import { isNativeApp } from '../lib/native';
import { APP_STORE_URL, INSTAGRAM_URL, PLAY_STORE_URL } from '../lib/storeLinks';

const SOON = '준비 중입니다';

/**
 * [Google Play] [App Store] [인스타그램] 알약 버튼 묶음 (SPEC 6-70).
 * 웹 브라우저에서는 알약 3개. iOS·Android 앱 안에서는 스토어 배지를 그리지 않고(Apple 심사 2.3.10: 다른 플랫폼 로고),
 * 작은 단색 [인스타그램] 글자 링크만 보인다 (6-78). 앱의 size="sm"(로그인 창)은 예전처럼 아무것도 그리지 않는다.
 * size="sm"은 로그인 창용 작은 변형.
 */
export default function StoreLinks({ size = 'md' }) {
  const [soon, setSoon] = useState(false);
  const timer = useRef(null);
  useEffect(() => {
    return () => clearTimeout(timer.current);
  }, []);

  if (isNativeApp()) return size === 'sm' ? null : <InstagramTextLink />;

  const showSoon = () => {
    setSoon(true);
    clearTimeout(timer.current);
    timer.current = setTimeout(() => setSoon(false), 2500);
  };

  return (
    <div className={`store-links store-links-${size}`}>
      <div className="store-links-row">
        {PLAY_STORE_URL ? (
          <a className="store-pill" href={PLAY_STORE_URL} target="_blank" rel="noopener noreferrer" aria-label="Google Play에서 앱 받기">
            <PlayIcon /> <span>Google Play</span>
          </a>
        ) : (
          <button type="button" className="store-pill" onClick={showSoon} aria-label="Google Play (준비 중)">
            <PlayIcon /> <span>Google Play</span>
          </button>
        )}
        <a className="store-pill" href={APP_STORE_URL} target="_blank" rel="noopener noreferrer" aria-label="App Store에서 앱 받기">
          <AppleIcon /> <span>App Store</span>
        </a>
        <a className="store-pill store-pill-icon" href={INSTAGRAM_URL} target="_blank" rel="noopener noreferrer" aria-label="인스타그램 열기">
          <InstagramIcon />
        </a>
      </div>
      {soon && <p className="store-links-soon" role="status">{SOON}</p>}
    </div>
  );
}

/** 앱 푸터용: 단색 작은 아이콘 + "인스타그램". 공식 그라데이션 로고는 쓰지 않는다 */
function InstagramTextLink() {
  return (
    <div className="store-links store-links-native">
      <a className="insta-text-link" href={INSTAGRAM_URL} target="_blank" rel="noopener noreferrer">
        <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" strokeWidth="2">
          <rect x="3.5" y="3.5" width="17" height="17" rx="5" />
          <circle cx="12" cy="12" r="4" />
          <circle cx="17.2" cy="6.8" r=".6" fill="currentColor" stroke="none" />
        </svg>
        <span>인스타그램</span>
      </a>
    </div>
  );
}

function PlayIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false">
      <path fill="#00D7FE" d="M3.6 2.3c-.3.3-.5.8-.5 1.4v16.6c0 .6.2 1.1.5 1.4l.1.1 9.3-9.3v-.2L3.7 2.2l-.1.1z" />
      <path fill="#FFCE00" d="M16.1 15.2 13 12.1v-.2l3.1-3.1.1.1 3.7 2.1c1 .6 1 1.6 0 2.2l-3.7 2.1-.1-.1z" />
      <path fill="#FF3A44" d="m16.2 15.1-3.2-3.2-9.4 9.4c.3.4.9.4 1.5.1l11.1-6.3" />
      <path fill="#00F076" d="M16.2 8.8 5.1 2.5c-.6-.3-1.2-.3-1.5.1l9.4 9.3 3.2-3.1z" />
    </svg>
  );
}

function AppleIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false">
      <path fill="#111" d="M16.37 12.6c-.02-2.2 1.8-3.26 1.88-3.31-1.03-1.5-2.62-1.7-3.18-1.73-1.35-.14-2.64.8-3.33.8-.69 0-1.74-.78-2.87-.76-1.47.02-2.83.86-3.59 2.18-1.53 2.66-.39 6.6 1.1 8.75.73 1.05 1.6 2.24 2.73 2.2 1.1-.04 1.51-.71 2.84-.71 1.32 0 1.7.71 2.86.69 1.18-.02 1.93-1.07 2.65-2.13.84-1.22 1.18-2.4 1.2-2.46-.03-.01-2.3-.88-2.32-3.5zM14.2 6.13c.6-.73 1.01-1.74.9-2.75-.87.04-1.92.58-2.54 1.3-.56.64-1.05 1.67-.92 2.66.97.08 1.96-.49 2.56-1.21z" />
    </svg>
  );
}

function InstagramIcon() {
  return (
    <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false">
      <defs>
        <linearGradient id="ig-grad" x1="0" y1="1" x2="1" y2="0">
          <stop offset="0" stopColor="#FEDA77" />
          <stop offset=".35" stopColor="#F58529" />
          <stop offset=".6" stopColor="#DD2A7B" />
          <stop offset="1" stopColor="#515BD4" />
        </linearGradient>
      </defs>
      <circle cx="12" cy="12" r="11" fill="url(#ig-grad)" />
      <rect x="6.5" y="6.5" width="11" height="11" rx="3.4" fill="none" stroke="#fff" strokeWidth="1.5" />
      <circle cx="12" cy="12" r="2.7" fill="none" stroke="#fff" strokeWidth="1.5" />
      <circle cx="15.6" cy="8.4" r=".9" fill="#fff" />
    </svg>
  );
}
