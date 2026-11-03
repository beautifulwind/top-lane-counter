import BuildCard from './BuildCard';
import { REQUIRED_LEVELS } from '../lib/docContent';

/**
 * 매치업 문서 모양 (읽기 전용, 022 순서): 한 줄 요약 + 빌드 + 레벨별 딜교법 + 특이사항 (번호는 있는 섹션만 차례로).
 * 운영자 미리보기, 내 제안·빌드 상세보기가 같이 쓴다 (매치업 문서는 섹션마다 버튼이 있어 LevelList만 쓴다).
 * doc: { summary, level_notes, lane_cautions } | null (글 섹션을 뺀다)
 * builds: BuildCard에 넘길 빌드들 (author 포함) | null (빌드 섹션을 뺀다), game: Data Dragon { items, runes, spells, latest }
 */
export default function DocView({ doc, builds = null, game, emptyBuilds = '등록된 빌드가 없어요.' }) {
  let n = 0;
  return (
    <>
      {doc?.summary && <p className="doc-summary">{doc.summary}</p>}
      {builds && (
        <section className="section">
          <h2 className="section-title"><span className="num">{++n}.</span> 빌드</h2>
          {builds.length === 0 ? (
            <p className="empty">{emptyBuilds}</p>
          ) : (
            builds.map((b, i) => <BuildCard key={b.id ?? i} build={b} {...game} />)
          )}
        </section>
      )}
      {doc && (
        <>
          <section className="section">
            <h2 className="section-title"><span className="num">{++n}.</span> 레벨별 딜교법</h2>
            <LevelList doc={doc} />
          </section>
          <section className="section">
            <h2 className="section-title"><span className="num">{++n}.</span> 특이사항</h2>
            {doc.lane_cautions ? <div className="prose">{doc.lane_cautions}</div> : <p className="empty">아직 작성된 내용이 없어요.</p>}
          </section>
        </>
      )}
    </>
  );
}

/** 레벨별 딜교법 목록 */
export function LevelList({ doc }) {
  const levels = doc
    ? Object.entries(doc.level_notes ?? {})
        .map(([lv, text]) => [Number(lv), text])
        .sort((a, b) => a[0] - b[0])
    : [];
  if (levels.length === 0) return <p className="empty">아직 작성된 내용이 없어요.</p>;
  return (
    <dl className="level-list">
      {levels.map(([lv, text]) => (
        <div key={lv} className={REQUIRED_LEVELS.includes(lv) ? 'level req' : 'level'}>
          <dt>{lv}레벨</dt>
          <dd>{text}</dd>
        </div>
      ))}
    </dl>
  );
}
