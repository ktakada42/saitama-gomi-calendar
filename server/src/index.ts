import { limitsOf, priceOf, MICRO, type Env } from './config';
import { askModel, UpstreamError } from './model';
import { Guard, type DenyReason, type Verdict } from './guard';
import { hashIp, parseSortRequest } from './request';

export { Guard };

/// 利用者の入力は、記録に残さない。
///
/// プライバシーポリシーに「質問文は保存しません」と書く以上、
/// 実装でも守る。このファイルで質問文や候補を console に渡してはいけない。
/// 失敗を書き残すときも、種類と件数だけにする。

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await route(request, env);
    } catch (error) {
      // ここから先へ例外を出さない。素通ししてしまうと Cloudflare の
      // エラー画面（1101）が返り、アプリはJSONを期待しているので
      // 「サーバーが壊れた」ではなく「応答が読めない」として出る。
      console.error(`unhandled: ${nameOf(error)}`);
      return json({ error: 'internal' }, 500);
    }
  },
} satisfies ExportedHandler<Env>;

function route(request: Request, env: Env): Promise<Response> | Response {
  const url = new URL(request.url);

  if (url.pathname === '/v1/sort' && request.method === 'POST') {
    return handleSort(request, env);
  }
  if (url.pathname === '/v1/status' && request.method === 'GET') {
    return handleStatus(request, env);
  }
  if (url.pathname === '/healthz') {
    return json({ ok: true });
  }
  return json({ error: 'not_found' }, 404);
}

/// 中身に利用者の入力が混ざりうるので、種類だけを持ち出す。
function nameOf(error: unknown): string {
  return error instanceof Error ? error.name : 'unknown';
}

async function handleSort(request: Request, env: Env): Promise<Response> {
  if (request.headers.get('x-app-token') !== env.APP_TOKEN) {
    return json({ error: 'unauthorized' }, 401);
  }

  const limits = limitsOf(env);
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad_request', field: 'body' }, 400);
  }
  const parsed = parseSortRequest(body, limits);
  if (!parsed.ok) {
    return json({ error: 'bad_request', ...parsed.error }, 400);
  }
  const { deviceId, question, candidates } = parsed.value;

  const ipHash = await hashIp(
    request.headers.get('cf-connecting-ip') ?? 'unknown',
    env.IP_SALT,
  );
  const guard = env.GUARD.get(env.GUARD.idFromName('global'));
  const now = Date.now();

  // 安全弁に訊けなかったら、断る。
  //
  // 訊けないまま先へ進むと、上限を数えないままモデルを呼ぶことになる。
  // 止めるための仕組みが、止まっているときにいちばん緩むのでは意味がない。
  // 使えない間サービスが止まるのは承知のうえで、閉じる側に倒す。
  // Durable Object は配信のたびに入れ替わるので、ここは実際に通る。
  let verdict: Verdict;
  try {
    verdict = await guard.reserve(deviceId, ipHash, limits, now);
  } catch (error) {
    console.error(`guard unavailable: ${nameOf(error)}`);
    return json({ error: 'guard_unavailable' }, 503, { 'retry-after': '5' });
  }

  if (!verdict.ok) {
    return json(
      { error: errorNameOf(verdict.reason), retryAfterSec: verdict.retryAfterSec },
      statusOf(verdict.reason),
      { 'retry-after': String(verdict.retryAfterSec) },
    );
  }

  try {
    const answer = await askModel(question, candidates, {
      ai: env.AI,
      model: env.MODEL,
      maxTokens: limits.maxOutputTokens,
      price: priceOf(env),
    });
    // 記録に失敗しても答えは返す。もう払ったぶんなので、捨てると
    // 費用だけかかって利用者にも何も渡らない。
    //
    // 積み損ねると上限の集計は甘くなるが、暴走はしない。安全弁が
    // 答えられない状態なら、次の問い合わせは reserve の段で断られる。
    try {
      await guard.settle(answer.microJpy, now);
    } catch (error) {
      console.error(`settle failed: ${nameOf(error)}`);
    }
    return json({ index: answer.index, remainingToday: verdict.remainingToday });
  } catch (error) {
    console.error(
      `model failed: ${error instanceof UpstreamError ? error.kind : nameOf(error)}`,
    );
    // 落ちたのはこちらの都合なので、取った席は返す。
    // 返すのに失敗しても、利用者に返すのは元の失敗のほうにする。
    // 席が1つ戻らないより、応答が壊れるほうが困る。
    try {
      await guard.refund(deviceId, ipHash, now);
    } catch (refundError) {
      console.error(`refund failed: ${nameOf(refundError)}`);
    }
    return json({ error: 'upstream_unavailable' }, 503);
  }
}

async function handleStatus(request: Request, env: Env): Promise<Response> {
  if (request.headers.get('x-admin-token') !== env.ADMIN_TOKEN) {
    return json({ error: 'unauthorized' }, 401);
  }
  const guard = env.GUARD.get(env.GUARD.idFromName('global'));
  const status = await guard.status(limitsOf(env), Date.now());
  return json({
    day: status.day,
    month: status.month,
    spentTodayJpy: status.spentTodayMicroJpy / MICRO,
    spentMonthJpy: status.spentMonthMicroJpy / MICRO,
    dailyBudgetJpy: status.dailyBudgetMicroJpy / MICRO,
    monthlyBudgetJpy: status.monthlyBudgetMicroJpy / MICRO,
  });
}

/// 断った理由を、アプリが出す文言に対応づけられる名前にする。
///
/// 「今日はここまで」と「今月の上限に達した」ではアプリの言うことが
/// 変わるので、まとめずに分けて返す。
function errorNameOf(reason: DenyReason): string {
  switch (reason) {
    case 'device_daily':
      return 'device_quota_exhausted';
    case 'ip_daily':
    case 'ip_burst':
      return 'rate_limited';
    case 'daily_budget':
    case 'monthly_budget':
      return 'budget_exceeded';
  }
}

function statusOf(reason: DenyReason): number {
  // 予算切れはサーバー側の都合なので 503。回数切れは相手の都合で 429。
  return reason === 'daily_budget' || reason === 'monthly_budget' ? 503 : 429;
}

function json(body: unknown, status = 200, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...headers },
  });
}
