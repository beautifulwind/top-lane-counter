import { useEffect, useId, useRef, useState } from 'react';
import {
  SEQ_KEYS, SEQ_MAX, maxSkillMismatch, nextKeyProblem, seqMode, seqProgress,
} from '../lib/skillSequence';

/**
 * 스킬 찍는 순서 상세 입력 (065, SPEC 6-80). 선마(Q/W/E)와 따로 — 둘 다 쓸 수 있다.
 * value: "QEWQ…" (빈 글자 = 없음), onChange(새 글자 줄), champion: 플레이할 챔피언 id (예외 표), maxSkill: 고른 선마 (어긋나면 안내만)
 * 칸은 하나씩: 적은 칸 + 깜빡이는 다음 칸 하나. 큰 [Q][W][E][R] 버튼, PC는 이 칸 안에서 q·w·e·r 키(Backspace = 하나 지우기).
 * 규칙에 안 맞는 버튼은 흐리게(aria-disabled) 두되 눌리게 하고, 누르면 이유를 보여 준다 (6-79와 같은 방식).
 * 고치기는 "여기부터 다시"만: [← 하나 지우기], 적은 칸을 누르면 그 칸부터 지우고 다시 쓰기, [전부 지우기].
 * 예외 챔피언(loose)은 형식만 본다. hidden 챔피언은 부르는 쪽이 그리지 않는다.
 */
export default function SkillSequenceInput({ value = '', onChange, champion, maxSkill }) {
  const [open, setOpen] = useState(!!value);
  const [msg, setMsg] = useState(null); // { text, alert, n } — n: 같은 문구도 다시 읽히게
  const keysRef = useRef(null);
  const focusKeys = useRef(false);
  const panelId = useId();
  const loose = seqMode(champion) === 'loose';
  const mismatch = maxSkillMismatch(value, maxSkill);

  useEffect(() => {
    if (focusKeys.current) {
      focusKeys.current = false;
      keysRef.current?.querySelector('button')?.focus();
    }
  });

  const say = (text, alert = false) => setMsg((m) => ({ text, alert, n: (m?.n ?? 0) + 1 }));

  const press = (k) => {
    const why = nextKeyProblem(value, k, champion);
    if (why) {
      say(why, true);
      return;
    }
    setMsg(null);
    onChange(value + k);
  };
  const back = () => {
    if (!value) return;
    if (value.length === 1) focusKeys.current = true; // 지우기 버튼이 꺼지므로 초점을 스킬 버튼으로
    setMsg(null);
    onChange(value.slice(0, -1));
  };
  const cutAt = (i) => {
    focusKeys.current = true; // 누른 칸이 사라지므로
    say(`${i + 1}렙부터 다시 적어 주세요.`);
    onChange(value.slice(0, i));
  };
  const clear = () => {
    focusKeys.current = true;
    say('적은 순서를 모두 지웠습니다.');
    onChange('');
  };
  const onKey = (e) => {
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    const k = e.key.toUpperCase();
    if (SEQ_KEYS.includes(k)) {
      e.preventDefault();
      press(k);
    } else if (e.key === 'Backspace') {
      e.preventDefault();
      back();
    }
  };

  const toggle = () => {
    if (!open) focusKeys.current = true;
    setOpen(!open);
  };

  return (
    <div className="seq-input">
      <button type="button" className="btn btn-small" aria-expanded={open} aria-controls={panelId} onClick={toggle}>
        {open ? '상세 순서 접기' : '상세하게 작성'}
      </button>
      {!open && value && <small className="hint">{seqProgress(value)}</small>}
      {open && (
        // 안의 버튼에 초점이 있을 때 q·w·e·r 키 입력
        <div id={panelId} className="seq-panel" role="group" aria-label="스킬 찍는 순서 (상세)" onKeyDown={onKey}>
          <small className="hint">
            1렙부터 찍는 스킬을 차례로 눌러 주세요. 원하는 레벨까지만 적어도 됩니다. R(궁)도 직접 눌러 주세요.
            PC에서는 q·w·e·r 키로도 적을 수 있습니다.
          </small>
          {loose && (
            <small className="hint">이 챔피언은 스킬 찍는 규칙이 달라 레벨 규칙은 검사하지 않습니다. Q·W·E·R을 {SEQ_MAX}칸까지 적을 수 있습니다.</small>
          )}

          <ol className="seq-slots" aria-label="적은 순서 (칸을 누르면 그 레벨부터 다시 적기)">
            {[...value].map((c, i) => (
              <li key={i}>
                <span className="seq-lv" aria-hidden="true">{i + 1}</span>
                <button
                  type="button"
                  className={`seq-slot${c === 'R' ? ' r' : ''}`}
                  onClick={() => cutAt(i)}
                  aria-label={`${i + 1}렙 ${c} (누르면 ${i + 1}렙부터 다시 적기)`}
                  title={`${i + 1}렙부터 다시 적기`}
                >
                  {c}
                </button>
              </li>
            ))}
            {value.length < SEQ_MAX && (
              <li aria-hidden="true">
                <span className="seq-lv">{value.length + 1}</span>
                <span className="seq-slot next" />
              </li>
            )}
          </ol>

          <div className="seq-keys" ref={keysRef}>
            {SEQ_KEYS.map((k) => {
              const why = nextKeyProblem(value, k, champion);
              return (
                <button
                  key={k}
                  type="button"
                  className={`seq-key${k === 'R' ? ' r' : ''}${why ? ' is-disabled' : ''}`}
                  aria-disabled={why ? true : undefined}
                  aria-label={why ? `${k} (지금은 찍을 수 없음)` : `${value.length + 1}렙에 ${k}`}
                  onClick={() => press(k)}
                >
                  {k}
                </button>
              );
            })}
          </div>
          <div className="seq-tools">
            <button type="button" className="btn btn-small" onClick={back} disabled={!value}>← 하나 지우기</button>
            <button type="button" className="btn btn-small" onClick={clear} disabled={!value}>전부 지우기</button>
          </div>

          <p className="seq-progress" role="status">{seqProgress(value)}</p>
          {msg && (
            <p key={msg.n} className={`vote-notice ${msg.alert ? 'vote-notice-error' : 'vote-notice-info'}`} role={msg.alert ? 'alert' : 'status'}>
              {msg.text}
            </p>
          )}
          {mismatch && <p className="hint seq-mismatch" role="note">{mismatch}</p>}
        </div>
      )}
    </div>
  );
}
