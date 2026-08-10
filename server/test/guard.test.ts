import { env as rawEnv } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';

import { MICRO, type Env, type Limits } from '../src/config';

// `cloudflare:test` の env は wrangler.jsonc からしか型を起こせず、
// Secrets が入らない。こちらで定義した形として扱う。
const env = rawEnv as unknown as Env;

/// 安全弁の検査。
///
/// 上限を超えたら止まる、という一点がこの機能を出せるかどうかを決める。
/// 広告を入れない以上、費用はそのまま開発者に来る。

const LIMITS: Limits = {
  maxOutputTokens: 2048,
  maxQuestionChars: 100,
  maxCandidates: 30,
  maxCandidateChars: 40,
  deviceDailyLimit: 3,
  ipDailyLimit: 5,
  ipBurstLimit: 4,
  dailyBudgetMicroJpy: 100 * MICRO,
  monthlyBudgetMicroJpy: 500 * MICRO,
};

// 2026-08-10 12:00 JST
const NOON = Date.parse('2026-08-10T03:00:00Z');

let seq = 0;
function freshGuard() {
  return env.GUARD.get(env.GUARD.idFromName(`test-${seq++}`));
}

const DEVICE = '11111111-2222-3333-4444-555555555555';
const OTHER_DEVICE = '99999999-8888-7777-6666-555555555555';

describe('回数の上限', () => {
  it('端末ごとの1日の上限で止まる', async () => {
    const guard = freshGuard();
    for (let i = 0; i < LIMITS.deviceDailyLimit; i++) {
      expect(await guard.reserve(DEVICE, 'ip-a', LIMITS, NOON)).toMatchObject({ ok: true });
    }
    expect(await guard.reserve(DEVICE, 'ip-a', LIMITS, NOON)).toMatchObject({
      ok: false,
      reason: 'device_daily',
    });
  });

  it('残り回数を返す', async () => {
    const guard = freshGuard();
    expect(await guard.reserve(DEVICE, 'ip-a', LIMITS, NOON)).toMatchObject({
      remainingToday: LIMITS.deviceDailyLimit - 1,
    });
  });

  it('別の端末は別に数える', async () => {
    const guard = freshGuard();
    const roomy = { ...LIMITS, ipDailyLimit: 100, ipBurstLimit: 100 };
    for (let i = 0; i < roomy.deviceDailyLimit; i++) {
      await guard.reserve(DEVICE, 'ip-a', roomy, NOON);
    }
    expect(await guard.reserve(OTHER_DEVICE, 'ip-a', roomy, NOON)).toMatchObject({ ok: true });
  });

  it('同じ回線からの合計はIPの上限で止まる', async () => {
    const guard = freshGuard();
    // 端末を入れ替えれば端末ごとの上限はすり抜けられる。
    // 入れ直しでIDを作り直されても効く歯止めがこれ。
    const roomy = { ...LIMITS, ipBurstLimit: 100 };
    for (let i = 0; i < roomy.ipDailyLimit; i++) {
      const device = `${i}0000000-2222-3333-4444-555555555555`;
      expect(await guard.reserve(device, 'ip-a', roomy, NOON)).toMatchObject({ ok: true });
    }
    expect(await guard.reserve(OTHER_DEVICE, 'ip-a', roomy, NOON)).toMatchObject({
      ok: false,
      reason: 'ip_daily',
    });
  });

  it('短時間に集中したら止まり、1分後に戻る', async () => {
    const guard = freshGuard();
    const roomy = { ...LIMITS, deviceDailyLimit: 100, ipDailyLimit: 100 };
    for (let i = 0; i < roomy.ipBurstLimit; i++) {
      await guard.reserve(DEVICE, 'ip-a', roomy, NOON);
    }
    const denied = await guard.reserve(DEVICE, 'ip-a', roomy, NOON);
    expect(denied).toMatchObject({ ok: false, reason: 'ip_burst', retryAfterSec: 60 });

    expect(await guard.reserve(DEVICE, 'ip-a', roomy, NOON + 61_000)).toMatchObject({ ok: true });
  });

  it('日付をまたぐと戻る', async () => {
    const guard = freshGuard();
    for (let i = 0; i < LIMITS.deviceDailyLimit; i++) {
      await guard.reserve(DEVICE, 'ip-a', LIMITS, NOON);
    }
    expect(await guard.reserve(DEVICE, 'ip-a', LIMITS, NOON)).toMatchObject({ ok: false });

    // 日本時間の翌日0時5分。UTCで切っていると、ここではまだ戻らない。
    const nextDay = Date.parse('2026-08-10T15:05:00Z');
    expect(await guard.reserve(DEVICE, 'ip-a', LIMITS, nextDay)).toMatchObject({ ok: true });
  });

  it('日本時間の日付で区切る', async () => {
    const guard = freshGuard();
    // 日本時間 2026-08-10 08:00（UTCではまだ8月9日）。
    const morning = Date.parse('2026-08-09T23:00:00Z');
    // 同じ日の 23:00 JST（UTCでは8月10日）。UTCで切ると別の日になってしまう。
    const night = Date.parse('2026-08-10T14:00:00Z');

    for (let i = 0; i < LIMITS.deviceDailyLimit; i++) {
      expect(await guard.reserve(DEVICE, 'ip-a', LIMITS, morning)).toMatchObject({ ok: true });
    }
    expect(await guard.reserve(DEVICE, 'ip-a', LIMITS, night)).toMatchObject({
      ok: false,
      reason: 'device_daily',
    });
  });
});

