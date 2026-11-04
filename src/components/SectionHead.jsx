/**
 * 섹션 제목 (2단계 디자인): [아이콘] 번호. 제목 + 옆에 "N개" 알약.
 * 아이콘은 꾸밈(aria-hidden), 알약은 제목(h2) 밖에 둬서 제목 이름은 "1. 빌드"처럼 그대로 읽힌다.
 * icon: Icons.jsx의 선 아이콘, num: 번호(없으면 생략), count: 개수(없으면 알약 없음), id: h2 id
 */
export default function SectionHead({ icon: Icon, num, count, id, children }) {
  return (
    <div className="section-head">
      <h2 className="section-title" id={id}>
        {Icon && <Icon size={22} className="title-icon" />}
        {num != null && <span className="num">{num}.</span>} {children}
      </h2>
      {count != null && <span className="count-badge">{count}개</span>}
    </div>
  );
}
