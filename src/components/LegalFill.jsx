/**
 * legal.js의 값 하나. 비어 있으면 노란 칸으로 "【채워 주세요: …】"를 크게 보여 준다 (배포 전에 빠뜨리지 않게).
 * email: 값이 있으면 메일 링크로
 */
export default function LegalFill({ value, label, email = false }) {
  if (!value) return <mark className="fill-me">【채워 주세요: {label}】</mark>;
  if (email) return <a href={`mailto:${value}`}>{value}</a>;
  return <>{value}</>;
}
