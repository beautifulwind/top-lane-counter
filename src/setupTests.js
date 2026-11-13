// jest-dom adds custom jest matchers for asserting on DOM nodes.
// allows you to do things like:
// expect(element).toHaveTextContent(/react/i)
// learn more: https://github.com/testing-library/jest-dom
import '@testing-library/jest-dom';

import { afterEach, vi } from 'vitest';
import { resetFake } from './test/fakeSupabase';
import { resetTitleInfo } from './lib/titles';

// 테스트는 진짜 Supabase 대신 가짜 데이터를 쓴다
vi.mock('./api/supabase', () => import('./test/fakeSupabase'));
afterEach(() => { resetFake(); resetTitleInfo(); });
