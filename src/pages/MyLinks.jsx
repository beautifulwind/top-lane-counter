import { useState } from 'react';
import { Link } from 'react-router-dom';
import { getMyLinks, setProfileLinks } from '../api/links';
import { getChampionMap } from '../api/ddragon';
import { RequireLogin } from '../components/RequireOperator';
import { ErrorBox, Loading } from '../components/Status';
import SectionHead from '../components/SectionHead';
import ExternalLink from '../components/ExternalLink';
import { LinkIcon, LayersIcon } from '../components/Icons';
import { useAuth } from '../lib/auth';
import { linkProblem, siteName } from '../lib/links';
import { matchupShort } from '../lib/josa';
import { buildLabel } from '../lib/wikiBuild';
import { useAsync } from '../lib/useAsync';

/**
 * 장인 링크 관리 (047, SPEC 6-34 · /me/links): 인증된 장인이 프로필 링크(최대 5개)를 더하고 고치고 지운다.
 * 허용 사이트를 안내하고, 안 되는 주소는 칸 바로 아래에 이유를 쉬운 말로 보여 준다(같은 기준을 DB가 다시 검사).
 * 빌드 링크는 각 빌드 화면의 "장인 링크" 칸에서 정한다 — 여기서는 목록만 보여 준다.
 */
export default function MyLinks() {
  return (
    <RequireLogin>
      <LinksPage />
    </RequireLogin>
  );
}

