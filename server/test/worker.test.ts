import { env as rawEnv, SELF } from 'cloudflare:test';
import type { Mock } from 'vitest';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { Env } from '../src/config';

// `cloudflare:test` の env は wrangler.jsonc からしか型を起こせず、
// Secrets が入らない。こちらで定義した形として扱う。
const env = rawEnv as unknown as Env;

/// 入口から出口までの通し。
///
/// Claude API への問い合わせだけ差し替える。ここで本物を呼ぶと、
/// テストを回すたびに費用がかかる。

const CANDIDATES = ['かさ', 'ペットボトル', '電池'];

/// APIが返す形の最小限。
function reply(item: string | null, tokens = { input: 500, output: 20 }) {
  return new Response(
    JSON.stringify({
      content: [{ type: 'text', text: JSON.stringify({ item }) }],
      usage: { input_tokens: tokens.input, output_tokens: tokens.output },
    }),
    { headers: { 'content-type': 'application/json' } },
  );
}

/// Claude API に渡した中身。組み立てた本文まで見たいので、形を決めておく。
type Sent = { headers: Record<string, string>; body: string };

let upstream: Mock<(input: RequestInfo, init: Sent) => Promise<Response>>;

beforeEach(() => {
  upstream = vi.fn(async () => reply('ペットボトル'));
  vi.stubGlobal('fetch', (input: RequestInfo, init: RequestInit) => {
    const url = typeof input === 'string' ? input : (input as Request).url;
    if (url.startsWith('https://api.anthropic.com/')) return upstream(input, init as unknown as Sent);
    throw new Error(`外に出てはいけない宛先: ${url}`);
  });
});

afterEach(() => vi.unstubAllGlobals());

function ask(body: unknown, headers: Record<string, string> = {}) {
  return SELF.fetch('https://relay.test/v1/sort', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-app-token': 'test-app-token',
      'cf-connecting-ip': `203.0.113.${Math.floor(Math.random() * 250) + 1}`,
      ...headers,
    },
    body: JSON.stringify(body),
  });
}

function newDevice() {
  return crypto.randomUUID();
}

describe('分別の問い合わせ', () => {
  it('選ばれた候補の番号を返す', async () => {
    const response = await ask({
      deviceId: newDevice(),
      question: 'ペットボトル',
      candidates: CANDIDATES,
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ index: 1 });
  });

  it('該当なしは null を返す', async () => {
    upstream.mockImplementation(async () => reply(null));
    const response = await ask({
      deviceId: newDevice(),
      question: 'よくわからないもの',
      candidates: CANDIDATES,
    });
    expect(await response.json()).toMatchObject({ index: null });
  });

  it('候補に無い答えは null にする', async () => {
    upstream.mockImplementation(async () => reply('宇宙船'));
    const response = await ask({
      deviceId: newDevice(),
      question: '傘',
      candidates: CANDIDATES,
    });
    expect(await response.json()).toMatchObject({ index: null });
  });

  it('残り回数を返す', async () => {
    const device = newDevice();
    const first = await (await ask({ deviceId: device, question: '傘', candidates: CANDIDATES })).json();
    const second = await (await ask({ deviceId: device, question: '傘', candidates: CANDIDATES })).json();
    expect((second as { remainingToday: number }).remainingToday).toBe(
      (first as { remainingToday: number }).remainingToday - 1,
    );
  });

  it('出力の長さに天井を付けている', async () => {
    await ask({ deviceId: newDevice(), question: '傘', candidates: CANDIDATES });
    const body = JSON.parse(upstream.mock.calls[0]![1].body);
    expect(body.max_tokens).toBeLessThanOrEqual(64);
  });

  it('APIキーはヘッダで渡し、本文には入れない', async () => {
    await ask({ deviceId: newDevice(), question: '傘', candidates: CANDIDATES });
    const [, init] = upstream.mock.calls[0]!;
    expect(init.headers['x-api-key']).toBe('test-api-key');
    expect(init.body).not.toContain('test-api-key');
  });
});

describe('合言葉', () => {
  it('無ければ断る', async () => {
    const response = await SELF.fetch('https://relay.test/v1/sort', {
      method: 'POST',
      body: JSON.stringify({ deviceId: newDevice(), question: '傘', candidates: CANDIDATES }),
    });
    expect(response.status).toBe(401);
    expect(upstream).not.toHaveBeenCalled();
  });

  it('違っていれば断る', async () => {
    const response = await ask(
      { deviceId: newDevice(), question: '傘', candidates: CANDIDATES },
      { 'x-app-token': 'ちがう' },
    );
    expect(response.status).toBe(401);
    expect(upstream).not.toHaveBeenCalled();
  });
});

