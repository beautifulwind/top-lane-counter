import { useEffect, useRef, useState } from 'react';
import {
  changeApplicationPhoto, changeProfilePhoto, deleteApplicationPhoto, deleteMyProfilePhoto, profilePhotoUrl,
} from '../api/profilePhoto';
import { prepareSquare } from '../lib/imageCompress';
import { getProfile } from '../api/auth';

/**
 * 장인 프로필 사진 (062, SPEC 6-71). 프로필 화면(마이페이지 카드·공개 프로필)에서만 쓴다.
 * 사진이 없거나(경로 없음) 주소를 못 받거나 그림을 못 불러오면 fallback을 그대로 보여 준다 — 사진이 없을 때 화면은 예전과 같다.
 * 경로가 바뀌면(사진을 바꾸면 새 이름) 새 주소를 받아서 옛 사진이 남아 보이지 않는다.
 */
export default function ProfilePhoto({ path, alt, className = 'profile-photo', fallback = null }) {
  const [state, setState] = useState({ path: null, url: null, broken: false });
  useEffect(() => {
    let alive = true;
    setState({ path, url: null, broken: false });
    if (path) profilePhotoUrl(path).then((url) => alive && setState({ path, url, broken: false }));
    return () => { alive = false; };
  }, [path]);
  if (!path || state.path !== path || !state.url || state.broken) return fallback;
  return (
    <img
      src={state.url} alt={alt} className={className} width={512} height={512} decoding="async"
      onError={() => setState((s) => ({ ...s, broken: true }))}
    />
  );
}

/**
 * 프로필 사진 동그라미 = 조작 버튼 (공통 모양, SPEC 6-75 · 6-76). 오른쪽 아래에 늘 "+" 배지.
 * 사진이 없으면 누르자마자 사진 고르기, 있으면 [사진 바꾸기]·[사진 삭제]·[취소] 메뉴. 삭제는 한 번 더 묻는다.
 * 일반 파일 고르기(<input type="file" accept="image/*">) — 앱(iOS·Android)도 같은 방식, 네이티브 플러그인 없음. 메뉴는 바깥·Esc로 닫힘.
 * 무엇을 할지는 부모가 준다: onFile(파일) / onRemove() → 성공 문구(Promise). 실패하면 Error 문구를 그대로 보여 준다.
 * shell: 동그라미 모양 클래스(me-avatar / inf-hero-avatar). image: 동그라미 안에 보일 것(사진 또는 기본 아이콘).
 */
export function AvatarControl({
  shell = 'me-avatar', image, hasPhoto, onFile, onRemove, inputId = 'profile-photo-input',
  label = '프로필 사진 변경', hint, removeQuestion = '프로필 사진을 지우시겠습니까?',
  busyLabels = { file: '올리는 중…', remove: '지우는 중…' },
}) {
  const input = useRef(null);
  const wrap = useRef(null);
  const [panel, setPanel] = useState(null); // null | 'menu' | 'confirm'
  const [busy, setBusy] = useState(null); // 'file' | 'remove'
  const [msg, setMsg] = useState(null); // { ok } | { error }

  const close = () => { setPanel(null); setMsg(null); };

  // 바깥을 누르거나 Esc를 누르면 닫기
  useEffect(() => {
    if (!panel && !msg) return undefined;
    const away = (e) => { if (wrap.current && !wrap.current.contains(e.target)) close(); };
    const esc = (e) => { if (e.key === 'Escape') close(); };
    document.addEventListener('mousedown', away);
    document.addEventListener('keydown', esc);
    return () => { document.removeEventListener('mousedown', away); document.removeEventListener('keydown', esc); };
  }, [panel, msg]);

  const pick = () => { setPanel(null); setMsg(null); input.current?.click(); };
  const onAvatar = () => {
    if (busy) return;
    if (!hasPhoto) pick();
    else { setMsg(null); setPanel((p) => (p ? null : 'menu')); }
  };

  const run = async (kind, job) => {
    setBusy(kind);
    setMsg(null);
    try {
      const ok = await job();
      setPanel(null);
      setMsg(ok ? { ok } : null);
    } catch (err) {
      setMsg({ error: err.message });
    } finally {
      setBusy(null);
    }
  };

  const changed = (e) => {
    const file = e.target.files?.[0];
    e.target.value = ''; // 같은 파일을 다시 골라도 바뀌게
    if (!file) return;
    setPanel(null);
    run('file', () => onFile(file));
  };

  return (
    <div className="avatar-edit" ref={wrap}>
      <input ref={input} id={inputId} type="file" accept="image/*" hidden onChange={changed} aria-label="프로필 사진 파일 고르기" />
      <button
        type="button" className={`${shell} avatar-btn${hasPhoto ? ' has-photo' : ''}`} onClick={onAvatar} disabled={!!busy}
        aria-label={label} aria-haspopup={hasPhoto ? 'true' : undefined} aria-expanded={hasPhoto ? !!panel : undefined}
      >
        {image}
        <span className="avatar-plus" aria-hidden="true">+</span>
      </button>
      {(panel || busy || msg) && (
        <div className="avatar-pop">
          {busy && <p className="notice" role="status">{busyLabels[busy]}</p>}
          {panel === 'menu' && !busy && (
            <div className="avatar-menu" role="group" aria-label="프로필 사진 메뉴">
              <button type="button" className="btn btn-small" onClick={pick} autoFocus data-write>사진 바꾸기</button>
              <button type="button" className="btn btn-small" onClick={() => setPanel('confirm')}>사진 삭제</button>
              <button type="button" className="btn btn-small" onClick={close}>취소</button>
              {hint && <small className="hint">{hint}</small>}
            </div>
          )}
          {panel === 'confirm' && !busy && (
            <div className="avatar-menu" role="group" aria-label="프로필 사진 삭제 확인">
              <span>{removeQuestion}</span>
              <button type="button" className="btn btn-small btn-danger" onClick={() => run('remove', onRemove)}>지우기</button>
              <button type="button" className="btn btn-small" onClick={() => setPanel('menu')} autoFocus>취소</button>
            </div>
          )}
          {msg?.ok && <p className="notice" role="status">{msg.ok}</p>}
          {msg?.error && <p className="form-error" role="alert">{msg.error}</p>}
        </div>
      )}
    </div>
  );
}

