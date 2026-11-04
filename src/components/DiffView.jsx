import { docDiff, lineDiff } from '../lib/diff';

/**
 * 기존 문서(before, 없으면 null = 새 문서) ↔ 바뀐 문서(after) 비교.
 * 바뀐 칸은 줄 단위로 − 지운 줄 / + 더한 줄, 바뀌지 않은 칸은 접어 둔다.
 */
export default function DiffView({ before, after }) {
  const fields = docDiff(before, after);
  const changed = fields.filter((f) => f.changed);
  const same = fields.filter((f) => !f.changed);
  return (
    <div className="diff">
      {changed.length === 0 && <p className="empty">바뀐 칸이 없습니다.</p>}
      {changed.map((f) => (
        <section key={f.key} className="diff-field" aria-label={`${f.label} 변경`}>
          <h3>
            {f.label}{' '}
            <span className="diff-tag">{!f.before ? '새로 씀' : !f.after ? '삭제' : '수정'}</span>
          </h3>
          <pre className="diff-lines">
            {lineDiff(f.before, f.after).map((l, i) => (
              <span key={i} className={`diff-line ${l.type}`}>
                {l.type === 'add' ? '+ ' : l.type === 'del' ? '− ' : '  '}
                {l.text}
                {'\n'}
              </span>
            ))}
          </pre>
        </section>
      ))}
      {before && same.length > 0 && (
        <details className="diff-same">
          <summary>바뀌지 않은 칸 {same.length}개 보기</summary>
          {same.map((f) => (
            <div key={f.key} className="diff-field">
              <h3>{f.label}</h3>
              <pre className="diff-lines">{f.after || '(비어 있음)'}</pre>
            </div>
          ))}
        </details>
      )}
    </div>
  );
}
