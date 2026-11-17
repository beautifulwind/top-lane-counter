// SPEC 6-64: 실제 @capacitor/core의 registerPlugin() 플러그인 객체(Proxy)로 Apple 시트 호출이 끝나는지 확인한다.
// (appleLogin.test.jsx는 @capacitor/core를 가짜로 바꾸므로 Proxy의 then 문제를 잡지 못한다.)
import { describe, expect, test, vi } from 'vitest';
import { registerPlugin } from '@capacitor/core';
import { getAppleAuthorizationCode, signInWithAppleSheet } from '../lib/appleAuth';

const signIn = vi.fn(async () => ({ idToken: 'proxy-token' }));
const realPlugin = registerPlugin('AppleSignInProxyTest', { web: { signIn } });

describe('Apple 플러그인 불러오기 (실제 Capacitor Proxy)', () => {
  test('Proxy는 then을 가진 것처럼 보인다 — 직접 await하면 안 되는 이유', () => {
    expect(typeof realPlugin.then).toBe('function');
  });

  test('모듈 모양 { AppleSignIn: Proxy }로 불러오면 시트 호출까지 가고 끝난다', async () => {
    const result = await signInWithAppleSheet({ load: async () => ({ AppleSignIn: realPlugin }) });
    expect(result.idToken).toBe('proxy-token');
    expect(signIn).toHaveBeenCalledTimes(1);
  });

  test('불러오기가 끝나지 않으면 제한 시간 뒤 오류로 끝난다 (로딩이 영원히 돌지 않게)', async () => {
    // 실제 Proxy를 그대로 돌려주는 옛 모양: 끝나지 않는 load와 같다
    const p = signInWithAppleSheet({ load: () => new Promise(() => {}), loadTimeoutMs: 50 });
    await expect(p).rejects.toThrow('Apple 로그인 기능을 불러오지 못했습니다.');
    expect(signIn).toHaveBeenCalledTimes(1); // 앞 테스트의 1회뿐 — 시트는 열리지 않았다
  });

  test('모듈에 AppleSignIn이 없으면 바로 오류', async () => {
    await expect(signInWithAppleSheet({ load: async () => ({}) })).rejects.toThrow('Apple 로그인 기능을 불러오지 못했습니다.');
  });
});

// 6-65: 탈퇴 전 Apple 재확인도 같은 불러오기 방식 (Proxy를 await하지 않음)
describe('탈퇴 전 Apple 재확인 (실제 Capacitor Proxy)', () => {
  const codeSignIn = vi.fn(async () => ({ idToken: 't', authorizationCode: 'proxy-code' }));
  const codePlugin = registerPlugin('AppleSignInCodeTest', { web: { signIn: codeSignIn } });

  test('모듈 모양으로 불러오면 코드를 받아 끝난다', async () => {
    await expect(getAppleAuthorizationCode({ load: async () => ({ AppleSignIn: codePlugin }) })).resolves.toBe('proxy-code');
    expect(codeSignIn).toHaveBeenCalledTimes(1);
  });

  test('불러오기가 끝나지 않으면 제한 시간 뒤 오류', async () => {
    await expect(getAppleAuthorizationCode({ load: () => new Promise(() => {}), loadTimeoutMs: 50 })).rejects.toThrow();
  });

  test('코드가 없으면 탈퇴하지 않는다는 오류', async () => {
    const empty = registerPlugin('AppleSignInEmptyTest', { web: { signIn: async () => ({ idToken: 't' }) } });
    await expect(getAppleAuthorizationCode({ load: async () => ({ AppleSignIn: empty }) })).rejects.toThrow('탈퇴하지 않았습니다');
  });
});
