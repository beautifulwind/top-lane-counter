import { useState } from 'react';
import { disableDevicePush, enableDevicePush, getDevicePush, getPushSettings, savePushSettings } from '../api/push';
import { PUSH_HELP, currentPushSupport } from '../lib/push';
import { useAsync } from '../lib/useAsync';
import { APPROVAL_ENABLED } from '../lib/features';
import { ErrorBox, Loading } from './Status';
import SectionHead from './SectionHead';
import { BellIcon } from './Icons';

/**
 * /me/settings "휴대폰 알림" (037, SPEC 6-24): 이 기기에서 잠금 화면 알림 켜기/끄기 + 받을 알림 종류.
 * - 켜기/끄기는 기기마다 (이 브라우저·이 홈 화면 앱). 종류 설정은 계정 하나에 한 번 (알림을 켠 모든 기기에 적용)
 * - 운영진 알림 칸은 운영자 계정·감독관에게만 보인다. 운영자 모드를 끈 동안에는 설정과 관계없이 운영진 알림이 오지 않는다
 */
export default function PushSettings({ auth }) {
  const support = currentPushSupport();
  const staffAccount = auth.isOperatorAccount || auth.isModerator;
  return (
    <section className="me-section" aria-labelledby="push-settings">
      <SectionHead icon={BellIcon} id="push-settings">휴대폰 알림</SectionHead>
      <p className="lead">
        {APPROVAL_ENABLED
          ? `켜 두면 ${staffAccount ? '새 제안·문의나 ' : ''}내 제안의 처리 결과를 휴대폰 잠금 화면 알림으로 받습니다.`
          : `켜 두면 ${staffAccount ? '새 상대법·새 빌드·새 문의나 ' : ''}숨겨졌던 내 상대법·빌드가 다시 공개된 소식을 휴대폰 잠금 화면 알림으로 받습니다.`}
        알림을 누르면 그 내용을 볼 수 있는 화면으로 갑니다.
      </p>
      {support === 'ok' ? <DeviceSwitch userId={auth.user.id} /> : <p className="hint push-help" role="note">{PUSH_HELP[support]}</p>}
      <PushKinds userId={auth.user.id} staffAccount={staffAccount} operatorOff={auth.isOperatorAccount && !auth.isOperator} />
    </section>
  );
}

function DeviceSwitch({ userId }) {
  const loaded = useAsync(getDevicePush, [userId]);
  const [changed, setChanged] = useState(null); // 켜기/끄기를 누른 뒤의 값 (다시 불러오지 않는다)
  const on = changed ?? loaded.data;
  const { error, loading, retry } = loaded;
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState(null);

  const toggle = async () => {
    if (busy) return;
    setBusy(true);
    setActionError(null);
    try {
      if (on) await disableDevicePush();
      else await enableDevicePush(userId);
      setChanged(!on);
    } catch (e) {
      setActionError(e.message);
    }
    setBusy(false);
  };

  if (changed === null && loading) return <Loading />;
  if (changed === null && error) return <ErrorBox error={error} onRetry={retry} />;
  return (
    <>
      <p className="operator-mode-state" role="status">
        이 기기: <strong>{on ? '켜짐' : '꺼짐'}</strong>
      </p>
      <button type="button" className="btn btn-small" onClick={toggle} disabled={busy} aria-pressed={on}>
        {busy ? '바꾸는 중…' : on ? '이 기기에서 알림 끄기' : '이 기기에서 알림 켜기'}
      </button>
      {actionError && <p className="form-error" role="alert">{actionError}</p>}
      <small className="hint push-note">로그아웃하면 이 기기의 알림도 꺼집니다. 다른 기기는 그 기기에서 따로 켜 주세요.</small>
    </>
  );
}

function PushKinds({ userId, staffAccount, operatorOff }) {
  const loaded = useAsync(() => getPushSettings(userId), [userId]);
  const [saved, setData] = useState(null); // 바꾼 뒤의 값
  const settings = saved ?? loaded.data;
  const { error, loading, retry } = loaded;
  const [busy, setBusy] = useState(false);
  const [saveError, setSaveError] = useState(null);

  const change = async (key, value) => {
    if (busy) return;
    const before = settings;
    const next = { ...settings, [key]: value };
    setData(next);
    setBusy(true);
    setSaveError(null);
    try {
      setData(await savePushSettings(userId, next));
    } catch (e) {
      setData(before);
      setSaveError(e.message);
    }
    setBusy(false);
  };

  if (!saved && loading) return <Loading />;
  if (!saved && error) return <ErrorBox error={error} onRetry={retry} />;
  return (
    <fieldset className="push-kinds" disabled={busy}>
      <legend>받을 알림 (알림을 켠 모든 기기에 적용)</legend>
      {staffAccount && (
        <label className="check-row">
          <input type="checkbox" checked={settings.staff_new} onChange={(e) => change('staff_new', e.target.checked)} />
          <span>
            {APPROVAL_ENABLED ? '운영진 알림: 새 제안·새 빌드·새 문의' : '운영진 알림: 새 상대법·새 빌드·새 문의'}
            {operatorOff && <small className="hint">운영자 모드를 끈 동안에는 오지 않습니다.</small>}
          </span>
        </label>
      )}
      <label className="check-row">
        <input type="checkbox" checked={settings.my_results} onChange={(e) => change('my_results', e.target.checked)} />
        {/* DB 칸 이름은 그대로 my_results. 승인 제도를 끈 뒤에도 "다시 공개" 알림(counter_restored·build_restored)은 이 설정을 따른다 */}
        <span>{APPROVAL_ENABLED ? '내 제안 결과: 승인·거절·재검토 요청·다시 공개' : '내 상대법·빌드 다시 공개: 숨겨졌던 것이 다시 공개됐을 때'}</span>
      </label>
      {saveError && <p className="form-error" role="alert">{saveError}</p>}
    </fieldset>
  );
}
