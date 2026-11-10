// 테스트 전용: Edge Function의 npm: 가져오기 자리 (vite.config.js test.alias). 테스트는 Deno 부분을 실행하지 않는다
export const createClient = () => { throw new Error('테스트에서는 쓰지 않습니다'); };
export default {};
