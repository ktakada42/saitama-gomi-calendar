import type { Limits } from './config';

export interface SortRequest {
  deviceId: string;
  question: string;
  candidates: string[];
}

export type Rejection = { field: string; reason: string };

/// 受け取った中身を検める。
///
/// 長さの上限は、行儀の悪いリクエストで費用を焼かれないための安全弁でもある。
/// 質問文と候補はそのままプロンプトに入るので、ここが唯一の歯止めになる。
export function parseSortRequest(
  body: unknown,
  limits: Limits,
): { ok: true; value: SortRequest } | { ok: false; error: Rejection } {
  if (typeof body !== 'object' || body === null) {
    return fail('body', 'JSONのオブジェクトではありません');
  }
  const { deviceId, question, candidates } = body as Record<string, unknown>;

  // 端末IDは端末が作った乱数（UUID）。形を縛るのは、好きな文字列を
  // 名乗られて数え上げの置き場を無限に増やされないため。
  if (typeof deviceId !== 'string' || !UUID.test(deviceId)) {
    return fail('deviceId', 'UUIDの形ではありません');
  }
  if (typeof question !== 'string') {
    return fail('question', '文字列ではありません');
  }
  const trimmed = question.trim();
  if (trimmed.length === 0) {
    return fail('question', '空です');
  }
  if ([...trimmed].length > limits.maxQuestionChars) {
    return fail('question', `${limits.maxQuestionChars}文字を超えています`);
  }
  if (!Array.isArray(candidates) || candidates.length === 0) {
    return fail('candidates', '空です');
  }
  if (candidates.length > limits.maxCandidates) {
    return fail('candidates', `${limits.maxCandidates}件を超えています`);
  }
  for (const name of candidates) {
    if (typeof name !== 'string' || name.length === 0) {
      return fail('candidates', '文字列でない要素があります');
    }
    if ([...name].length > limits.maxCandidateChars) {
      return fail('candidates', `${limits.maxCandidateChars}文字を超える要素があります`);
    }
  }

  return {
    ok: true,
    value: { deviceId, question: trimmed, candidates: candidates as string[] },
  };
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function fail(field: string, reason: string): { ok: false; error: Rejection } {
  return { ok: false, error: { field, reason } };
}

/// IPは生のまま持たない。同じ相手だと分かれば足りる。
///
/// 種は秘密にしてあるので、保存された値から元のIPは復元できない。
export async function hashIp(ip: string, salt: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(`${salt}:${ip}`),
  );
  return [...new Uint8Array(digest)]
    .slice(0, 8)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}
