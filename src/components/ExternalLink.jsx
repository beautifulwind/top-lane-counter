import { useEffect, useId, useRef, useState } from 'react';
import { LEAVE_TEXT, LINK_REL, siteName } from '../lib/links';

/**
 * 장인 외부 링크 (047, SPEC 6-34). 새 창 + rel="noopener noreferrer nofollow ugc".
 * 누르면 바로 가지 않고 확인 창: "탑신병자를 떠나 외부 사이트로 이동합니다. 주소를 확인하세요." + 전체 주소 + [이동] [취소].
 * 사이트 이름(유튜브·치지직…)을 글자 칸으로 앞에 붙인다. children이 없으면 사이트 이름 + 주소 일부를 글자로 쓴다.
 */
export default function ExternalLink({ link, domains, children, className = '' }) {
  const [asking, setAsking] = useState(false);
  const opener = useRef(null);
  const site = siteName(link.host, domains);
  const ask = (e) => {
    e.preventDefault();
    setAsking(true);
  };
  return (
    <>
      <a
        ref={opener}
        href={link.url}
        target="_blank"
        rel={LINK_REL}
        className={`ext-link ${className}`.trim()}
        onClick={ask}
        onAuxClick={(e) => { if (e.button === 1) ask(e); }}
      >
        <span className="ext-site">{site}</span>{' '}
        <span className="ext-text">{children ?? shortUrl(link.url)}</span>
        <span className="sr-only"> (외부 사이트, 새 창)</span>
      </a>
      {asking && <LeaveDialog link={link} site={site} opener={opener} onClose={() => setAsking(false)} />}
    </>
  );
}

/** "https://www.youtube.com/@faker" → "youtube.com/@faker" (40자 넘으면 줄임) */
export function shortUrl(url) {
  const s = String(url).replace(/^https:\/\//i, '').replace(/^www\./i, '');
  return s.length > 40 ? `${s.slice(0, 39)}…` : s;
}

function LeaveDialog({ link, site, opener, onClose }) {
  const panel = useRef(null);
  const cancelBtn = useRef(null);
  const titleId = useId();
  useEffect(() => {
    cancelBtn.current?.focus(); // 실수로 Enter를 눌러도 이동하지 않게 [취소]에 초점
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
    const list = [...panel.current.querySelectorAll('button, a[href]')];
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
    // eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions
    <div className="dialog-backdrop" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <div ref={panel} className="dialog-panel leave-dialog" role="alertdialog" aria-modal="true" aria-labelledby={titleId} onKeyDown={onKeyDown}>
        <h2 id={titleId} className="dialog-title">외부 사이트로 이동</h2>
        <p>{LEAVE_TEXT}</p>
        <p className="leave-site"><span className="ext-site">{site}</span> <code className="leave-url">{link.url}</code></p>
        <div className="actions">
          <a href={link.url} target="_blank" rel={LINK_REL} className="btn btn-primary" onClick={() => onClose()}>이동</a>
          <button ref={cancelBtn} type="button" className="btn" onClick={onClose}>취소</button>
        </div>
      </div>
    </div>
  );
}
