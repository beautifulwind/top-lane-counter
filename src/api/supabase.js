// Supabase 클라이언트. 화면 컴포넌트는 이 파일을 직접 쓰지 않고 src/api/의 다른 모듈을 거친다.
import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

/**
 * .env 값 검사. 문제가 있으면 안내 문구, 없으면 null.
 * (키에 다른 글자가 섞이면 모든 요청이 브라우저 안에서 조용히 실패하므로 미리 잡는다)
 */
export function configProblem(u, k) {
  if (!u || !k) return 'Supabase 설정이 없습니다. .env에 VITE_SUPABASE_URL과 VITE_SUPABASE_PUBLISHABLE_KEY를 넣어 주세요.';
  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(u)) {
    return 'VITE_SUPABASE_URL 값이 이상합니다. https://<프로젝트ID>.supabase.co 형태인지 확인해 주세요.';
  }
  if (!/^(sb_publishable_[A-Za-z0-9_-]+|eyJ[A-Za-z0-9_.-]+)$/.test(k)) {
    return 'VITE_SUPABASE_PUBLISHABLE_KEY 값이 이상합니다. 앞뒤 공백이나 다른 글자 없이 sb_publishable_로 시작하는 키만 들어 있는지 확인해 주세요.';
  }
  return null;
}

let client = null;

/** Supabase 클라이언트 (설정이 잘못됐으면 알아보기 쉬운 오류) */
export function db() {
  const problem = configProblem(url, key);
  if (problem) throw new Error(problem);
  // PKCE: 로그인 후 주소로 돌아온 ?code=를 이 브라우저만 가진 값으로 교환한다 (implicit보다 안전)
  client ??= createClient(url, key, { auth: { flowType: 'pkce' } });
  return client;
}