/**
 * 내 장인 프로필 사진 (인증된 장인 본인만 — 부모가 고른다. 마이페이지 카드·내 공개 프로필 공통, SPEC 6-75).
 * 고른 사진은 가운데 정사각형 512px로 줄여 올린다(EXIF 빠짐). 바꾸면 옛 파일은 바로 지운다. 서버 함수·제한은 062 그대로.
 * 사진은 내 프로필(auth.profile.photo_path)에서 읽어 바꾼 즉시 반영.
 */
export function ProfileAvatarEditor({ auth, shell = 'me-avatar', fallback = null }) {
  const userId = auth.user.id;
  const path = auth.profile.photo_path ?? null;
  const alt = `${auth.profile.nickname ?? ''} 프로필 사진`;
  const reload = async () => auth.setProfile(await getProfile(userId));
  return (
    <AvatarControl
      shell={shell}
      hasPhoto={!!path}
      image={<ProfilePhoto path={path} alt={alt} className="me-avatar-img" fallback={fallback} />}
      hint="JPG·PNG·WebP, 5MB까지. 가운데를 정사각형으로 잘라 올리며 내 공개 프로필에 보입니다."
      onFile={async (file) => {
        await changeProfilePhoto(userId, file, path);
        await reload();
        return path ? '프로필 사진을 바꿨습니다.' : '프로필 사진을 올렸습니다.';
      }}
      onRemove={async () => {
        await deleteMyProfilePhoto(path);
        await reload();
        return '프로필 사진을 지웠습니다.';
      }}
    />
  );
}

export const APPLICATION_PHOTO_HINT =
  'JPG·PNG·WebP, 5MB까지. 가운데를 정사각형으로 잘라 올립니다. 심사 중에는 나와 운영자만 보고, 승인되면 장인 페이지 프로필 사진이 됩니다.';

/**
 * 장인 인증 신청 사진 — 심사 중인 [내 신청] 카드 (064, SPEC 6-76). 바로 올리고 신청에 붙인다(set_application_photo).
 * 바꾸면 옛 파일은 바로 지우고, 지우면 clear_application_photo. 하루 10번은 장인 사진과 함께 센다(DB).
 * 경로는 처음 값(initialPath)에서 시작해 이 컴포넌트가 들고 있는다 — 바꿀 때마다 페이지 전체를 다시 읽지 않게. onChanged(새 경로 | null)
 */
export function ApplicationPhotoEditor({ userId, initialPath = null, nickname, onChanged, fallback = null }) {
  const [path, setPath] = useState(initialPath);
  const done = (next) => { setPath(next); onChanged?.(next); };
  return (
    <AvatarControl
      inputId="application-photo-input"
      label="신청 프로필 사진 변경"
      hasPhoto={!!path}
      image={<ProfilePhoto path={path} alt={`${nickname ?? ''} 신청 프로필 사진`} className="me-avatar-img" fallback={fallback} />}
      hint={APPLICATION_PHOTO_HINT}
      removeQuestion="신청 사진을 지우시겠습니까? 사진 없이도 심사를 받을 수 있습니다."
      onFile={async (file) => {
        done(await changeApplicationPhoto(userId, file, path));
        return path ? '신청 사진을 바꿨습니다.' : '신청 사진을 올렸습니다.';
      }}
      onRemove={async () => {
        await deleteApplicationPhoto(path);
        done(null);
        return '신청 사진을 지웠습니다.';
      }}
    />
  );
}

/**
 * 장인 인증 신청서의 사진 고르기 (064, 선택 사항). 고르면 이 기기에서 정사각형으로 줄여 미리보기만 하고,
 * [신청 보내기]로 신청이 접수된 뒤 부모가 올린다(uploadApplicationPhoto). value / onChange = 줄인 사진 { blob, mime, ext } | null
 */
export function ApplicationPhotoPicker({ value, onChange, fallback = null }) {
  const [preview, setPreview] = useState(null);
  useEffect(() => {
    if (!value?.blob || typeof URL.createObjectURL !== 'function') { setPreview(null); return undefined; }
    const url = URL.createObjectURL(value.blob);
    setPreview(url);
    return () => URL.revokeObjectURL?.(url);
  }, [value]);
  const image = value && preview ? <img src={preview} alt="고른 프로필 사진" className="me-avatar-img" /> : fallback;
  return (
    <AvatarControl
      inputId="application-photo-input"
      label="신청 프로필 사진 고르기"
      hasPhoto={!!value}
      image={image}
      hint={APPLICATION_PHOTO_HINT}
      removeQuestion="고른 사진을 빼시겠습니까? 사진 없이도 신청할 수 있습니다."
      busyLabels={{ file: '사진을 준비하는 중…', remove: '빼는 중…' }}
      onFile={async (file) => {
        const prepared = await prepareSquare(file);
        onChange(prepared);
        return '사진을 골랐습니다. 신청을 보내면 함께 올라갑니다.';
      }}
      onRemove={async () => {
        onChange(null);
        return '고른 사진을 뺐습니다.';
      }}
    />
  );
}
