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
 * 내 프로필 사진 동그라미 = 조작 버튼 (인증된 장인 본인만 — 부모가 고른다. 마이페이지 카드·내 공개 프로필 공통, SPEC 6-75).
 * 오른쪽 아래에 늘 "+" 배지. 사진이 없으면 누르자마자 사진 고르기, 있으면 [사진 바꾸기]·[사진 삭제]·[취소] 메뉴.
 * 삭제는 한 번 더 묻는다. 일반 파일 고르기(<input type="file" accept="image/*">) — 앱(iOS·Android)도 같은 방식, 네이티브 플러그인 없음.
 * 고른 사진은 가운데 정사각형 512px로 줄여 올린다(EXIF 빠짐). 바꾸면 옛 파일은 바로 지운다. 서버 함수·제한은 062 그대로.
 * shell: 동그라미 모양 클래스(me-avatar / inf-hero-avatar). 사진은 내 프로필(auth.profile.photo_path)에서 읽어 바꾼 즉시 반영.
 */
export function ProfileAvatarEditor({ auth, shell = 'me-avatar', fallback = null }) {
  const input = useRef(null);
  const wrap = useRef(null);
  const [panel, setPanel] = useState(null); // null | 'menu' | 'confirm'
  const [busy, setBusy] = useState(null); // 'upload' | 'delete'
  const [msg, setMsg] = useState(null); // { ok } | { error }
  const userId = auth.user.id;
  const path = auth.profile.photo_path ?? null;
  const alt = `${auth.profile.nickname ?? ''} 프로필 사진`;

  const reload = async () => auth.setProfile(await getProfile(userId));
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
    if (!path) pick();
    else { setMsg(null); setPanel((p) => (p ? null : 'menu')); }
  };

  const onFile = async (e) => {
    const file = e.target.files?.[0];
    e.target.value = ''; // 같은 파일을 다시 골라도 바뀌게
    if (!file) return;
    setBusy('upload');
    setMsg(null);
    setPanel(null);
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
      setPanel(null);
      setMsg({ ok: '프로필 사진을 지웠습니다.' });
    } catch (err) {
      setMsg({ error: err.message });
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="avatar-edit" ref={wrap}>
      <input
        ref={input} id="profile-photo-input" type="file" accept="image/*" hidden onChange={onFile}
        aria-label="프로필 사진 파일 고르기"
      />
      <button
        type="button" className={`${shell} avatar-btn${path ? ' has-photo' : ''}`} onClick={onAvatar} disabled={!!busy}
        aria-label="프로필 사진 변경" aria-haspopup={path ? 'true' : undefined} aria-expanded={path ? !!panel : undefined}
      >
        <ProfilePhoto path={path} alt={alt} className="me-avatar-img" fallback={fallback} />
        <span className="avatar-plus" aria-hidden="true">+</span>
      </button>
      {(panel || busy || msg) && (
        <div className="avatar-pop">
          {busy && <p className="notice" role="status">{busy === 'upload' ? '올리는 중…' : '지우는 중…'}</p>}
          {panel === 'menu' && !busy && (
            <div className="avatar-menu" role="group" aria-label="프로필 사진 메뉴">
              <button type="button" className="btn btn-small" onClick={pick} autoFocus>사진 바꾸기</button>
              <button type="button" className="btn btn-small" onClick={() => setPanel('confirm')}>사진 삭제</button>
              <button type="button" className="btn btn-small" onClick={close}>취소</button>
              <small className="hint">JPG·PNG·WebP, 5MB까지. 가운데를 정사각형으로 잘라 올리며 내 공개 프로필에 보입니다.</small>
            </div>
          )}
          {panel === 'confirm' && !busy && (
            <div className="avatar-menu" role="group" aria-label="프로필 사진 삭제 확인">
              <span>프로필 사진을 지우시겠습니까?</span>
              <button type="button" className="btn btn-small btn-danger" onClick={remove}>지우기</button>
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
