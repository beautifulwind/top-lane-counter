// Supabase 클라이언트. 화면 컴포넌트는 이 파일을 직접 쓰지 않고 src/api/의 다른 모듈을 거친다.
import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

let client = null;

/** Supabase 클라이언트 (설정이 없으면 알아보기 쉬운 오류) */
export function db() {
  if (!url || !key) {
    throw new Error('Supabase 설정이 없어요. .env에 VITE_SUPABASE_URL과 VITE_SUPABASE_PUBLISHABLE_KEY를 넣어 주세요.');
  }
  client ??= createClient(url, key);
  return client;
}
