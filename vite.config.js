import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

// 빌드 때 public/sw.js의 __BUILD_ID__ 를 이번 빌드 번호로 바꾼다 → 배포마다 sw.js 내용이 달라져 브라우저가 새 버전을 알아챈다
function swBuildId() {
  let outDir = 'dist';
  return {
    name: 'sw-build-id',
    apply: 'build',
    configResolved(config) { outDir = join(config.root, config.build.outDir); },
    closeBundle() {
      const file = join(outDir, 'sw.js');
      const code = readFileSync(file, 'utf8');
      if (!code.includes('__BUILD_ID__')) throw new Error('sw.js에 __BUILD_ID__ 자리가 없습니다');
      writeFileSync(file, code.replaceAll('__BUILD_ID__', Date.now().toString(36)));
    },
  };
}

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react(), swBuildId()],
  server: {
    port: 3000,
    // 3000이 이미 쓰이고 있으면 다른 포트로 몰래 넘어가지 않고 바로 실패한다.
    // (서버 두 개가 node_modules/.vite 캐시를 동시에 덮어써서 빈 화면이 생기는 문제 방지)
    strictPort: true,
  },
  optimizeDeps: {
    // 개발 서버가 미리 훑는 시작점은 사이트의 index.html만 (old-app-reference/의 예전 앱 index.html은 훑지 않는다)
    entries: ['index.html'],
    // 미리 묶어 두어 개발 중 의존성 재최적화로 인한 강제 새로고침을 막는다.
    include: ['react', 'react-dom', 'react-dom/client', 'react-router-dom'],
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/setupTests.js'],
    // Edge Function(Deno)의 npm: 가져오기는 테스트에서 빈 모듈로 (함수 안의 순수 로직만 검사한다)
    alias: [{ find: /^npm:.*/, replacement: join(import.meta.dirname, 'src/test/npmStub.js') }],
    exclude: ['**/node_modules/**', 'old-app-reference/**'],
  },
})
