import { useEffect, useRef } from 'react';
import { getBuildContributors } from '../api/builds';
import { useAsync } from '../lib/useAsync';
import UserName from './UserName';
import { ErrorBox, Loading } from './Status';

/**
 * 시초 뱃지: 이 빌드를 처음 만든 사람. 닉네임 글자와 따로 그린 칸이라 닉네임에 "시초"를 넣어도 같은 모양이 되지 않는다
 * (닉네임은 글자만, 이 뱃지는 테두리·색이 있는 칸 + 읽는 이름 "시초(처음 만든 사람)").
 */
export function OriginBadge() {
  return (
    <span className="origin-badge" title="이 빌드를 처음 만든 사람">
      <span aria-hidden="true">시초</span>
      <span className="sr-only">시초(처음 만든 사람)</span>
    </span>
  );
}

/**
 * [수정 기록] 팝업: 이 빌드를 만들고 고친 사람들 (시초 먼저). 무엇을 고쳤는지(전후 내용)는 운영자만 따로 본다.
 * Esc·바깥 누르기·[닫기]로 닫히고, 닫히면 연 버튼으로 초점이 돌아간다 (opener = 연 버튼 ref).
 */
export default function ContributorsDialog({ build, title, onClose, opener }) {
  const { data, error, loading, retry } = useAsync(() => getBuildContributors(build.id), [build.id]);
  const panel = useRef(null);
  const closeBtn = useRef(null);

  useEffect(() => {
    closeBtn.current?.focus();
    const back = opener?.current;
    return () => back?.focus();
  }, [opener]);

  const onKeyDown = (e) => {
    if (e.key === 'Escape') {
      e.stopPropagation();
      onClose();
      return;
    }
    if (e.key !== 'Tab') return;
    // 초점을 팝업 안에 가둔다
    const list = [...panel.current.querySelectorAll('button, a[href]')].filter((el) => !el.disabled);
    const first = list[0];
    const last = list[list.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  };

  return (
    // 바깥(어두운 바탕)을 누르면 닫힌다. 키보드는 Esc·[닫기]
    // eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions
    <div className="dialog-backdrop" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <div
        ref={panel}
        className="dialog-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="contributors-title"
        onKeyDown={onKeyDown}
      >
        <h2 id="contributors-title" className="dialog-title">{title} 기여자</h2>
        <p className="hint">이 빌드를 만들고 고친 분들입니다. 시초는 처음 만든 분입니다.</p>
        {loading && <Loading />}
        {error && <ErrorBox error={error} onRetry={retry} />}
        {data && (data.length === 0 ? (
          <p className="empty">기여자 기록이 없습니다.</p>
        ) : (
          <ul className="contributor-list">
            {data.map((p, i) => (
              <li key={p.user_id ?? `gone-${i}`}>
                {p.user_id ? <UserName profile={p} /> : <span className="muted">(탈퇴한 유저)</span>}
                {p.is_origin && <>{' '}<OriginBadge /></>}
              </li>
            ))}
          </ul>
        ))}
        <div className="actions">
          <button ref={closeBtn} type="button" className="btn" onClick={onClose}>닫기</button>
        </div>
      </div>
    </div>
  );
}
