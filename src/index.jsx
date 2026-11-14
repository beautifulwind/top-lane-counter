import React from 'react';
import ReactDOM from 'react-dom/client';
import './styles/tokens.css';
import './index.css';
import App from './App';
import { blockStrayFileDrops } from './components/Media';
import { captureInstallPrompt } from './lib/install';
import { registerServiceWorker } from './lib/sw';

blockStrayFileDrops(); // 사진을 첨부 칸 밖에 떨어뜨려도 새 탭으로 열리지 않게
captureInstallPrompt(); // [앱 설치] 메뉴용 — 설치 창 이벤트를 미리 잡아 둠
registerServiceWorker(); // 화면 파일 저장·오프라인 안내·새 버전 알림 (프로덕션 빌드에서만)

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);

// 글꼴 선언(Pretendard·Black Han Sans, src/styles/fonts.css)은 화면 표시를 막지 않게 첫 화면을 그린 뒤 따로 불러온다.
// 오기 전에는 시스템 글꼴로 먼저 보이고(font-display: swap) 오면 바뀐다. 실패해도 시스템 글꼴로 계속 쓸 수 있다.
import('./styles/fonts.css').catch(() => {});
