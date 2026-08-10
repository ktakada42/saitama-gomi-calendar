/// Workers AI のモデルを手元の検証スクリプトから叩くための足場。
///
/// Workers AI はバインディング経由でしか呼べないので、間にこれを置く。
/// デプロイはしない。`wrangler dev` で動かして使う。

interface Env {
  AI: Ai;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const { model, prompt, maxTokens } = (await request.json()) as {
      model: string;
      prompt: string;
      maxTokens?: number;
    };
    try {
      const result = await env.AI.run(
        model as Parameters<Ai['run']>[0],
        {
          messages: [{ role: 'user', content: prompt }],
          max_tokens: maxTokens ?? 64,
        } as never,
      );
      return Response.json({ ok: true, result });
    } catch (error) {
      return Response.json({ ok: false, error: String(error) });
    }
  },
};
