import { env as rawEnv, SELF } from 'cloudflare:test';
import type { Mock } from 'vitest';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { Env } from '../src/config';

// `cloudflare:test` の env は wrangler.jsonc からしか型を起こせず、
// Secrets が入らない。こちらで定義した形として扱う。
const env = rawEnv as unknown as Env;

/// 入口から出口までの通し。
///
/// モデルの呼び出しだけ差し替える。本物を呼ぶと、テストを回すたびに
/// 費用がかかるうえ、CIから外に出ることになる。

const CANDIDATES = ['かさ', 'ペットボトル', '電池'];

/// Workers AI が返す形の最小限。
function reply(item: string | null, neurons = 14.1) {
  return {
    choices: [{ message: { content: JSON.stringify({ item }) } }],
    usage: { neurons },
  };
}

/// モデルに渡した中身。組み立てたプロンプトまで見たいので形を決めておく。
type Sent = { messages: Array<{ content: string }>; max_tokens: number };

let model: Mock<(name: string, inputs: Sent) => Promise<unknown>>;

beforeEach(() => {
  model = vi.fn(async () => reply('ペットボトル'));
  env.AI = { run: model as never };
  // 中継サーバーは外に出ない。モデルも同じ Cloudflare の上で動くので、
  // ここで fetch が呼ばれたら設計が崩れている。
  vi.stubGlobal('fetch', (input: RequestInfo) => {
    const url = typeof input === 'string' ? input : (input as Request).url;
    throw new Error(`外に出てはいけない: ${url}`);
  });
});

const realGuard = env.GUARD;
afterEach(() => {
  vi.unstubAllGlobals();
  env.GUARD = realGuard;
});

/// 安全弁が答えられない状態を作る。配信のたびに Durable Object は
/// 入れ替わるので、これは実際に起きる。
function breakGuard(failing: Partial<Record<'reserve' | 'refund' | 'settle', true>>) {
  const stub = new Proxy(
    {},
    {
      get(_, name: string) {
        if (failing[name as keyof typeof failing]) {
          return () => Promise.reject(new Error('Durable Object reset'));
        }
        return () => Promise.resolve({ ok: true, remainingToday: 19 });
      },
    },
  );
  env.GUARD = { idFromName: () => 'x', get: () => stub } as never;
}

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
    model.mockImplementation(async () => reply(null));
    const response = await ask({
      deviceId: newDevice(),
      question: 'よくわからないもの',
      candidates: CANDIDATES,
    });
    expect(await response.json()).toMatchObject({ index: null });
  });

  it('候補に無い答えは null にする', async () => {
    model.mockImplementation(async () => reply('宇宙船'));
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
    // 1回あたりの費用の天井。無ければ、思考が長引くだけで費用が伸びる。
    await ask({ deviceId: newDevice(), question: '傘', candidates: CANDIDATES });
    const [, inputs] = model.mock.calls[0]!;
    expect(inputs.max_tokens).toBe(Number(env.MAX_OUTPUT_TOKENS));
  });

  it('設定したモデルに投げる', async () => {
    await ask({ deviceId: newDevice(), question: '傘', candidates: CANDIDATES });
    expect(model.mock.calls[0]![0]).toBe(env.MODEL);
  });

  it('質問と候補だけを渡し、端末IDは渡さない', async () => {
    const device = newDevice();
    await ask({ deviceId: device, question: 'こわれた傘', candidates: CANDIDATES });

    const prompt = model.mock.calls[0]![1].messages[0]!.content;
    expect(prompt).toContain('こわれた傘');
    expect(prompt).toContain('- かさ');
    // 端末IDは数え上げにしか使わない。モデルに渡す理由がない。
    expect(prompt).not.toContain(device);
  });
});