function LinksPage() {
  const auth = useAuth();
  const [notice, setNotice] = useState(null); // 저장 뒤 다시 읽는 동안에도 남도록 화면 쪽에 둔다
  const { data, error, loading, retry } = useAsync(async () => {
    const [mine, champs] = await Promise.all([getMyLinks(), getChampionMap().catch(() => ({}))]);
    return { mine, champs };
  }, [auth.user.id]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const { mine, champs } = data;

  return (
    <article className="me-page">
      <nav className="crumbs"><Link to="/me">마이페이지</Link> › 링크 관리</nav>
      <h1 className="doc-title">장인 링크 관리</h1>
      {!mine.influencer ? (
        <div className="inf-guide">
          <p>링크는 <strong>인증된 장인</strong>만 올릴 수 있습니다.</p>
          <p><Link to="/me/influencer">장인 인증 신청하기</Link></p>
        </div>
      ) : (
        <>
          <p className="hint">
            내 채널·SNS 주소를 올리면 <Link to={`/u/${auth.user.id}`}>내 공개 프로필</Link>에 보입니다.
            누르는 사람에게는 &quot;외부 사이트로 이동합니다&quot; 확인 창이 먼저 뜹니다.
          </p>
          {notice && <p className="notice" role="status">{notice}</p>}
          <ProfileLinksForm
            key={mine.profile.map((l) => l.id).join(',')}
            mine={mine}
            onEdit={() => setNotice(null)}
            onSaved={() => { setNotice('저장했습니다.'); retry(); }}
          />
          <BuildLinks mine={mine} champs={champs} />
        </>
      )}
    </article>
  );
}

function SiteGuide({ domains }) {
  const names = [];
  for (const d of domains) {
    const n = siteName(d.domain, domains);
    if (!names.includes(n)) names.push(n);
  }
  return (
    <div className="inf-guide">
      <p><strong>올릴 수 있는 사이트</strong></p>
      <ul className="site-list" aria-label="올릴 수 있는 사이트">
        {names.map((n) => <li key={n}><span className="ext-site">{n}</span></li>)}
      </ul>
      <p className="hint">
        https://로 시작하는 주소만 됩니다. 브라우저 주소창의 주소를 그대로 복사해 붙여 넣어 주세요.
        단축 주소(bit.ly 등)나 다른 사이트로 넘겨주는 주소는 올릴 수 없습니다.
      </p>
    </div>
  );
}

function ProfileLinksForm({ mine, onEdit, onSaved }) {
  const [rows, setRows] = useState(() => mine.profile.map((l) => l.url));
  const [shown, setShown] = useState(false); // [저장]을 누른 뒤부터 칸마다 이유를 보여 준다
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const max = mine.max ?? 5;
  const saved = Object.fromEntries(mine.profile.map((l) => [l.url, l]));
  const problems = rows.map((u) => (u.trim() ? linkProblem(u, mine.domains) : null));
  const dup = rows.map((u, i) => !!u.trim() && rows.findIndex((v) => v.trim().toLowerCase() === u.trim().toLowerCase()) < i);

  const change = (i, v) => setRows(rows.map((r, j) => (j === i ? v : r)));
  const move = (i, d) => {
    const next = [...rows];
    [next[i], next[i + d]] = [next[i + d], next[i]];
    setRows(next);
  };
  const save = async (e) => {
    e.preventDefault();
    setShown(true);
    onEdit();
    if (problems.some(Boolean) || dup.some(Boolean)) {
      setError('고칠 칸이 있습니다. 칸 아래 안내를 확인해 주세요.');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await setProfileLinks(rows);
      onSaved();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="me-section" aria-labelledby="profile-links">
      <SectionHead icon={LinkIcon} id="profile-links" count={rows.filter((r) => r.trim()).length}>프로필 링크 (최대 {max}개)</SectionHead>
      <SiteGuide domains={mine.domains} />
      <form className="inf-form" onSubmit={save} noValidate>
        {rows.length === 0 && <p className="empty">아직 올린 링크가 없습니다.</p>}
        {rows.map((u, i) => {
          const msg = shown ? (problems[i] ?? (dup[i] ? '위 칸과 같은 주소입니다.' : null)) : null;
          const old = saved[u.trim()];
          return (
            // eslint-disable-next-line react/no-array-index-key
            <div key={i}>
              <label htmlFor={`link-${i}`} className="sr-only">링크 {i + 1}</label>
              <div className="link-edit-row">
                <input
                  id={`link-${i}`}
                  type="url"
                  inputMode="url"
                  autoComplete="off"
                  placeholder="https://www.youtube.com/@내채널"
                  value={u}
                  onChange={(e) => change(i, e.target.value)}
                  aria-invalid={msg ? 'true' : undefined}
                  aria-describedby={msg ? `link-${i}-problem` : undefined}
                />
                <button type="button" className="btn btn-small" onClick={() => move(i, -1)} disabled={i === 0} aria-label={`링크 ${i + 1} 위로`}>↑</button>
                <button type="button" className="btn btn-small" onClick={() => move(i, 1)} disabled={i === rows.length - 1} aria-label={`링크 ${i + 1} 아래로`}>↓</button>
                <button type="button" className="btn btn-small" onClick={() => setRows(rows.filter((_, j) => j !== i))} aria-label={`링크 ${i + 1} 지우기`}>지우기</button>
              </div>
              {msg && <p id={`link-${i}-problem`} className="link-problem" role="alert">{msg}</p>}
              {old && old.visible === false && (
                <p className="link-hidden-note">지금은 다른 사람에게 보이지 않습니다. (허용 사이트에서 빠진 사이트입니다)</p>
              )}
            </div>
          );
        })}
        <div className="row-actions">
          <button type="button" className="btn" onClick={() => setRows([...rows, ''])} disabled={rows.length >= max}>+ 링크 추가</button>
          <button type="submit" className="btn btn-primary" disabled={busy}>{busy ? '저장하는 중…' : '저장'}</button>
        </div>
        {rows.length >= max && <p className="hint">프로필 링크는 {max}개까지 올릴 수 있습니다.</p>}
        {error && <p className="form-error" role="alert">{error}</p>}
      </form>
    </section>
  );
}

function BuildLinks({ mine, champs }) {
  const name = (id) => champs?.[id]?.name ?? id;
  return (
    <section className="me-section" aria-labelledby="build-links">
      <SectionHead icon={LayersIcon} id="build-links" count={mine.builds.length}>빌드 링크</SectionHead>
      <p className="hint">
        내가 처음 만든 빌드마다 링크 1개를 달 수 있습니다. 빌드 화면 아래의 &quot;장인 링크&quot; 칸에서 정하고 고칩니다.
        (빌드 내용 수정과는 따로라, 다른 분이 빌드를 고쳐도 링크는 그대로입니다)
      </p>
      {mine.builds.length === 0 ? (
        <p className="empty">빌드에 단 링크가 없습니다.</p>
      ) : (
        <ul className="link-list">
          {mine.builds.map((l) => (
            <li key={l.id}>
              <Link to={`/champion/${l.target_champion}/counter/${l.counter_champion}?build=${l.build_id}`}>
                {matchupShort(name(l.counter_champion), name(l.target_champion))} · {buildLabel(l)}
              </Link>
              <div><ExternalLink link={l} domains={mine.domains} /></div>
              {!l.visible && <p className="link-hidden-note">지금은 다른 사람에게 보이지 않습니다. (빌드·상대법이 숨겨졌거나 허용 사이트에서 빠졌습니다)</p>}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
