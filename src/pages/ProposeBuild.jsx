import { useState } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { SHARD_ROWS, getChampionMap, getItems, getLatestVersion, getRunes, getSummonerSpells } from '../api/ddragon';
import { getMatchup } from '../api/content';
import { getMyBuild, submitBuild } from '../api/builds';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { matchesQuery } from '../lib/chosung';
import { ITEM_LIMITS, SKILLS, SKILL_ORDERS, buildProblem, buildToForm, emptyBuild, patchMinor } from '../lib/buildContent';
import { ErrorBox, Loading } from '../components/Status';
import { RequireLogin } from '../components/RequireOperator';
import BuildCard, { Icon } from '../components/BuildCard';
import NotFound from './NotFound';

/**
 * 빌드 등록: /champion/:targetId/counter/:counterId/build/new[?from=내 빌드 id]
 * from: [이 빌드로 다시 쓰기] — 내 빌드 내용을 채워서 새 빌드로 보낸다 (원래 빌드는 그대로).
 */
export default function ProposeBuild() {
  return (
    <RequireLogin>
      <ProposeBuildForm />
    </RequireLogin>
  );
}

function ProposeBuildForm() {
  const { targetId, counterId } = useParams();
  const [search] = useSearchParams();
  const fromId = Number(search.get('from')) || null;
  const auth = useAuth();
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, matchup, items, runes, spells, latest, from] = await Promise.all([
      getChampionMap(), getMatchup(targetId, counterId), getItems(), getRunes(), getSummonerSpells(), getLatestVersion(),
      fromId ? getMyBuild(auth.user.id, fromId) : null,
    ]);
    return { champs, matchup, items, runes, spells, latest, from };
  }, [targetId, counterId, fromId, auth.user.id]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const target = data.champs[targetId];
  const counter = data.champs[counterId];
  if (!target || !counter || !data.matchup) return <NotFound />;
  return <BuildEditor key={fromId ?? 'new'} data={data} target={target} counter={counter} fromId={fromId} />;
}

