import { DurableObject } from 'cloudflare:workers';

import type { Limits } from './config';
import { jstDay, jstMinute, jstMonth } from './time';

/// 安全弁。回数と金額の両方を数え、上限を超えたら断る。
///
/// 全リクエストがこの1つの実体を通る。だから数え落としも二重計上も起きない。
/// KVのような結果整合の置き場だと、同時に来た分を数え落として上限を
/// すり抜けるので、ここは強い一貫性のある Durable Object を使う。
///
/// 台数が増えて1つでは捌けなくなったら、金額だけをここに残し、
/// 回数は端末IDで分割すればよい。当面その必要はない。
export class Guard extends DurableObject {
  private readonly sql = this.ctx.storage.sql;

  constructor(ctx: DurableObjectState, env: unknown) {
    super(ctx, env as never);
    this.sql.exec(`
      CREATE TABLE IF NOT EXISTS counters (
        key        TEXT PRIMARY KEY,
        n          INTEGER NOT NULL,
        expires_at INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS counters_expires ON counters (expires_at);
      CREATE TABLE IF NOT EXISTS spend (
        bucket    TEXT PRIMARY KEY,
        micro_jpy INTEGER NOT NULL
      );
    `);
  }

  /// 1回ぶんの席を取る。取れたら回数を進める。
  ///
  /// 問い合わせる前に必ず通す。あとから数えると、断るべきものを
  /// APIに投げてしまってから気づくことになる。
  reserve(deviceId: string, ipHash: string, limits: Limits, nowMs: number): Verdict {
    const now = new Date(nowMs);
    const day = jstDay(now);
    const month = jstMonth(now);
    const minute = jstMinute(now);

    this.sql.exec('DELETE FROM counters WHERE expires_at < ?', nowMs);

    // 金額を先に見る。使いすぎを止めるのがこの仕組みの主目的で、
    // 回数の上限はその内側にある補助でしかない。
    const spentToday = this.spent(day);
    if (spentToday >= limits.dailyBudgetMicroJpy) {
      return { ok: false, reason: 'daily_budget', retryAfterSec: secondsToNextJstDay(now) };
    }
    const spentMonth = this.spent(month);
    if (spentMonth >= limits.monthlyBudgetMicroJpy) {
      return { ok: false, reason: 'monthly_budget', retryAfterSec: secondsToNextJstDay(now) };
    }

    const checks: Array<[string, number, number, DenyReason]> = [
      [`d:${deviceId}:${day}`, limits.deviceDailyLimit, endOfJstDayMs(now), 'device_daily'],
      [`i:${ipHash}:${day}`, limits.ipDailyLimit, endOfJstDayMs(now), 'ip_daily'],
      [`b:${ipHash}:${minute}`, limits.ipBurstLimit, nowMs + 60_000, 'ip_burst'],
    ];
    for (const [key, limit, , reason] of checks) {
      if (this.count(key) >= limit) {
        return {
          ok: false,
          reason,
          retryAfterSec:
            reason === 'ip_burst' ? 60 : secondsToNextJstDay(now),
        };
      }
    }

    // すべて通ってから進める。途中で断る場合に数えてしまうと、
    // 断られた回数ぶん本来使えるはずの枠が減る。
    for (const [key, , expiresAt] of checks) {
      this.sql.exec(
        `INSERT INTO counters (key, n, expires_at) VALUES (?, 1, ?)
         ON CONFLICT (key) DO UPDATE SET n = n + 1`,
        key,
        expiresAt,
      );
    }
    return { ok: true, remainingToday: limits.deviceDailyLimit - this.count(`d:${deviceId}:${day}`) };
  }

  /// 実際にかかった額を記録する。
  settle(microJpy: number, nowMs: number): void {
    const now = new Date(nowMs);
    for (const bucket of [jstDay(now), jstMonth(now)]) {
      this.sql.exec(
        `INSERT INTO spend (bucket, micro_jpy) VALUES (?, ?)
         ON CONFLICT (bucket) DO UPDATE SET micro_jpy = micro_jpy + ?`,
        bucket,
        microJpy,
        microJpy,
      );
    }
  }

  /// 取った席を返す。APIが落ちたときに使う。
  ///
  /// こちらの都合で失敗したぶんまで利用者の回数を削るのは筋が通らない。
  refund(deviceId: string, ipHash: string, nowMs: number): void {
    const now = new Date(nowMs);
    const day = jstDay(now);
    for (const key of [`d:${deviceId}:${day}`, `i:${ipHash}:${day}`, `b:${ipHash}:${jstMinute(now)}`]) {
      this.sql.exec('UPDATE counters SET n = n - 1 WHERE key = ? AND n > 0', key);
    }
  }

  /// いま何円使ったか。運用者が見るためのもの。
  status(limits: Limits, nowMs: number): Status {
    const now = new Date(nowMs);
    return {
      day: jstDay(now),
      month: jstMonth(now),
      spentTodayMicroJpy: this.spent(jstDay(now)),
      spentMonthMicroJpy: this.spent(jstMonth(now)),
      dailyBudgetMicroJpy: limits.dailyBudgetMicroJpy,
      monthlyBudgetMicroJpy: limits.monthlyBudgetMicroJpy,
    };
  }

  private count(key: string): number {
    const row = this.sql.exec('SELECT n FROM counters WHERE key = ?', key).toArray()[0];
    return row ? Number(row.n) : 0;
  }

  private spent(bucket: string): number {
    const row = this.sql
      .exec('SELECT micro_jpy FROM spend WHERE bucket = ?', bucket)
      .toArray()[0];
    return row ? Number(row.micro_jpy) : 0;
  }
}

export type DenyReason =
  | 'device_daily'
  | 'ip_daily'
  | 'ip_burst'
  | 'daily_budget'
  | 'monthly_budget';

export type Verdict =
  | { ok: true; remainingToday: number }
  | { ok: false; reason: DenyReason; retryAfterSec: number };

export interface Status {
  day: string;
  month: string;
  spentTodayMicroJpy: number;
  spentMonthMicroJpy: number;
  dailyBudgetMicroJpy: number;
  monthlyBudgetMicroJpy: number;
}

const DAY_MS = 24 * 60 * 60 * 1000;
const JST_OFFSET_MS = 9 * 60 * 60 * 1000;

function endOfJstDayMs(now: Date): number {
  const shifted = now.getTime() + JST_OFFSET_MS;
  return shifted - (shifted % DAY_MS) + DAY_MS - JST_OFFSET_MS;
}

function secondsToNextJstDay(now: Date): number {
  return Math.max(1, Math.ceil((endOfJstDayMs(now) - now.getTime()) / 1000));
}
