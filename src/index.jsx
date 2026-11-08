import React from 'react';
import ReactDOM from 'react-dom/client';
import 'pretendard/dist/web/variable/pretendardvariable-dynamic-subset.css'; // 한글 글꼴 (사이트 안에 넣음, 쓰는 글자 조각만 받음)
import '@fontsource/black-han-sans/400.css'; // 제목 글꼴 (사이트 안에 넣음, 쓰는 글자 조각만 받음)
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
