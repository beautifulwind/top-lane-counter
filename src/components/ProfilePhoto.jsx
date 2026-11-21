import { useEffect, useRef, useState } from 'react';
import { changeProfilePhoto, deleteMyProfilePhoto, profilePhotoUrl } from '../api/profilePhoto';
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
 * 마이페이지 프로필 카드의 [프로필 사진 올리기]/[사진 바꾸기]·[사진 삭제] (인증된 장인만 — 부모가 고른다).
 * 일반 파일 고르기(<input type="file" accept="image/*">)를 쓴다 — 앱(iOS·Android)도 같은 방식, 네이티브 플러그인 없음.
 * 고른 사진은 가운데 정사각형 512px로 줄여 올린다(사진 정보 EXIF는 빠짐). 바꾸면 옛 파일은 바로 지운다.
 */
export function ProfilePhotoEditor({ auth }) {
  const input = useRef(null);
  const [busy, setBusy] = useState(null); // 'upload' | 'delete'
  const [confirming, setConfirming] = useState(false);
  const [msg, setMsg] = useState(null); // { ok } | { error }
  const userId = auth.user.id;
  const path = auth.profile.photo_path ?? null;

  const reload = async () => auth.setProfile(await getProfile(userId));

  const onFile = async (e) => {
    const file = e.target.files?.[0];
    e.target.value = ''; // 같은 파일을 다시 골라도 바뀌게
    if (!file) return;
    setBusy('upload');
    setMsg(null);
    setConfirming(false);
    try {
      await changeProfilePhoto(userId, file, path);
      await reload();
      setMsg({ ok: path ? '프로필 사진을 바꿨습니다.' : '프로필 사진을 올렸습니다.' });
    } catch (err) {
      setMsg({ error: err.message });
    } finally {
      setBusy(null);
    }
  };

  const remove = async () => {
    setBusy('delete');
    setMsg(null);
    try {
      await deleteMyProfilePhoto(path);
      await reload();
      setConfirming(false);
      setMsg({ ok: '프로필 사진을 지웠습니다.' });
    } catch (err) {
      setMsg({ error: err.message });
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="photo-editor">
      <input
        ref={input} id="profile-photo-input" type="file" accept="image/*" hidden onChange={onFile}
        aria-label="프로필 사진 파일 고르기"
      />
      <div className="row-actions">
        <button type="button" className="btn btn-small" onClick={() => input.current?.click()} disabled={!!busy}>
          {busy === 'upload' ? '올리는 중…' : path ? '사진 바꾸기' : '프로필 사진 올리기'}
        </button>
        {path && !confirming && (
          <button type="button" className="btn btn-small" onClick={() => { setConfirming(true); setMsg(null); }} disabled={!!busy}>사진 삭제</button>
        )}
        {path && confirming && (
          <span className="photo-confirm" role="group" aria-label="프로필 사진 삭제 확인">
            <span>프로필 사진을 지우시겠습니까?</span>
            <button type="button" className="btn btn-small btn-danger" onClick={remove} disabled={!!busy}>
              {busy === 'delete' ? '지우는 중…' : '지우기'}
            </button>
            <button type="button" className="btn btn-small" onClick={() => setConfirming(false)} disabled={!!busy} autoFocus>취소</button>
          </span>
        )}
      </div>
      <small className="hint">JPG·PNG·WebP, 5MB까지. 가운데를 정사각형으로 잘라 올리며 내 공개 프로필에 보입니다.</small>
      {msg?.ok && <p className="notice" role="status">{msg.ok}</p>}
      {msg?.error && <p className="form-error" role="alert">{msg.error}</p>}
    </div>
  );
}