describe('合言葉', () => {
  it('無ければ断る', async () => {
    const response = await SELF.fetch('https://relay.test/v1/sort', {
      method: 'POST',
      body: JSON.stringify({ deviceId: newDevice(), question: '傘', candidates: CANDIDATES }),
    });
    expect(response.status).toBe(401);
    expect(model).not.toHaveBeenCalled();
  });

  it('違っていれば断る', async () => {
    const response = await ask(
      { deviceId: newDevice(), question: '傘', candidates: CANDIDATES },
      { 'x-app-token': 'wrong-token' },
    );
    expect(response.status).toBe(401);
    expect(model).not.toHaveBeenCalled();
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
    expect(model).not.toHaveBeenCalled();
  });

  it('長すぎる質問は400で返し、APIを呼ばない', async () => {
    // ここで通してしまうと、そのぶんのトークン代がかかる。
    const response = await ask({
      deviceId: newDevice(),
      question: 'あ'.repeat(1000),
      candidates: CANDIDATES,
    });
    expect(response.status).toBe(400);
    expect(model).not.toHaveBeenCalled();
  });

  it('候補が多すぎれば400で返し、APIを呼ばない', async () => {
    const response = await ask({
      deviceId: newDevice(),
      question: '傘',
      candidates: Array.from({ length: 200 }, (_, i) => `品目${i}`),
    });
    expect(response.status).toBe(400);
    expect(model).not.toHaveBeenCalled();
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
    model.mockClear();

    const denied = await ask({ deviceId: device, question: '傘', candidates: CANDIDATES });
    expect(denied.status).toBe(429);
    expect(denied.headers.get('retry-after')).toBeTruthy();
    expect(await denied.json()).toMatchObject({ error: 'device_quota_exhausted' });
    expect(model).not.toHaveBeenCalled();
  });
});

describe('APIが落ちたとき', () => {
  it('503で返し、取った回数は戻す', async () => {
    const device = newDevice();
    const ip = '198.51.100.99';
    model.mockRejectedValue(new Error('model unavailable'));

    const failed = await ask(
      { deviceId: device, question: '傘', candidates: CANDIDATES },
      { 'cf-connecting-ip': ip },
    );
    expect(failed.status).toBe(503);
    expect(await failed.json()).toMatchObject({ error: 'upstream_unavailable' });

    // こちらの都合で失敗したぶんは、利用者の回数から引かない。
    model.mockImplementation(async () => reply('かさ'));
    const retried = await ask(
      { deviceId: device, question: '傘', candidates: CANDIDATES },
      { 'cf-connecting-ip': ip },
    );
    expect(await retried.json()).toMatchObject({
      remainingToday: Number(env.DEVICE_DAILY_LIMIT) - 1,
    });
  });

  it('通信そのものが失敗しても503で返す', async () => {
    model.mockRejectedValue(new Error('capacity'));
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

describe('安全弁に訊けないとき', () => {
  it('断る。モデルは呼ばない', async () => {
    // 訊けないまま先へ進むと、上限を数えないままモデルを呼ぶことになる。
    // 止めるための仕組みが止まっているときにいちばん緩むのでは意味がない。
    breakGuard({ reserve: true });

    const response = await ask({
      deviceId: newDevice(),
      question: '傘',
      candidates: CANDIDATES,
    });
    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ error: 'guard_unavailable' });
    expect(model).not.toHaveBeenCalled();
  });

  it('Cloudflareのエラー画面ではなくJSONで返す', async () => {
    // アプリはJSONを期待している。素通しすると「サーバーが壊れた」ではなく
    // 「応答が読めない」として出てしまう。
    breakGuard({ reserve: true });

    const response = await ask({
      deviceId: newDevice(),
      question: '傘',
      candidates: CANDIDATES,
    });
    expect(response.headers.get('content-type')).toContain('application/json');
  });

  it('席を返せなくても、元の失敗を伝える', async () => {
    // 席が1つ戻らないより、応答が壊れるほうが困る。
    breakGuard({ refund: true });
    model.mockRejectedValue(new Error('capacity'));

    const response = await ask({
      deviceId: newDevice(),
      question: '傘',
      candidates: CANDIDATES,
    });
    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ error: 'upstream_unavailable' });
  });

  it('使った額を記録できなくても、答えは返す', async () => {
    // もう払ったぶんなので、捨てると費用だけかかって利用者にも何も渡らない。
    // 積み損ねても暴走はしない。安全弁が答えられない状態なら、次の
    // 問い合わせは席を取る段で断られる。
    breakGuard({ settle: true });

    const response = await ask({
      deviceId: newDevice(),
      question: '傘',
      candidates: CANDIDATES,
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ index: 1 });
  });
});
