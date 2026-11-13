import { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { searchInfluencers } from '../api/follow';
import { INFLUENCER_KINDS } from '../lib/nickname';
import { InfluencerName } from './UserName';

/** 입력을 멈추고 이만큼 기다렸다가 찾는다 (글자마다 요청하지 않게) */
export const SEARCH_WAIT_MS = 300;
export const NO_RESULT_TEXT = '찾는 장인이 없습니다. 닉네임의 일부만 넣어 다시 찾아보세요.';

/**
 * ☰ 메뉴 [장인찾기] 아래 검색 칸 (050, SPEC 6-36). 로그인하지 않아도 쓸 수 있다.
 * 한 글자 이상(앞뒤 빈칸 빼고, 20자까지) → 입력을 멈추고 0.3초 뒤 search_influencers. 늦게 온 옛 결과는 버린다.
 * 결과: 장인 표시 + 닉네임 · 유형 · 팔로워 N명, 누르면 장인 페이지(/u/:id). 20개씩 [더보기].
 * 아래에 [내가 팔로우한 장인의 빌드 보기] → /following. onGo: 링크를 눌러 이동할 때 메뉴를 닫는다.
 */
export default function InfluencerSearch({ id, onGo }) {
  const [q, setQ] = useState('');
  const [res, setRes] = useState(null); // { query, items, total, page }
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const seq = useRef(0);
  const input = useRef(null);
  const term = q.trim();

  useEffect(() => { input.current?.focus(); }, []);

  useEffect(() => {
    const my = ++seq.current;
    setError(null);
    if (!term) {
      setRes(null);
      setBusy(false);
      return undefined;
    }
    setBusy(true);
    const t = setTimeout(async () => {
      try {
        const r = await searchInfluencers(term, 1);
        if (my === seq.current) setRes({ query: term, items: r.items, total: Number(r.total) || 0, page: 1 });
      } catch (e) {
        if (my === seq.current) setError(e.message);
      } finally {
        if (my === seq.current) setBusy(false);
      }
    }, SEARCH_WAIT_MS);
    return () => clearTimeout(t);
  }, [term]);

  const more = async () => {
    const my = seq.current;
    setBusy(true);
    try {
      const r = await searchInfluencers(res.query, res.page + 1);
      if (my !== seq.current) return;
      setRes((s) => ({ ...s, items: [...s.items, ...r.items.filter((x) => !s.items.some((y) => y.id === x.id))], total: Number(r.total) || 0, page: s.page + 1 }));
    } catch (e) {
      if (my === seq.current) setError(e.message);
    } finally {
      if (my === seq.current) setBusy(false);
    }
  };

  return (
    <div className="inf-search" id={id} role="search" aria-label="장인찾기">
      <label className="sr-only" htmlFor={`${id}-q`}>장인 닉네임</label>
      <input
        ref={input} id={`${id}-q`} type="search" className="inf-search-input" value={q} maxLength={20}
        placeholder="장인 닉네임" autoComplete="off" enterKeyHint="search"
        onChange={(e) => setQ(e.target.value)}
        onKeyDown={(e) => { if (e.key === 'Enter') e.preventDefault(); }}
      />
      <div className="inf-search-result" aria-live="polite">
        {!term && <p className="hint">장인 닉네임을 한 글자 이상 넣어 주세요.</p>}
        {term && busy && !res && <p className="hint">찾는 중…</p>}
        {error && <p className="form-error" role="alert">{error}</p>}
        {res && res.query === term && !error && (res.items.length === 0 ? (
          <p className="empty">{NO_RESULT_TEXT}</p>
        ) : (
          <>
            <p className="sr-only">장인 {res.total}명</p>
            <ul className="inf-search-list">
              {res.items.map((p) => (
                <li key={p.id}>
                  <Link to={`/u/${p.id}`} className="inf-search-row" onClick={onGo}>
                    <span className="inf-search-name"><InfluencerName profile={p} /></span>
                    <small className="muted">
                      {INFLUENCER_KINDS[p.influencer] ?? '장인'} · 팔로워 {Number(p.follower_count ?? 0).toLocaleString()}명
                    </small>
                  </Link>
                </li>
              ))}
            </ul>
            {res.items.length < res.total && (
              <button type="button" className="btn btn-small inf-search-more" onClick={more} disabled={busy}>
                {busy ? '불러오는 중…' : `더보기 (${res.total - res.items.length}명 남음)`}
              </button>
            )}
          </>
        ))}
      </div>
      <Link to="/following" className="inf-search-following" onClick={onGo}>내가 팔로우한 장인의 빌드 보기</Link>
    </div>
  );
}
