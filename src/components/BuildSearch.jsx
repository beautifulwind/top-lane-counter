import { useEffect, useId, useMemo, useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { getSearchIndex } from '../api/searchIndex';
import { searchAll, tokenize } from '../lib/championSearch';
import { matchupShort } from '../lib/josa';
import { SearchIcon } from './Icons';

export const NO_RESULT = '맞는 결과가 없습니다. 챔피언 이름(별명·초성도 됩니다)이나 빌드 제목의 일부를 띄어쓰기로 나눠 넣어 보세요.';
export const INDEX_ERROR = '조합·빌드 목록을 불러오지 못했습니다. 챔피언 검색은 그대로 쓸 수 있습니다.';

/**
 * 홈 검색창 (SPEC 6-61). 입력창은 기존 챔피언 검색칸 그대로, 아래에 후보 목록(챔피언 / 상대법 / 빌드)이 바로 뜬다.
 * 요청은 키 입력마다 보내지 않는다: 챔피언은 이미 받아 둔 목록, 조합·빌드는 처음 입력할 때 한 번 받아 10분 캐시(api/searchIndex.js).
 * 키보드: ↑↓ 후보 이동, Enter 이동, Esc 목록 닫기. 목록은 입력칸 바로 아래 흐름 안에 있어(떠 있지 않아) 모바일 키보드에 가려지지 않는다.
 */
export default function BuildSearch({ champions, value, onChange }) {
  const id = useId();
  const navigate = useNavigate();
  const [index, setIndex] = useState(null);
  const [indexError, setIndexError] = useState(false);
  const [active, setActive] = useState(-1);
  const [closed, setClosed] = useState(false);
  const asked = useRef(false);
  const tokens = useMemo(() => tokenize(value), [value]);
  const key = tokens.join(' ');

  const load = () => {
    asked.current = true;
    getSearchIndex().then((i) => { setIndex(i); setIndexError(false); }, () => setIndexError(true));
  };
  useEffect(() => { if (tokens.length > 0 && !asked.current) load(); }, [tokens.length]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { setActive(-1); setClosed(false); }, [key]);

  const res = useMemo(() => searchAll(tokens, champions, index), [tokens, champions, index]); // eslint-disable-line react-hooks/exhaustive-deps

  // 위에서부터 이어 붙인 후보 (키보드 이동 순서 = 화면 순서)
  const options = [];
  const add = (o) => { options.push({ ...o, id: `${id}-o${options.length}` }); return options[options.length - 1]; };
  const champRows = res.champions.map((c) => add({ to: `/champion/${c.id}`, champ: c }));
  const comboRows = res.combos.map((r) => add({ to: `/champion/${r.target.id}/counter/${r.mine.id}`, combo: r }));
  const missingRow = res.missing ? add({ to: `/matchup/new?target=${res.missing.target.id}&mine=${res.missing.mine.id}`, missing: res.missing }) : null;
  const buildRows = res.builds.map((r) => add({ to: `/champion/${r.target.id}/counter/${r.mine.id}?build=${r.build.id}`, found: r }));

  const open = tokens.length > 0 && !closed;
  const waiting = tokens.length > 0 && !index && !indexError;
  const empty = options.length === 0;

  const onKeyDown = (e) => {
    if (e.key === 'Escape') {
      if (open) { e.preventDefault(); setClosed(true); setActive(-1); }
      return;
    }
    if (!open || options.length === 0) {
      if (e.key === 'Enter') e.preventDefault();
      return;
    }
    if (e.key === 'ArrowDown') { e.preventDefault(); setActive((i) => (i + 1) % options.length); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); setActive((i) => (i <= 0 ? options.length - 1 : i - 1)); }
    else if (e.key === 'Enter') {
      e.preventDefault();
      navigate(options[active >= 0 ? active : 0].to);
    }
  };

  const optProps = (o) => ({
    id: o.id, role: 'option', 'aria-selected': options[active]?.id === o.id, className: options[active]?.id === o.id ? 'bs-opt on' : 'bs-opt',
    onMouseEnter: () => setActive(options.indexOf(o)),
  });

  return (
    <div className="bs">
      <div className="search">
      <SearchIcon size={18} className="search-icon" />
      <input
        type="search" value={value} onChange={(e) => { onChange(e.target.value); }} onFocus={load} onKeyDown={onKeyDown}
        placeholder="챔피언·빌드 검색 (예: 퀸 다리우스, ㄷㄹㅇㅅ)" aria-label="챔피언·빌드 검색" autoComplete="off" enterKeyHint="go"
        role="combobox" aria-expanded={open && !empty} aria-controls={`${id}-list`} aria-autocomplete="list"
        aria-activedescendant={open && active >= 0 ? options[active]?.id : undefined}
      />
      </div>
      {open && (
        <div className="bs-panel" id={`${id}-list`} role="listbox" aria-label="검색 후보">
          {champRows.length > 0 && (
            <div role="group" aria-label="챔피언">
              <p className="bs-head" aria-hidden="true">챔피언</p>
              {champRows.map((o) => (
                <Link key={o.id} to={o.to} {...optProps(o)}>
                  <img src={o.champ.icon} alt="" width="36" height="36" loading="lazy" />
                  <span className="bs-text"><strong>{o.champ.name}</strong><small>{o.champ.title}</small></span>
                </Link>
              ))}
            </div>
          )}
          {(comboRows.length > 0 || missingRow) && (
            <div role="group" aria-label="상대법">
              <p className="bs-head" aria-hidden="true">상대법</p>
              {comboRows.map((o) => (
                <Link key={o.id} to={o.to} {...optProps(o)}>
                  <img src={o.combo.mine.icon} alt="" width="36" height="36" loading="lazy" />
                  <span className="bs-text">
                    <strong>{matchupShort(o.combo.mine.name, o.combo.target.name)}</strong>
                    <small>
                      {o.combo.reverse ? '입력과 반대 방향 · ' : ''}{o.combo.builds > 0 ? `빌드 ${o.combo.builds}개` : '빌드가 아직 없습니다'}
                    </small>
                  </span>
                </Link>
              ))}
              {missingRow && (
                <Link {...optProps(missingRow)} to={missingRow.to}>
                  <img src={missingRow.missing.mine.icon} alt="" width="36" height="36" loading="lazy" />
                  <span className="bs-text">
                    <strong>{matchupShort(missingRow.missing.mine.name, missingRow.missing.target.name)}</strong>
                    <small>아직 없음 · 직접 쓰기</small>
                  </span>
                </Link>
              )}
            </div>
          )}
          {buildRows.length > 0 && (
            <div role="group" aria-label="빌드">
              <p className="bs-head" aria-hidden="true">빌드</p>
              {buildRows.map((o) => (
                <Link key={o.id} to={o.to} {...optProps(o)}>
                  <img src={o.found.mine.icon} alt="" width="36" height="36" loading="lazy" />
                  <span className="bs-text">
                    <strong>
                      {o.found.build.influencer && <><span className="inf-build-tag">장인 빌드</span>{' '}</>}
                      {o.found.build.title || `빌드 ${o.found.build.seq ?? ''}`.trim()}
                    </strong>
                    {o.found.build.summary && <small className="bs-summary">{o.found.build.summary}</small>}
                    <small>{matchupShort(o.found.mine.name, o.found.target.name)}</small>
                  </span>
                </Link>
              ))}
            </div>
          )}
          {waiting && <p className="bs-note" role="status">조합·빌드 목록을 불러오는 중…</p>}
          {indexError && <p className="bs-note" role="status">{INDEX_ERROR}</p>}
          {empty && !waiting && <p className="bs-note" role="status">{NO_RESULT}</p>}
        </div>
      )}
    </div>
  );
}