describe('形が違うものを外に出さない', () => {
  it('壊れたJSONは400で返し、APIを呼ばない', async () => {
    const response = await SELF.fetch('https://relay.test/v1/sort', {
      method: 'POST',
      headers: { 'x-app-token': 'test-app-token' },
      body: '{壊れている',
    });
    expect(response.status).toBe(400);
    expect(upstream).not.toHaveBeenCalled();
  });

  it('長すぎる質問は400で返し、APIを呼ばない', async () => {
    // ここで通してしまうと、そのぶんのトークン代がかかる。
    const response = await ask({
      deviceId: newDevice(),
      question: 'あ'.repeat(1000),
      candidates: CANDIDATES,
    });
    expect(response.status).toBe(400);
    expect(upstream).not.toHaveBeenCalled();
  });

  it('候補が多すぎれば400で返し、APIを呼ばない', async () => {
    const response = await ask({
      deviceId: newDevice(),
      question: '傘',
      candidates: Array.from({ length: 200 }, (_, i) => `品目${i}`),
    });
    expect(response.status).toBe(400);
    expect(upstream).not.toHaveBeenCalled();
  });
});

describe('回数を使い切ったとき', () => {
  it('429で断り、APIを呼ばない', async () => {
    const device = newDevice();
    const limit = Number(env.DEVICE_DAILY_LIMIT);

    // IPは毎回変える。端末ごとの上限だけを見たいので、
    // 同じ回線への制限（#43のもう一段）に先に当たらないようにする。
    // 入れ直しではなくIPを変えても端末IDが同じなら効く、ということでもある。
    for (let i = 0; i < limit; i++) {
      const ok = await ask({ deviceId: device, question: '傘', candidates: CANDIDATES });
      expect(ok.status).toBe(200);
    }
    upstream.mockClear();

    const denied = await ask({ deviceId: device, question: '傘', candidates: CANDIDATES });
    expect(denied.status).toBe(429);
    expect(denied.headers.get('retry-after')).toBeTruthy();
    expect(await denied.json()).toMatchObject({ error: 'device_quota_exhausted' });
    expect(upstream).not.toHaveBeenCalled();
  });
});

describe('APIが落ちたとき', () => {
  it('503で返し、取った回数は戻す', async () => {
    const device = newDevice();
    const ip = '198.51.100.99';
    upstream.mockImplementation(async () => new Response('overloaded', { status: 529 }));

    const failed = await ask(
      { deviceId: device, question: '傘', candidates: CANDIDATES },
      { 'cf-connecting-ip': ip },
    );
    expect(failed.status).toBe(503);
    expect(await failed.json()).toMatchObject({ error: 'upstream_unavailable' });

    // こちらの都合で失敗したぶんは、利用者の回数から引かない。
    upstream.mockImplementation(async () => reply('かさ'));
    const retried = await ask(
      { deviceId: device, question: '傘', candidates: CANDIDATES },
      { 'cf-connecting-ip': ip },
    );
    expect(await retried.json()).toMatchObject({
      remainingToday: Number(env.DEVICE_DAILY_LIMIT) - 1,
    });
  });

  it('通信そのものが失敗しても503で返す', async () => {
    upstream.mockRejectedValue(new Error('network down'));
    const response = await ask({ deviceId: newDevice(), question: '傘', candidates: CANDIDATES });
    expect(response.status).toBe(503);
  });
});

describe('使用額の確認', () => {
  it('合言葉が無ければ見せない', async () => {
    const response = await SELF.fetch('https://relay.test/v1/status');
    expect(response.status).toBe(401);
  });

  it('使った額と上限を返す', async () => {
    await ask({ deviceId: newDevice(), question: '傘', candidates: CANDIDATES });
    const response = await SELF.fetch('https://relay.test/v1/status', {
      headers: { 'x-admin-token': 'test-admin-token' },
    });
    const body = (await response.json()) as Record<string, number>;

    expect(body.spentTodayJpy).toBeGreaterThan(0);
    expect(body.dailyBudgetJpy).toBe(Number(env.DAILY_BUDGET_JPY));
    expect(body.monthlyBudgetJpy).toBe(Number(env.MONTHLY_BUDGET_JPY));
  });
});

describe('その他', () => {
  it('生存確認に応える', async () => {
    const response = await SELF.fetch('https://relay.test/healthz');
    expect(response.status).toBe(200);
  });

  it('知らない道は404', async () => {
    expect((await SELF.fetch('https://relay.test/v1/anything')).status).toBe(404);
  });
});
