import { useState } from 'react';
import { SHARD_ROWS } from '../api/ddragon';
import { matchesQuery } from '../lib/chosung';
import { ITEM_LIMITS, SKILLS, buildProblem, startGold, startGoldMax } from '../lib/buildContent';
import BuildCard, { Icon } from './BuildCard';

/**
 * 빌드 입력 (룬·주문·아이템·스킬 + 미리보기). 빌드 등록·새 카운터 제안·다시 제출 공용.
 * game = { items, runes, spells, latest, startGoldMax } (Data Dragon + 시작템 합계 상한), value = 등록 화면 값(buildContent.emptyBuild 모양)
 * author: 미리보기에 보일 작성자 프로필
 */
export default function BuildFields({ game, value: build, onChange, author }) {
  const set = (patch) => onChange({ ...build, ...patch });
  const problem = buildProblem(build, game);
  return (
    <>
      <RunePicker runes={game.runes} value={build.runes} onChange={(runes) => set({ runes })} />
      <SpellPicker spells={game.spells} value={build.summoner_spells} onChange={(summoner_spells) => set({ summoner_spells })} />
      <ItemPicker
        id="starting"
        title="시작 아이템"
        hint={`${ITEM_LIMITS.starting[0]}~${ITEM_LIMITS.starting[1]}개, 합계 ${startGoldMax(game)}골드까지 (같은 아이템 여러 개 가능, 예: 포션 2개)`}
        items={game.items}
        value={build.starting_items}
        max={ITEM_LIMITS.starting[1]}
        goldMax={startGoldMax(game)}
        order="cheap"
        onChange={(starting_items) => set({ starting_items })}
      />
      <ItemPicker
        id="core"
        title="핵심 템트리"
        hint={`${ITEM_LIMITS.core[0]}~${ITEM_LIMITS.core[1]}개, 사는 순서대로`}
        items={game.items}
        value={build.core_items}
        max={ITEM_LIMITS.core[1]}
        distinct
        movable
        onChange={(core_items) => set({ core_items })}
      />
      <SkillPicker value={build} onChange={set} />

      <fieldset className="pick-group">
        <legend>빌드 미리보기</legend>
        {problem ? (
          <p className="hint" role="status">아직 고를 것: {problem}</p>
        ) : (
          <BuildCard build={{ ...build, patch: game.latest, author }} {...game} />
        )}
      </fieldset>
    </>
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

/** goldMax: 시작 아이템처럼 골드 합계 상한이 있으면 그 값 (그보다 비싼 아이템은 목록에 없고, 합계를 넘기는 아이템은 잠긴다) */
function ItemPicker({ id, title, hint, items, value, max, goldMax = null, distinct = false, movable = false, order = 'expensive', onChange }) {
  const [query, setQuery] = useState('');
  const budget = goldMax !== null;
  const total = budget ? startGold(value, items) : 0;
  const shop = Object.values(items)
    .filter((it) => it.shop && (!budget || it.gold <= goldMax) && matchesQuery(query, it.name))
    .sort((a, b) => (order === 'cheap' ? a.gold - b.gold : b.gold - a.gold) || a.name.localeCompare(b.name, 'ko'));
  const full = value.length >= max;
  const move = (i) => onChange(value.map((x, j) => (j === i - 1 ? value[i] : j === i ? value[i - 1] : x)));

  return (
    <fieldset className="pick-group">
      <legend>{title}</legend>
      <small className="hint">{hint}</small>
      {budget && (
        <p className={total > goldMax ? 'gold-total over' : 'gold-total'} role="status" aria-label="시작 아이템 골드 합계">
          합계 {total} / {goldMax}골드 · 남은 골드 {Math.max(goldMax - total, 0)}
        </p>
      )}
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
        onKeyDown={(e) => e.key === 'Enter' && e.preventDefault()} // 폼 안이라 Enter로 제출되지 않게
      />
      <div className="pick-row wrap" role="group" aria-label={`${title} 고르기`}>
        {shop.slice(0, SHOW).map((it) => (
          <Pick
            key={it.id}
            entry={it}
            selected={value.includes(it.id)}
            disabled={full || (distinct && value.includes(it.id)) || (budget && total + it.gold > goldMax)}
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

/** 스킬: 선마(첫 번째로 마스터할 스킬) 하나만 */
function SkillPicker({ value, onChange }) {
  return (
    <fieldset className="pick-group">
      <legend>스킬</legend>
      <div className="pick-row" role="group" aria-label="선마 (첫 번째로 마스터할 스킬)">
        <span className="label">선마</span>
        {SKILLS.map((k) => (
          <Pick key={k} selected={value.max_skill === k} onClick={() => onChange({ max_skill: k })} label={`선마 ${k}`} text={k} />
        ))}
      </div>
      <small className="hint">첫 번째로 마스터할 스킬을 골라 주세요.</small>
    </fieldset>
  );
}
