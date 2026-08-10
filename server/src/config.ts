/// 中継サーバーの設定。
///
/// 数値はすべて環境変数から読む。上限を締めたいときに、コードを触らず
/// `wrangler.jsonc` の `vars` を変えてデプロイし直せるようにしている。

export interface Env {
  GUARD: DurableObjectNamespace<import('./guard').Guard>;
  /// Workers AI。同じ Cloudflare の上で動くので、外への通信は発生しない。
  AI: import('./model').Runner;

  // Secrets（`wrangler secret put` で入れる。リポジトリには置かない）
  /// アプリに埋め込む合言葉。抜き出せてしまうので防御の本命ではない。
  /// URLを見つけただけの相手を弾くための一段目。
  APP_TOKEN: string;
  /// IPをそのまま保存しないためのハッシュの種。
  IP_SALT: string;
  /// 使用額を見るときの合言葉。
  ADMIN_TOKEN: string;

  // Vars
  MODEL: string;
  MAX_OUTPUT_TOKENS: string;
  MAX_QUESTION_CHARS: string;
  MAX_CANDIDATES: string;
  MAX_CANDIDATE_CHARS: string;
  DEVICE_DAILY_LIMIT: string;
  IP_DAILY_LIMIT: string;
  IP_BURST_LIMIT: string;
  DAILY_BUDGET_JPY: string;
  MONTHLY_BUDGET_JPY: string;
  USD_JPY: string;
  USD_PER_1K_NEURONS: string;
}

export interface Limits {
  maxOutputTokens: number;
  maxQuestionChars: number;
  maxCandidates: number;
  maxCandidateChars: number;
  deviceDailyLimit: number;
  ipDailyLimit: number;
  ipBurstLimit: number;
  dailyBudgetMicroJpy: number;
  monthlyBudgetMicroJpy: number;
}

export interface Price {
  usdJpy: number;
  usdPer1kNeurons: number;
}

function num(raw: string | undefined, fallback: number): number {
  const value = Number(raw);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

/// 1円 = 1,000,000 マイクロ円。
///
/// 1問あたりの費用は0.1円ほどで、円のままだと整数で持てない。
/// かといって小数で積むと誤差が溜まるので、整数のまま扱える単位に落とす。
export const MICRO = 1_000_000;

export function limitsOf(env: Env): Limits {
  return {
    maxOutputTokens: num(env.MAX_OUTPUT_TOKENS, 2048),
    maxQuestionChars: num(env.MAX_QUESTION_CHARS, 100),
    maxCandidates: num(env.MAX_CANDIDATES, 30),
    maxCandidateChars: num(env.MAX_CANDIDATE_CHARS, 40),
    deviceDailyLimit: num(env.DEVICE_DAILY_LIMIT, 20),
    ipDailyLimit: num(env.IP_DAILY_LIMIT, 60),
    ipBurstLimit: num(env.IP_BURST_LIMIT, 5),
    dailyBudgetMicroJpy: num(env.DAILY_BUDGET_JPY, 300) * MICRO,
    monthlyBudgetMicroJpy: num(env.MONTHLY_BUDGET_JPY, 3000) * MICRO,
  };
}

export function priceOf(env: Env): Price {
  return {
    usdJpy: num(env.USD_JPY, 160),
    usdPer1kNeurons: num(env.USD_PER_1K_NEURONS, 0.011),
  };
}

/// 1回の問い合わせにかかった額。
///
/// 見積もりではなく、Workers AI が応答に返す実際の neuron 数から出す。
/// 見積もりで積むと、思考が長引いたときに上限をすり抜ける。
/// neuron は Cloudflare が課金に使う単位そのものなので、請求と食い違わない。
export function microJpyOfNeurons(neurons: number, price: Price): number {
  const usd = (neurons / 1000) * price.usdPer1kNeurons;
  return Math.round(usd * price.usdJpy * MICRO);
}
