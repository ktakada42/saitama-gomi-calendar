/// Claude API への問い合わせ。
///
/// プロンプトは #41 の検証（`scripts/ai_eval/run_eval.py`）で使ったものと
/// 同じにしてある。測った精度をそのまま引き継ぐため、文言は理由なく変えない。
/// 変えるときは検証を回し直すこと。

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
  inputTokens: number;
  outputTokens: number;
}

export async function askClaude(
  question: string,
  candidates: string[],
  opts: { apiKey: string; model: string; fetcher?: typeof fetch },
): Promise<Answer> {
  const doFetch = opts.fetcher ?? fetch;
  const response = await doFetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': opts.apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: opts.model,
      // 出力はJSONが1行だけ。長い応答を返す余地を与えない。
      // これも安全弁のひとつで、1回あたりの費用に天井を作る。
      max_tokens: 64,
      messages: [{ role: 'user', content: buildPrompt(question, candidates) }],
    }),
  });

  if (!response.ok) {
    // 本文には利用者の入力が混ざりうるので、状態番号だけを持ち出す。
    throw new UpstreamError(response.status);
  }

  const body = (await response.json()) as {
    content?: Array<{ type: string; text?: string }>;
    usage?: { input_tokens?: number; output_tokens?: number };
  };
  const text = (body.content ?? [])
    .filter((block) => block.type === 'text')
    .map((block) => block.text ?? '')
    .join('');

  return {
    index: pickIndex(text, candidates),
    inputTokens: body.usage?.input_tokens ?? 0,
    outputTokens: body.usage?.output_tokens ?? 0,
  };
}

export class UpstreamError extends Error {
  constructor(readonly status: number) {
    super(`upstream ${status}`);
  }
}

/// 答えを候補の番号に直す。
///
/// 候補に無い名前が返ってきたら「該当なし」として捨てる。こうしておくと、
/// アプリが表示する区分は必ず市の資料に由来する。作り話の区分が画面に
/// 出る道が構造として存在しない。
export function pickIndex(text: string, candidates: string[]): number | null {
  const match = text.match(/\{[\s\S]*\}/);
  if (!match) return null;

  let parsed: unknown;
  try {
    parsed = JSON.parse(match[0]);
  } catch {
    return null;
  }
  const item = (parsed as { item?: unknown })?.item;
  if (typeof item !== 'string') return null;

  const index = candidates.indexOf(item);
  return index >= 0 ? index : null;
}
