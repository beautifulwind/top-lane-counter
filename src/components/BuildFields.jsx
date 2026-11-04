import { useEffect, useRef, useState } from 'react';
import {
  DndContext, KeyboardSensor, MouseSensor, TouchSensor, closestCenter, useSensor, useSensors,
} from '@dnd-kit/core';
import { SortableContext, arrayMove, sortableKeyboardCoordinates, useSortable, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { SHARD_ROWS } from '../api/ddragon';
import { matchesQuery } from '../lib/chosung';
import { ITEM_LIMITS, NO_SPELLS, SKILLS, buildProblem, startGold, startGoldMax } from '../lib/buildContent';
import BuildCard, { Icon } from './BuildCard';
import { XIcon } from './Icons';
import { CORE_FILTERS, isCoreItem } from '../lib/itemKinds';

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
        items={game.items}
        value={build.starting_items}
        max={ITEM_LIMITS.starting[1]}
        goldMax={startGoldMax(game)}
        order="cheap"
        frequent={game.frequent?.starting}
        onChange={(starting_items) => set({ starting_items })}
      />
      <ItemPicker
        id="core"
        title="핵심 템트리"
        hint={`${ITEM_LIMITS.core[0]}~${ITEM_LIMITS.core[1]}개, 사는 순서대로 · 전설·서사·신발 (전설 1개 이상) · 끌어서 순서 바꾸기 (폰은 꾹 눌러 끌기)`}
        items={game.items}
        value={build.core_items}
        max={ITEM_LIMITS.core[1]}
        distinct
        movable
        allow={isCoreItem}
        filters={CORE_FILTERS}
        frequent={game.frequent?.core}
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
      aria-label={label ?? (entry?.kind === 'epic' ? `${entry.name} (서사)` : entry?.name)}
      title={entry?.name}
      onClick={onClick}
      disabled={disabled}
    >
      {entry ? <img src={entry.icon} alt="" width={size} height={size} className={round ? 'ico round' : 'ico'} loading="lazy" /> : text ?? label}
      {entry?.kind === 'epic' && <span className="epic-tag" aria-hidden="true">서사</span>}
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
  // 022: 강타는 고를 수 없다. 예전 빌드를 다시 쓸 때 이미 골라져 있으면 뺄 수 있게만 보여 준다
  const list = Object.values(spells).filter((s) => s.classic && (!NO_SPELLS.includes(s.id) || value.includes(s.id))).sort((a, b) => a.name.localeCompare(b.name, 'ko'));
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

const OVER_MS = 2000;

/**
 * 아이템 고르기 (028): 처음에는 "자주 쓰는 아이템"(운영자가 /admin에서 정함)만, 나머지는 [더보기]를 눌러야 펼쳐진다.
 * 검색(초성 포함)은 항상 고를 수 있는 아이템 전체에서. filters가 있으면 [더보기] 안에 [전체][전설][서사][신발] 거르기.
 * allow: 이 칸에 넣을 수 있는 아이템인가 (핵심 템트리 = 전설·서사·신발). 자주 쓰는 아이템이 없으면 [더보기]를 펼친 채로 시작한다.
 * goldMax: 시작 아이템처럼 골드 합계 상한이 있으면 그 값 (그보다 비싼 아이템은 목록에 없다).
 * 합계를 넘기는 아이템을 누르면 넣지 않고 "N골드를 넘습니다"를 잠깐 보여 준다 (022: 합계·남은 골드 안내는 숨김).
 * movable: 끌어서 순서 바꾸기 (PC는 마우스로 끌기, 폰은 꾹 눌러 끌기, 키보드는 Space 후 화살표)
 */
function ItemPicker({
  id, title, hint, items, value, max, goldMax = null, distinct = false, movable = false, order = 'expensive',
  allow = null, filters = null, frequent = [], onChange,
}) {
  const [query, setQuery] = useState('');
  const [over, setOver] = useState(false);
  const [kind, setKind] = useState('all');
  const timer = useRef(null);
  useEffect(() => {
    return () => clearTimeout(timer.current);
  }, []);
  const budget = goldMax !== null;
  const total = budget ? startGold(value, items) : 0;
  const byOrder = (a, b) => (order === 'cheap' ? a.gold - b.gold : b.gold - a.gold) || a.name.localeCompare(b.name, 'ko');
  // 이 칸에서 고를 수 있는 아이템 전부 (지금 상점에 있는 것)
  const pool = Object.values(items).filter((it) => it.shop && (!budget || it.gold <= goldMax) && (!allow || allow(it))).sort(byOrder);
  const freqIds = new Set(frequent ?? []);
  const common = pool.filter((it) => freqIds.has(it.id));
  const [moreOpen, setMoreOpen] = useState(common.length === 0);
  const searching = query.trim() !== '';
  const found = searching ? pool.filter((it) => matchesQuery(query, it.name)) : [];
  const rest = pool.filter((it) => !freqIds.has(it.id) && (kind === 'all' || it.kind === kind));
  const full = value.length >= max;
  const name = (itemId) => items[itemId]?.name ?? itemId;
  const keys = value.map((itemId, i) => `${itemId}-${i}`);

  const add = (it) => {
    if (budget && total + it.gold > goldMax) {
      setOver(true);
      clearTimeout(timer.current);
      timer.current = setTimeout(() => setOver(false), OVER_MS);
      return;
    }
    onChange([...value, it.id]);
  };
  const remove = (i) => onChange(value.filter((_, j) => j !== i));

  const sensors = useSensors(
    useSensor(MouseSensor, { activationConstraint: { distance: 4 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 250, tolerance: 8 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );
  const onDragEnd = ({ active, over: target }) => {
    if (!target || active.id === target.id) return;
    onChange(arrayMove(value, keys.indexOf(active.id), keys.indexOf(target.id)));
  };

  const rows = value.map((itemId, i) => (
    <PickedItem key={keys[i]} id={keys[i]} movable={movable} entry={items[itemId]} name={name(itemId)} onRemove={() => remove(i)} />
  ));
  const picks = (list, label) => (
    <div className="pick-row wrap" role="group" aria-label={label}>
      {list.map((it) => (
        <Pick
          key={it.id}
          entry={it}
          selected={value.includes(it.id)}
          disabled={full || (distinct && value.includes(it.id))}
          onClick={() => add(it)}
        />
      ))}
    </div>
  );

  return (
    <fieldset className="pick-group">
      <legend>{title}</legend>
      {hint && <small className="hint">{hint}</small>}
      <ol className="picked" aria-label={`고른 ${title}`}>
        {value.length === 0 && <li className="empty">아직 고르지 않았습니다.</li>}
        {movable ? (
          <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={onDragEnd}>
            <SortableContext items={keys} strategy={verticalListSortingStrategy}>{rows}</SortableContext>
          </DndContext>
        ) : rows}
      </ol>
      {over && <p className="gold-over" role="status">{goldMax}골드를 넘습니다</p>}
      <label htmlFor={`${id}-search`} className="sr-only">{title} 검색</label>
      <input
        id={`${id}-search`}
        type="search"
        className="item-search"
        placeholder="판금장화 ex) ㅍㄱㅈㅎ"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        onKeyDown={(e) => e.key === 'Enter' && e.preventDefault()} // 폼 안이라 Enter로 제출되지 않게
      />
      {searching ? (
        <>
          {picks(found.slice(0, SHOW), `${title} 고르기`)}
          {found.length === 0 && <p className="empty">찾는 아이템이 없습니다.</p>}
          {found.length > SHOW && <small className="hint">{found.length - SHOW}개 더 있습니다. 이름을 더 적어 주세요.</small>}
        </>
      ) : (
        <>
          {common.length > 0 && (
            <>
              <p className="pick-caption">자주 쓰는 아이템</p>
              {picks(common, `${title} 고르기`)}
            </>
          )}
          {common.length > 0 && (
            <button
              type="button" className="btn btn-small more-btn" aria-expanded={moreOpen} aria-controls={`${id}-more`}
              onClick={() => setMoreOpen((o) => !o)}
            >
              {moreOpen ? '접기' : `더보기 (${pool.length - common.length}개)`}
            </button>
          )}
          {moreOpen && (
            <div id={`${id}-more`} className="pick-more">
              {filters && (
                <div className="view-switch kind-switch" role="group" aria-label={`${title} 종류`}>
                  {filters.map((f) => (
                    <button key={f.key} type="button" className="btn btn-small" aria-pressed={kind === f.key} onClick={() => setKind(f.key)}>
                      {f.label}
                    </button>
                  ))}
                </div>
              )}
              {picks(rest, common.length > 0 ? `${title} 더보기` : `${title} 고르기`)}
              {rest.length === 0 && <p className="empty">이 종류의 아이템이 없습니다.</p>}
            </div>
          )}
        </>
      )}
      {full && <small className="hint">{max}개까지 고를 수 있습니다.</small>}
    </fieldset>
  );
}

/** 고른 아이템 한 줄. movable이면 줄 전체를 끌어서 옮긴다 (손잡이 ⋮⋮는 CSS가 그림, [X]는 끌기와 따로 눌린다) */
function PickedItem({ id, movable, entry, name, onRemove }) {
  const sortable = useSortable({ id, disabled: !movable });
  const { setNodeRef, attributes, listeners, transform, transition, isDragging } = sortable;
  const dragProps = movable
    ? { ...attributes, ...listeners, 'aria-roledescription': '끌어서 순서 바꾸기', 'aria-label': `${name} (끌어서 순서 바꾸기)` }
    : {};
  return (
    <li
      ref={movable ? setNodeRef : undefined}
      className={`picked-item${movable ? ' movable' : ''}${isDragging ? ' dragging' : ''}`}
      style={movable ? { transform: CSS.Transform.toString(transform), transition } : undefined}
    >
      <span className="picked-drag" {...dragProps}>
        <Icon entry={entry} size={32} />
        <span className="picked-name">{name}</span>
      </span>
      <button type="button" className="icon-btn" onClick={onRemove} aria-label={`${name} 빼기`} title="빼기">
        <XIcon />
      </button>
    </li>
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
