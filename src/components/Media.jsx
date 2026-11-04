import { useEffect, useRef, useState } from 'react';
import { DEFAULT_MEDIA_RULES, getMediaRules, mediaUploadProblem } from '../api/media';
import { ACCEPT, GIF, prepareImage } from '../lib/imageCompress';
import { XIcon } from './Icons';

let seq = 0;
const NOT_IMAGE = '사진·GIF만 올릴 수 있어요.';
const isImageFile = (file) => (file.type ?? '').startsWith('image/');
const hasFiles = (data) => Boolean(data) && [...(data.types ?? [])].includes('Files');

/**
 * 사진 칸 밖에 파일을 떨어뜨려도 브라우저가 그 파일을 새 탭으로 열지 않게 (앱을 켤 때 한 번).
 * 글자·링크 끌기는 그대로 두고, 파일을 끌 때만 막는다. 첨부 칸은 자기 drop에서 먼저 받는다.
 */
export function blockStrayFileDrops(target = window) {
  const stop = (e) => {
    if (!hasFiles(e.dataTransfer) || e.defaultPrevented) return; // 첨부 칸이 이미 받았으면 그대로
    e.preventDefault();
    if (e.type === 'dragover') e.dataTransfer.dropEffect = 'none';
  };
  target.addEventListener('dragover', stop);
  target.addEventListener('drop', stop);
  return () => {
    target.removeEventListener('dragover', stop);
    target.removeEventListener('drop', stop);
  };
}

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
 * dropRef: 끌어다 놓기·Ctrl+V 붙여넣기를 받을 칸 (글쓰기·댓글 form). 그 칸에 position: relative가 있어야 "여기에 놓으면" 막이 덮인다
 */
export function MediaPicker({ id, items, onChange, max, gifMax = max, rules, disabled = false, dropRef }) {
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

  // 버튼으로 고르기·끌어다 놓기·붙여넣기가 모두 여기로 온다 (개수·GIF 수·크기·압축·올리기 가능 여부가 똑같다)
  const addFiles = async (files) => {
    if (files.length === 0 || disabled || busy) return;
    const images = files.filter(isImageFile);
    const notes = images.length < files.length ? [NOT_IMAGE] : [];
    if (images.length === 0) {
      setError(NOT_IMAGE);
      return;
    }
    if (left <= 0) {
      setError(`사진은 ${max}개까지 붙일 수 있어요.`);
      return;
    }
    setError(null);
    setBusy(true);
    try {
      const problem = await mediaUploadProblem();
      if (problem) throw new Error(problem);
      const next = [...items];
      let gifCount = gifs;
      for (const file of images) {
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

  const pick = (e) => {
    const files = [...(e.target.files ?? [])];
    e.target.value = ''; // 같은 파일을 다시 골라도 바뀜으로 잡히게
    addFiles(files);
  };

  // 끌어다 놓기·붙여넣기는 dropRef(글쓰기·댓글 칸 전체)에서 받는다. 듣는 함수는 늘 최신 addFiles를 부른다
  const latest = useRef(addFiles);
  latest.current = addFiles;
  const [over, setOver] = useState(false);
  useEffect(() => {
    const zone = dropRef?.current;
    if (!zone) return undefined;
    let depth = 0; // 안쪽 칸을 지날 때마다 enter/leave가 나와서 깜빡이지 않게 센다
    const enter = (e) => {
      if (!hasFiles(e.dataTransfer)) return;
      e.preventDefault();
      depth += 1;
      setOver(true);
    };
    const move = (e) => {
      if (!hasFiles(e.dataTransfer)) return;
      e.preventDefault();
      e.dataTransfer.dropEffect = 'copy';
    };
    const leave = (e) => {
      if (!hasFiles(e.dataTransfer)) return;
      depth = Math.max(0, depth - 1);
      if (depth === 0) setOver(false);
    };
    const drop = (e) => {
      if (!hasFiles(e.dataTransfer)) return;
      e.preventDefault();
      e.stopPropagation();
      depth = 0;
      setOver(false);
      latest.current([...(e.dataTransfer.files ?? [])]);
    };
    const paste = (e) => {
      const data = e.clipboardData;
      // 글자도 같이 있으면(엑셀·워드 복사 등) 글자 붙여넣기로 둔다. 사진만 있을 때(캡처·이미지 복사·파일 복사)만 첨부
      if (!data || !hasFiles(data) || [...(data.types ?? [])].includes('text/plain')) return;
      const files = [...(data.files ?? [])];
      if (files.length === 0) return;
      e.preventDefault();
      latest.current(files);
    };
    const reset = () => {
      depth = 0;
      setOver(false);
    };
    zone.addEventListener('dragenter', enter);
    zone.addEventListener('dragover', move);
    zone.addEventListener('dragleave', leave);
    zone.addEventListener('drop', drop);
    zone.addEventListener('paste', paste);
    window.addEventListener('dragend', reset);
    window.addEventListener('drop', reset);
    return () => {
      zone.removeEventListener('dragenter', enter);
      zone.removeEventListener('dragover', move);
      zone.removeEventListener('dragleave', leave);
      zone.removeEventListener('drop', drop);
      zone.removeEventListener('paste', paste);
      window.removeEventListener('dragend', reset);
      window.removeEventListener('drop', reset);
    };
  }, [dropRef]);

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
        사진은 자동으로 줄여 올려요{dropRef ? ' · 끌어다 놓거나 Ctrl+V로 붙여 넣어도 돼요' : ''}{gifMax > 0 ? ` · GIF는 ${gifMax}개, ${Math.round(rules.gifMaxKb / 1024)}MB까지` : ''}
      </small>
      {error && <p className="form-error" role="alert">{error}</p>}
      {over && (
        <div className="media-drop-overlay" role="status">
          {disabled || busy ? '잠시 뒤에 다시 놓아 주세요' : left > 0 ? '여기에 놓으면 첨부돼요' : `사진은 ${max}개까지 붙일 수 있어요`}
        </div>
      )}
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
