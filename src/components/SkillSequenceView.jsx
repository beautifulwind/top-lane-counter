import { useId, useState } from 'react';
import { seqSpoken, toSeq } from '../lib/skillSequence';

/**
 * 스킬 찍는 순서 보기 (065, SPEC 6-80): 빌드 카드 스킬 줄의 "선마 [Q]" 옆 [상세하게 보기].
 * 누르면 작은 글자 칸이 이어서 나온다 (R은 주황, 6칸마다 살짝 띄움, 좁으면 다음 줄로). 순서가 없으면 아무것도 그리지 않는다.
 * 스크린리더는 칸 대신 "1렙 Q, 2렙 E, …" 한 문장을 읽는다.
 */
export default function SkillSequenceView({ sequence }) {
  const seq = toSeq(sequence);
  const [open, setOpen] = useState(false);
  const id = useId();
  if (!seq) return null;
  return (
    <>
      <button type="button" className="link-btn seq-toggle" aria-expanded={open} aria-controls={id} onClick={() => setOpen(!open)}>
        {open ? '상세 접기' : '상세하게 보기'}
      </button>
      {open && (
        <div id={id} className="seq-view">
          <span className="sr-only">{`스킬 순서: ${seqSpoken(seq)}`}</span>
          <ol className="seq-chips" aria-hidden="true">
            {[...seq].map((c, i) => (
              <li key={i} className={c === 'R' ? 'r' : undefined} title={`${i + 1}렙 ${c}`}>{c}</li>
            ))}
          </ol>
        </div>
      )}
    </>
  );
}
