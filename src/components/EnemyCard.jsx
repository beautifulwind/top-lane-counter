import { CrosshairIcon } from './Icons';

/**
 * 상대 챔피언 빨간 카드 (2단계 디자인, 예전 앱 "예상 상대 탑"): 빨강 → 카드색 그라데이션 + 빨간 테두리,
 * 조준 아이콘 + 빨간 작은 제목, 빨간 테두리 초상화. 제목(h1 등)은 children으로.
 */
export default function EnemyCard({ champ, label = '상대 챔피언', children }) {
  return (
    <header className="enemy-card">
      <p className="enemy-label"><CrosshairIcon size={16} /> {label}</p>
      <div className="enemy-body">
        <img src={champ.icon} alt="" width="64" height="64" className="enemy-portrait" />
        <div className="enemy-text">{children}</div>
      </div>
    </header>
  );
}
