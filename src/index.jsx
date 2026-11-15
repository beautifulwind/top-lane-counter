import React from 'react';
import ReactDOM from 'react-dom/client';
import './styles/tokens.css';
import './index.css';
import App from './App';
import { blockStrayFileDrops } from './components/Media';
import { startWebOnlyFeatures } from './lib/startup';
import { startBackButton } from './lib/backButton';

blockStrayFileDrops(); // 사진을 첨부 칸 밖에 떨어뜨려도 새 탭으로 열리지 않게
startWebOnlyFeatures(); // 웹에서만: [앱 설치] 설치 창 잡기 + 서비스 워커(오프라인 안내·새 버전 알림). 앱(Capacitor)에서는 끔
startBackButton(); // 앱에서만: 안드로이드 뒤로가기 = 열린 창 닫기 → 이전 화면 → 첫 화면이면 종료

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);

// 글꼴 선언(Pretendard·Black Han Sans, src/styles/fonts.css)은 화면 표시를 막지 않게 첫 화면을 그린 뒤 따로 불러온다.
// 오기 전에는 시스템 글꼴로 먼저 보이고(font-display: swap) 오면 바뀐다. 실패해도 시스템 글꼴로 계속 쓸 수 있다.
import('./styles/fonts.css').catch(() => {});