describe('金額の上限', () => {
  it('日額を超えたら、回数が残っていても止まる', async () => {
    const guard = freshGuard();
    await guard.settle(LIMITS.dailyBudgetMicroJpy, NOON);

    expect(await guard.reserve(DEVICE, 'ip-a', LIMITS, NOON)).toMatchObject({
      ok: false,
      reason: 'daily_budget',
    });
  });

  it('日額を超えても、翌日には戻る', async () => {
    const guard = freshGuard();
    await guard.settle(LIMITS.dailyBudgetMicroJpy, NOON);
    const nextDay = Date.parse('2026-08-11T03:00:00Z');

    expect(await guard.reserve(DEVICE, 'ip-a', LIMITS, nextDay)).toMatchObject({ ok: true });
  });

  it('月額を超えたら、その日の枠が残っていても止まる', async () => {
    const guard = freshGuard();
    // 日額に触れないよう、前の月日に分けて積む。
    for (let day = 1; day <= 5; day++) {
      const at = Date.parse(`2026-08-0${day}T03:00:00Z`);
      await guard.settle(LIMITS.monthlyBudgetMicroJpy / 5, at);
    }
    expect(await guard.reserve(DEVICE, 'ip-a', LIMITS, NOON)).toMatchObject({
      ok: false,
      reason: 'monthly_budget',
    });
  });

  it('月が変われば戻る', async () => {
    const guard = freshGuard();
    for (let day = 1; day <= 5; day++) {
      await guard.settle(LIMITS.monthlyBudgetMicroJpy / 5, Date.parse(`2026-08-0${day}T03:00:00Z`));
    }
    const nextMonth = Date.parse('2026-09-01T03:00:00Z');
    expect(await guard.reserve(DEVICE, 'ip-a', LIMITS, nextMonth)).toMatchObject({ ok: true });
  });

  it('金額で断るときは回数を消費しない', async () => {
    const guard = freshGuard();
    await guard.settle(LIMITS.dailyBudgetMicroJpy, NOON);
    for (let i = 0; i < 10; i++) {
      await guard.reserve(DEVICE, 'ip-a', LIMITS, NOON);
    }
    // 予算が戻った翌日、回数は手つかずで残っているべき。
    const nextDay = Date.parse('2026-08-11T03:00:00Z');
    for (let i = 0; i < LIMITS.deviceDailyLimit; i++) {
      expect(await guard.reserve(DEVICE, 'ip-a', LIMITS, nextDay)).toMatchObject({ ok: true });
    }
  });

  it('使った額を月と日の両方に積む', async () => {
    const guard = freshGuard();
    await guard.settle(3 * MICRO, NOON);
    await guard.settle(4 * MICRO, NOON);

    const status = await guard.status(LIMITS, NOON);
    expect(status.spentTodayMicroJpy).toBe(7 * MICRO);
    expect(status.spentMonthMicroJpy).toBe(7 * MICRO);
  });
});

describe('席の返却', () => {
  it('返せば、また使える', async () => {
    const guard = freshGuard();
    for (let i = 0; i < LIMITS.deviceDailyLimit; i++) {
      await guard.reserve(DEVICE, 'ip-a', LIMITS, NOON);
    }
    expect(await guard.reserve(DEVICE, 'ip-a', LIMITS, NOON)).toMatchObject({ ok: false });

    await guard.refund(DEVICE, 'ip-a', NOON);
    expect(await guard.reserve(DEVICE, 'ip-a', LIMITS, NOON)).toMatchObject({ ok: true });
  });

  it('取っていない席は返せない', async () => {
    const guard = freshGuard();
    // 使っていない状態で返しても、枠が増えたりはしない。
    await guard.refund(DEVICE, 'ip-a', NOON);
    await guard.refund(DEVICE, 'ip-a', NOON);

    for (let i = 0; i < LIMITS.deviceDailyLimit; i++) {
      expect(await guard.reserve(DEVICE, 'ip-a', LIMITS, NOON)).toMatchObject({ ok: true });
    }
    expect(await guard.reserve(DEVICE, 'ip-a', LIMITS, NOON)).toMatchObject({ ok: false });
  });
});

describe('同時に来ても数え落とさない', () => {
  it('一斉に投げても上限ちょうどしか通さない', async () => {
    const guard = freshGuard();
    const roomy = { ...LIMITS, deviceDailyLimit: 5, ipDailyLimit: 100, ipBurstLimit: 100 };

    const verdicts = await Promise.all(
      Array.from({ length: 20 }, () => guard.reserve(DEVICE, 'ip-a', roomy, NOON)),
    );
    expect(verdicts.filter((v: { ok: boolean }) => v.ok)).toHaveLength(roomy.deviceDailyLimit);
  });
});
