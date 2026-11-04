import React from 'react';
import ReactDOM from 'react-dom/client';
import './styles/tokens.css';
import './index.css';
import App from './App';
import { blockStrayFileDrops } from './components/Media';

blockStrayFileDrops(); // 사진을 첨부 칸 밖에 떨어뜨려도 새 탭으로 열리지 않게

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
