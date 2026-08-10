import { env as rawEnv, SELF } from 'cloudflare:test';
import type { Mock } from 'vitest';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { MICRO, type Env } from '../src/config';

// `cloudflare:test` の env は wrangler.jsonc からしか型を起こせず、
// Secrets が入らない。こちらで定義した形として扱う。
const env = rawEnv as unknown as Env;

/// 安全弁が入口まで効いているかを、外から見て確かめる。
///
/// 上限そのものの数え方は guard.test.ts で見ている。ここで見るのは、
/// 上限に達したときに実際に Claude API を呼ばなくなるか、という一点。
/// ここが繋がっていなければ、上限はただの飾りになる。

/// Claude API に渡した中身。組み立てた本文まで見たいので、形を決めておく。
type Sent = { headers: Record<string, string>; body: string };

let upstream: Mock<(input: RequestInfo, init: Sent) => Promise<Response>>;

beforeEach(() => {
  upstream = vi.fn(
    async () =>
      new Response(
        JSON.stringify({
          content: [{ type: 'text', text: '{"item": "かさ"}' }],
          usage: { input_tokens: 500, output_tokens: 20 },
        }),
      ),
  );
  vi.stubGlobal('fetch', (input: RequestInfo, init: RequestInit) => {
    const url = typeof input === 'string' ? input : (input as Request).url;
    if (url.startsWith('https://api.anthropic.com/')) return upstream(input, init as unknown as Sent);
    throw new Error(`外に出てはいけない宛先: ${url}`);
  });
});

afterEach(() => vi.unstubAllGlobals());

function ask() {
  return SELF.fetch('https://relay.test/v1/sort', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-app-token': 'test-app-token',
      'cf-connecting-ip': `203.0.113.${Math.floor(Math.random() * 250) + 1}`,
    },
    body: JSON.stringify({
      deviceId: crypto.randomUUID(),
      question: '傘',
      candidates: ['かさ', '電池'],
    }),
  });
}

/// 予算を使い切った状態にする。
async function burnBudget(microJpy: number) {
  const guard = env.GUARD.get(env.GUARD.idFromName('global'));
  await guard.settle(microJpy, Date.now());
}

describe('予算を使い切ったとき', () => {
  it('まず、使い切る前は通る', async () => {
    expect((await ask()).status).toBe(200);
    expect(upstream).toHaveBeenCalled();
  });

  it('日額に達したら、APIを呼ばずに断る', async () => {
    await burnBudget(Number(env.DAILY_BUDGET_JPY) * MICRO);
    upstream.mockClear();

    const response = await ask();
    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ error: 'budget_exceeded' });
    // ここが肝心。断るだけで呼んでいたら、費用は止まらない。
    expect(upstream).not.toHaveBeenCalled();
  });

  it('いつ戻るかを伝える', async () => {
    await burnBudget(Number(env.DAILY_BUDGET_JPY) * MICRO);

    const response = await ask();
    const retryAfter = Number(response.headers.get('retry-after'));
    expect(retryAfter).toBeGreaterThan(0);
    // 日額なので、遅くとも翌日には戻る。
    expect(retryAfter).toBeLessThanOrEqual(24 * 60 * 60);
  });

  it('使った額は確認できる', async () => {
    // このファイルの前の検査ぶんが既に積まれているので、増えた差で見る。
    const before = await spentTodayJpy();
    await burnBudget(50 * MICRO);

    expect(await spentTodayJpy()).toBe(before + 50);
  });
});

async function spentTodayJpy(): Promise<number> {
  const response = await SELF.fetch('https://relay.test/v1/status', {
    headers: { 'x-admin-token': 'test-admin-token' },
  });
  return ((await response.json()) as { spentTodayJpy: number }).spentTodayJpy;
}