function BuildEditor({ data, target, counter, fromId }) {
  const auth = useAuth();
  const navigate = useNavigate();
  const [build, setBuild] = useState(() => (data.from ? buildToForm(data.from) : emptyBuild()));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const game = { items: data.items, runes: data.runes, spells: data.spells };
  const problem = buildProblem(build, game);
  const title = `${counter.name}(으)로 ${target.name} 잡는 법`;
  const set = (patch) => setBuild((b) => ({ ...b, ...patch }));

  const submit = async (e) => {
    e.preventDefault();
    if (problem || busy) return;
    setBusy(true);
    setError(null);
    try {
      await submitBuild(auth.user.id, data.matchup.counter.id, build, data.latest);
      navigate('/me', { state: { sent: `${title} — 빌드를 보냈어요.` } });
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  return (
    <article>
      <nav className="crumbs">
        <Link to="/">홈</Link> › <Link to={`/champion/${target.id}`}>{target.name}</Link> ›{' '}
        <Link to={`/champion/${target.id}/counter/${counter.id}`}>{counter.name}</Link> › 빌드 등록
      </nav>
      <h1 className="doc-title">{title} — 빌드 등록</h1>
      {fromId && data.from && <p className="notice" role="status">내 빌드 내용을 채워 뒀어요. 고쳐서 새 빌드로 보내요. (원래 빌드는 그대로 남아요)</p>}
      {fromId && !data.from && <p className="notice" role="status">불러올 내 빌드를 찾지 못했어요. 빈 칸에서 시작해요.</p>}
      <p className="lead">
        운영자가 승인하면 매치업 문서에 공개돼요. 패치 {patchMinor(data.latest)} 기준으로 등록돼요.
      </p>

      <form className="build-form" onSubmit={submit}>
        <RunePicker runes={data.runes} value={build.runes} onChange={(runes) => set({ runes })} />
        <SpellPicker spells={data.spells} value={build.summoner_spells} onChange={(summoner_spells) => set({ summoner_spells })} />
        <ItemPicker
          id="starting"
          title="시작 아이템"
          hint={`${ITEM_LIMITS.starting[0]}~${ITEM_LIMITS.starting[1]}개 (같은 아이템 여러 개 가능, 예: 포션 2개)`}
          items={data.items}
          value={build.starting_items}
          max={ITEM_LIMITS.starting[1]}
          order="cheap"
          onChange={(starting_items) => set({ starting_items })}
        />
        <ItemPicker
          id="core"
          title="핵심 템트리"
          hint={`${ITEM_LIMITS.core[0]}~${ITEM_LIMITS.core[1]}개, 사는 순서대로`}
          items={data.items}
          value={build.core_items}
          max={ITEM_LIMITS.core[1]}
          distinct
          movable
          onChange={(core_items) => set({ core_items })}
        />
        <SkillPicker value={build} onChange={set} />

        <fieldset className="pick-group">
          <legend>미리보기</legend>
          {problem ? (
            <p className="hint" role="status">아직 고를 것: {problem}</p>
          ) : (
            <BuildCard
              build={{ ...build, patch: data.latest, author: auth.profile }}
              items={data.items}
              runes={data.runes}
              spells={data.spells}
              latest={data.latest}
            />
          )}
        </fieldset>

        {error && <p className="form-error" role="alert">{error}</p>}
        <div className="actions">
          <button type="submit" className="btn" disabled={!!problem || busy}>
            {busy ? '보내는 중…' : '빌드 보내기'}
          </button>
          <Link to={`/champion/${target.id}/counter/${counter.id}`} className="btn">취소</Link>
        </div>
      </form>
    </article>
  );
}

/** 아이콘 고르기 버튼 (이름은 aria-label로, 선택은 aria-pressed로) */
function Pick({ entry, selected, onClick, size = 36, round = false, disabled = false, label, text }) {
  return (
    <button
      type="button"
      className={selected ? 'pick on' : 'pick'}
      aria-pressed={selected}
      aria-label={label ?? entry?.name}
      title={entry?.name}
      onClick={onClick}
      disabled={disabled}
    >
      {entry ? <img src={entry.icon} alt="" width={size} height={size} className={round ? 'ico round' : 'ico'} loading="lazy" /> : text ?? label}
    </button>
  );
}

const SHARD_ROW_NAMES = ['공격', '유연', '방어'];

function RunePicker({ runes, value: r, onChange }) {
  const paths = Object.values(runes.paths).sort((a, b) => a.id - b.id);
  const primary = runes.paths[r.primaryPath];
  const secondary = runes.paths[r.secondaryPath];

  const choosePrimary = (id) => {
    if (id === r.primaryPath) return;
    onChange({
      ...r, primaryPath: id, keystone: null, primary: [null, null, null],
      ...(r.secondaryPath === id ? { secondaryPath: null, secondary: [] } : {}),
    });
  };
  const chooseSecondary = (id) => {
    if (id === r.secondaryPath) return;
    onChange({ ...r, secondaryPath: id, secondary: [] });
  };
  /** 보조 룬: 같은 줄이면 바꾸고, 이미 2개면 먼저 고른 것을 뺀다 */
  const toggleSecondary = (id) => {
    if (r.secondary.includes(id)) {
      onChange({ ...r, secondary: r.secondary.filter((x) => x !== id) });
      return;
    }
    const row = runes.runes[id].row;
    let next = r.secondary.filter((x) => runes.runes[x]?.row !== row);
    if (next.length >= 2) next = next.slice(1);
    onChange({ ...r, secondary: [...next, id] });
  };

  return (
    <fieldset className="pick-group">
      <legend>특성(룬)</legend>
      <div className="pick-row" role="group" aria-label="주 경로">
        <span className="label">주 경로</span>
        {paths.map((p) => <Pick key={p.id} entry={p} round size={28} selected={p.id === r.primaryPath} onClick={() => choosePrimary(p.id)} label={`주 경로 ${p.name}`} />)}
      </div>
      {primary && (
        <>
          <div className="pick-row" role="group" aria-label="핵심 룬">
            <span className="label">핵심</span>
            {primary.keystones.map((id) => (
              <Pick key={id} entry={runes.runes[id]} round size={40} selected={id === r.keystone} onClick={() => onChange({ ...r, keystone: id })} />
            ))}
          </div>
          {primary.rows.map((row, i) => (
            <div key={i} className="pick-row" role="group" aria-label={`주 경로 ${i + 1}줄`}>
              <span className="label">{i + 1}줄</span>
              {row.map((id) => (
                <Pick
                  key={id}
                  entry={runes.runes[id]}
                  round
                  selected={r.primary[i] === id}
                  onClick={() => onChange({ ...r, primary: r.primary.map((x, j) => (j === i ? id : x)) })}
                />
              ))}
            </div>
          ))}
        </>
      )}
      <div className="pick-row" role="group" aria-label="보조 경로">
        <span className="label">보조 경로</span>
        {paths.filter((p) => p.id !== r.primaryPath).map((p) => (
          <Pick key={p.id} entry={p} round size={28} selected={p.id === r.secondaryPath} onClick={() => chooseSecondary(p.id)} label={`보조 경로 ${p.name}`} />
        ))}
      </div>
      {secondary && (
        <div className="pick-row wrap" role="group" aria-label="보조 룬 (서로 다른 줄에서 2개)">
          <span className="label">보조 룬</span>
          {secondary.rows.map((row, i) => (
            <span key={i} className="pick-sub">
              {row.map((id) => (
                <Pick key={id} entry={runes.runes[id]} round size={32} selected={r.secondary.includes(id)} onClick={() => toggleSecondary(id)} />
              ))}
            </span>
          ))}
        </div>
      )}
      {SHARD_ROWS.map((row, i) => (
        <div key={i} className="pick-row" role="group" aria-label={`능력치 파편 ${SHARD_ROW_NAMES[i]}`}>
          <span className="label">{SHARD_ROW_NAMES[i]}</span>
          {row.map((id) => (
            <Pick
              key={id}
              entry={runes.shards[id]}
              round
              size={24}
              selected={r.shards[i] === id}
              onClick={() => onChange({ ...r, shards: r.shards.map((x, j) => (j === i ? id : x)) })}
              label={`${SHARD_ROW_NAMES[i]} ${runes.shards[id].name}`}
            />
          ))}
        </div>
      ))}
    </fieldset>
  );
}

function SpellPicker({ spells, value, onChange }) {
  const list = Object.values(spells).filter((s) => s.classic).sort((a, b) => a.name.localeCompare(b.name, 'ko'));
  const toggle = (id) => {
    if (value.includes(id)) onChange(value.filter((x) => x !== id));
    else onChange([...(value.length >= 2 ? value.slice(1) : value), id]);
  };
  return (
    <fieldset className="pick-group">
      <legend>소환사 주문 (2개)</legend>
      <div className="pick-row wrap" role="group" aria-label="소환사 주문">
        {list.map((s) => <Pick key={s.id} entry={s} selected={value.includes(s.id)} onClick={() => toggle(s.id)} />)}
      </div>
    </fieldset>
  );
}

const SHOW = 60;

function ItemPicker({ id, title, hint, items, value, max, distinct = false, movable = false, order = 'expensive', onChange }) {
  const [query, setQuery] = useState('');
  const shop = Object.values(items)
    .filter((it) => it.shop && matchesQuery(query, it.name))
    .sort((a, b) => (order === 'cheap' ? a.gold - b.gold : b.gold - a.gold) || a.name.localeCompare(b.name, 'ko'));
  const full = value.length >= max;
  const move = (i) => onChange(value.map((x, j) => (j === i - 1 ? value[i] : j === i ? value[i - 1] : x)));

  return (
    <fieldset className="pick-group">
      <legend>{title}</legend>
      <small className="hint">{hint}</small>
      <ol className="picked" aria-label={`고른 ${title}`}>
        {value.length === 0 && <li className="empty">아직 고르지 않았어요.</li>}
        {value.map((itemId, i) => (
          <li key={`${itemId}-${i}`} className="picked-item">
            <Icon entry={items[itemId]} size={32} />
            <span>{items[itemId]?.name ?? itemId}</span>
            {movable && i > 0 && (
              <button type="button" className="btn btn-small" onClick={() => move(i)} aria-label={`${items[itemId]?.name ?? itemId} 앞으로`}>
                ←
              </button>
            )}
            <button
              type="button"
              className="btn btn-small"
              onClick={() => onChange(value.filter((_, j) => j !== i))}
              aria-label={`${items[itemId]?.name ?? itemId} 빼기`}
            >
              빼기
            </button>
          </li>
        ))}
      </ol>
      <label htmlFor={`${id}-search`} className="sr-only">{title} 검색</label>
      <input
        id={`${id}-search`}
        type="search"
        className="item-search"
        placeholder="아이템 이름 검색 (초성도 돼요)"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
      />
      <div className="pick-row wrap" role="group" aria-label={`${title} 고르기`}>
        {shop.slice(0, SHOW).map((it) => (
          <Pick
            key={it.id}
            entry={it}
            selected={value.includes(it.id)}
            disabled={full || (distinct && value.includes(it.id))}
            onClick={() => onChange([...value, it.id])}
          />
        ))}
        {shop.length === 0 && <p className="empty">찾는 아이템이 없어요.</p>}
      </div>
      {shop.length > SHOW && <small className="hint">{shop.length - SHOW}개 더 있어요. 이름으로 검색해 주세요.</small>}
      {full && <small className="hint">{max}개까지 고를 수 있어요.</small>}
    </fieldset>
  );
}

function SkillPicker({ value, onChange }) {
  const setEarly = (lv, k) => onChange({ early_skills: value.early_skills.map((x, i) => (i === lv ? k : x)) });
  return (
    <fieldset className="pick-group">
      <legend>스킬</legend>
      {[0, 1, 2].map((lv) => (
        <div key={lv} className="pick-row" role="group" aria-label={`${lv + 1}레벨 스킬`}>
          <span className="label">{lv + 1}레벨</span>
          {SKILLS.map((k) => (
            <Pick key={k} selected={value.early_skills[lv] === k} onClick={() => setEarly(lv, k)} label={`${lv + 1}레벨 ${k}`} text={k} />
          ))}
        </div>
      ))}
      <div className="pick-row wrap" role="group" aria-label="선마 순서">
        <span className="label">선마</span>
        {SKILL_ORDERS.map((o) => (
          <Pick
            key={o.join('')}
            selected={value.skill_order?.join('') === o.join('')}
            onClick={() => onChange({ skill_order: o })}
            label={`선마 ${o.join(' › ')}`}
            text={o.join(' › ')}
          />
        ))}
      </div>
    </fieldset>
  );
}
