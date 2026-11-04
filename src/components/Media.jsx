import { useEffect, useRef, useState } from 'react';
import { DEFAULT_MEDIA_RULES, getMediaRules, mediaUploadProblem } from '../api/media';
import { ACCEPT, GIF, prepareImage } from '../lib/imageCompress';
import { XIcon } from './Icons';

let seq = 0;

/** 사진 숫자 (xp_rules). 읽기 전·실패 때는 기본값 — 어차피 DB가 다시 검사한다 */
export function useMediaRules() {
  const [rules, setRules] = useState(DEFAULT_MEDIA_RULES);
  useEffect(() => {
    let alive = true;
    getMediaRules().then((r) => {
      if (alive) setRules(r);
    });
    return () => {
      alive = false;
    };
  }, []);
  return rules;
}

/** 저장된 사진 → 고르기 칸 항목 ({ key, path, url, mime }) */
export const mediaToItems = (media = []) => media.map((m) => ({ key: m.path, path: m.path, url: m.url, mime: m.mime }));
/** 고르기 칸 항목이 처음과 같은가 (경로·순서) */
export const sameMedia = (items, media = []) =>
  items.length === media.length && items.every((it, i) => it.path && it.path === media[i].path);

/**
 * 사진·GIF 고르기 (SPEC 6-13): [사진·GIF 추가] → 브라우저에서 줄이기 → 작은 미리보기 + X로 빼기.
 * items = [{ key, path?(이미 올린 것), url(미리보기), mime, prepared?({ blob, mime, ext } — 보낼 때 올림) }]
 * max: 붙일 수 있는 수, gifMax: 그중 GIF 수, rules: { photoMaxKb, gifMaxKb }
 */
export function MediaPicker({ id, items, onChange, max, gifMax = max, rules, disabled = false }) {
  const input = useRef(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  // 미리보기용으로 만든 주소는 칸이 사라질 때 돌려준다
  const made = useRef(new Set());
  useEffect(() => {
    const urls = made.current;
    return () => {
      urls.forEach((u) => URL.revokeObjectURL?.(u));
    };
  }, []);

  const left = max - items.length;
  const gifs = items.filter((it) => it.mime === GIF).length;

  const pick = async (e) => {
    const files = [...(e.target.files ?? [])];
    e.target.value = ''; // 같은 파일을 다시 골라도 바뀜으로 잡히게
    if (files.length === 0) return;
    setError(null);
    setBusy(true);
    try {
      const problem = await mediaUploadProblem();
      if (problem) throw new Error(problem);
      const next = [...items];
      let gifCount = gifs;
      const notes = [];
      for (const file of files) {
        if (next.length >= max) {
          notes.push(`사진은 ${max}개까지 붙일 수 있어요.`);
          break;
        }
        if (file.type === GIF && gifCount >= gifMax) {
          notes.push(`GIF는 ${gifMax}개까지 붙일 수 있어요.`);
          continue;
        }
        try {
          const prepared = await prepareImage(file, rules);
          const url = URL.createObjectURL(prepared.blob);
          made.current.add(url);
          seq += 1;
          next.push({ key: `new-${seq}`, url, mime: prepared.mime, prepared });
          if (prepared.mime === GIF) gifCount += 1;
        } catch (err) {
          notes.push(err.message);
        }
      }
      onChange(next);
      if (notes.length) setError([...new Set(notes)].join(' '));
    } catch (err) {
      setError(err.message);
    }
    setBusy(false);
  };

  return (
    <div className="media-picker">
      {items.length > 0 && (
        <ul className="media-thumbs" aria-label="붙일 사진">
          {items.map((it, i) => (
            <li key={it.key} className="media-thumb">
              {it.url ? <img src={it.url} alt={`붙일 사진 ${i + 1}`} /> : <span className="media-missing">사진 {i + 1}</span>}
              {it.mime === GIF && <span className="media-gif" aria-hidden="true">GIF</span>}
              <button
                type="button" className="icon-btn media-remove" aria-label={`사진 ${i + 1} 빼기`} title="빼기" disabled={disabled}
                onClick={() => onChange(items.filter((x) => x !== it))}
              >
                <XIcon />
              </button>
            </li>
          ))}
        </ul>
      )}
      <input
        ref={input} id={id} type="file" accept={ACCEPT} multiple={max > 1} hidden
        onChange={pick} disabled={disabled || busy || left <= 0}
      />
      <button
        type="button" className="btn btn-small" onClick={() => input.current?.click()}
        disabled={disabled || busy || left <= 0} aria-describedby={`${id}-hint`}
      >
        {busy ? '사진 줄이는 중…' : `📷 사진·GIF 추가 (${items.length}/${max})`}
      </button>
      <small className="hint" id={`${id}-hint`}>
        사진은 자동으로 줄여 올려요{gifMax > 0 ? ` · GIF는 ${gifMax}개, ${Math.round(rules.gifMaxKb / 1024)}MB까지` : ''}
      </small>
      {error && <p className="form-error" role="alert">{error}</p>}
    </div>
  );
}

/** 붙은 사진 보기: 작은 칸 → 누르면 크게 (Esc·[닫기]·바깥을 누르면 닫힘) */
export function MediaGallery({ media, label = '첨부 사진' }) {
  const [open, setOpen] = useState(null);
  if (!media?.length) return null;
  const close = () => setOpen(null);
  return (
    <>
      <ul className={media.length === 1 ? 'media-gallery single' : 'media-gallery'} aria-label={label}>
        {media.map((m, i) => (
          <li key={m.path}>
            {m.url ? (
              <button type="button" className="media-open" onClick={() => setOpen(i)} aria-label={`${label} ${i + 1} 크게 보기`}>
                <img src={m.url} alt={`${label} ${i + 1}`} loading="lazy" />
                {m.mime === GIF && <span className="media-gif" aria-hidden="true">GIF</span>}
              </button>
            ) : (
              <span className="media-missing">사진을 불러오지 못했어요</span>
            )}
          </li>
        ))}
      </ul>
      {open !== null && media[open]?.url && (
        <div
          className="media-viewer" role="dialog" aria-modal="true" aria-label={`${label} ${open + 1}`}
          onClick={close} onKeyDown={(e) => e.key === 'Escape' && close()}
        >
          <img src={media[open].url} alt={`${label} ${open + 1}`} onClick={(e) => e.stopPropagation()} />
          {/* eslint-disable-next-line jsx-a11y/no-autofocus -- 크게 보기를 열면 바로 [닫기]에 둔다 (Esc로도 닫힘) */}
          <button type="button" className="btn btn-small media-close" onClick={close} autoFocus>닫기</button>
        </div>
      )}
    </>
  );
}
