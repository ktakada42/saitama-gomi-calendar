/// モデルへの問い合わせ。Cloudflare Workers AI を使う。
///
/// 50件の検証（`scripts/ai_eval/`）で9モデルを比べて選んだ。GPT-OSS 20B は
/// Sonnet 5 と同じ成績（44/50、「該当なし」12/12）で、費用が11分の1になる。
/// 同じ Cloudflare の上で動くので、外への通信も、預ける相手も増えない。
///
/// プロンプトは #41 の検証で使ったものと同じ。測った精度をそのまま
/// 引き継ぐため、文言は理由なく変えない。変えるときは検証を回し直すこと。

import { microJpyOfNeurons, type Price } from './config';

const PROMPT = `あなたは、さいたま市のごみ分別を調べる手伝いをします。

利用者が入力した言葉が、市の分別早見表のどの品目にあたるかを1つだけ選んでください。

守ること:
- 候補の中から選ぶこと。候補に無いものを答えてはいけません
- 少しでも自信が持てない場合、また利用者の入力が品目名でない場合は「該当なし」を選ぶこと
- 分別の区分（もえるごみ等）は答えないこと。品目を選ぶだけです

利用者の入力:
{query}

候補:
{candidates}

次のJSONだけを出力してください。説明は書かないでください。
{"item": "選んだ品目名、または該当なしなら null"}`;

export function buildPrompt(question: string, candidates: string[]): string {
  const listing = candidates.map((name) => `- ${name}`).join('\n');
  return PROMPT.replace('{query}', question).replace(
    '{candidates}',
    listing || '(候補なし)',
  );
}

export interface Answer {
  /// 候補の何番目か。該当なしなら null。
  index: number | null;
  /// かかった額。Workers AI は応答に実際の neuron 数を返すので、
  /// 見積もりではなく実測になる。
  microJpy: number;
}

export interface Runner {
  run(model: string, inputs: unknown): Promise<unknown>;
}

export async function askModel(
  question: string,
  candidates: string[],
  opts: { ai: Runner; model: string; maxTokens: number; price: Price },
): Promise<Answer> {
  let raw: unknown;
  try {
    raw = await opts.ai.run(opts.model, {
      messages: [{ role: 'user', content: buildPrompt(question, candidates) }],
      max_tokens: opts.maxTokens,
    });
  } catch (error) {
    // 中身には利用者の入力が混ざりうるので、そのままは持ち出さない。
    throw new UpstreamError(error instanceof Error ? error.name : 'unknown');
  }

  const result = (raw ?? {}) as ModelResult;
  return {
    index: pickIndex(textOf(result), candidates),
    microJpy: microJpyOfNeurons(result.usage?.neurons ?? 0, opts.price),
  };
}

export class UpstreamError extends Error {
  constructor(readonly kind: string) {
    super(`upstream ${kind}`);
  }
}

interface ModelResult {
  response?: string | null;
  choices?: Array<{ message?: { content?: string | null } }>;
  usage?: { neurons?: number };
}

/// 応答の形はモデルによって違う。
///
/// OpenAI互換の `choices` に入るものと、`response` に文字列で入るものがあり、
/// 両方を持っていて片方が空、ということもある。順に見て最初に中身が
/// あったものを採る。
export function textOf(result: ModelResult): string {
  for (const choice of result.choices ?? []) {
    const content = choice.message?.content;
    if (typeof content === 'string' && content.trim()) return content.trim();
  }
  return typeof result.response === 'string' ? result.response.trim() : '';
}

/// 答えを候補の番号に直す。
///
/// 候補に無い名前が返ってきたら「該当なし」として捨てる。こうしておくと、
/// アプリが表示する区分は必ず市の資料に由来する。作り話の区分が画面に
/// 出る道が構造として存在しない。
export function pickIndex(text: string, candidates: string[]): number | null {
  if (!text) return null;

  // 思考するモデルは、答えの前に考えを書くことがある。最後のJSONらしき
  // 塊から見ていく。前から採ると、考えの途中の例を拾ってしまう。
  const blocks = text.match(/\{[^{}]*\}/g) ?? [];
  for (const block of blocks.reverse()) {
    let parsed: unknown;
    try {
      parsed = JSON.parse(block);
    } catch {
      continue;
    }
    if (typeof parsed !== 'object' || parsed === null || !('item' in parsed)) {
      continue;
    }
    const item = (parsed as { item: unknown }).item;
    if (typeof item !== 'string') return null;
    const index = candidates.indexOf(item);
    return index >= 0 ? index : null;
  }
  return null;
}
