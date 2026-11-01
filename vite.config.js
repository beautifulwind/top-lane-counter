import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    // 3000이 이미 쓰이고 있으면 다른 포트로 몰래 넘어가지 않고 바로 실패한다.
    // (서버 두 개가 node_modules/.vite 캐시를 동시에 덮어써서 빈 화면이 생기는 문제 방지)
    strictPort: true,
  },
  optimizeDeps: {
    // 미리 묶어 두어 개발 중 의존성 재최적화로 인한 강제 새로고침을 막는다.
    include: ['react', 'react-dom', 'react-dom/client', 'react-router-dom'],
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/setupTests.js'],
  },
})
