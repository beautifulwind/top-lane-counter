export function Loading() {
  return (
    <p className="status" role="status">
      불러오는 중…
    </p>
  );
}

export function ErrorBox({ error, onRetry }) {
  return (
    <div className="status status-error" role="alert">
      <p>데이터를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.</p>
      {error && <small>{String(error.message ?? error)}</small>}
      <div className="actions center">
        <button type="button" className="btn" onClick={onRetry ?? (() => window.location.reload())}>
          다시 시도
        </button>
      </div>
    </div>
  );
}

/** 아직 기능이 연결되지 않은 버튼 (로그인·제안은 이후 단계) */
export function PendingButton({ children }) {
  return (
    <button
      type="button"
      className="btn"
      onClick={() => alert('준비 중인 기능입니다. (로그인·제안 기능은 다음 단계에서 연결됩니다)')}
    >
      {children}
    </button>
  );
}
