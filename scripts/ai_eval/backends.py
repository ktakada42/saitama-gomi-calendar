"""検証にかけるモデルと、その呼び出し方・料金。

精度と費用は別々の方法で出す。

- 精度: 実際に問い合わせて答え合わせする
- 費用: Claude は CLI 経由でしか叩けず、CLIが自前のシステムプロンプト
  （2万トークン規模）を積むため、CLIの申告額は当てにならない。
  こちらのプロンプトのトークン数と各社の公表価格から出す。
  Workers AI だけは応答に実際の neuron 数が入るので、それを使う。
"""
import json
import re
import subprocess
import urllib.error
import urllib.request

# 1ドル何円で見るか。wrangler.jsonc の USD_JPY と合わせる。
USD_JPY = 160

# Workers AI の単価。https://developers.cloudflare.com/workers-ai/platform/pricing/
USD_PER_NEURON = 0.011 / 1000

PROBE_URL = "http://127.0.0.1:8787"

# Workers AI には1日10,000 neuron の無料枠がある。ここに収まる限り
# 費用は0円なので、月額を出すときは差し引く。
FREE_NEURONS_PER_DAY = 10_000


class Backend:
    """モデル1つぶんの呼び出し方。"""

    max_jobs = 8
    #: 1日いくらまで無料か（円）。無料枠が無いものは0。
    free_jpy_per_day = 0.0

    def __init__(self, name: str, label: str, note: str = ""):
        self.name = name
        self.label = label
        self.note = note

    @property
    def slug(self) -> str:
        return re.sub(r"[^a-z0-9]+", "-", self.label.lower()).strip("-")

    def ask(self, prompt: str) -> dict:
        """{text, input_tokens, output_tokens, usd} を返す。失敗したら text=None。"""
        raise NotImplementedError


class ClaudeCli(Backend):
    """claude CLI 経由。APIキーを持っていないのでこの道しかない。

    費用はここでは測れない（CLIが自前のシステムプロンプトを積むため）。
    トークン数を数えて、公表価格から別に出す。
    """

    # claude CLI は同時に起こすと応答が空で返ってくる。#41 は逐次で回して
    # いた。ここを並列にすると、モデルの成績ではなく呼び出し方の失敗を
    # 測ることになる。
    max_jobs = 1

    def __init__(self, name, label, in_usd_per_mtok, out_usd_per_mtok, note=""):
        super().__init__(name, label, note)
        self.in_usd = in_usd_per_mtok
        self.out_usd = out_usd_per_mtok

    def ask(self, prompt: str) -> dict:
        try:
            result = subprocess.run(
                ["claude", "-p", "--model", self.name],
                input=prompt,
                capture_output=True,
                text=True,
                timeout=180,
            )
        except subprocess.TimeoutExpired:
            return {"text": None, "error": "timeout"}
        return {"text": result.stdout.strip()}

    def usd_of(self, input_tokens: int, output_tokens: int) -> float:
        return (input_tokens * self.in_usd + output_tokens * self.out_usd) / 1e6


class WorkersAi(Backend):
    """Workers AI。`scripts/ai_eval/probe` を `wrangler dev` で立てておく。

    応答に実際の neuron 数が入るので、費用は見積もりでなく実測になる。
    """

    free_jpy_per_day = FREE_NEURONS_PER_DAY * USD_PER_NEURON * USD_JPY

    def __init__(self, name, label, max_tokens=768, note=""):
        super().__init__(name, label, note)
        self.max_tokens = max_tokens

    def ask(self, prompt: str) -> dict:
        payload = json.dumps(
            {"model": self.name, "prompt": prompt, "maxTokens": self.max_tokens}
        ).encode()
        request = urllib.request.Request(
            PROBE_URL, data=payload, headers={"content-type": "application/json"}
        )
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                body = json.loads(response.read())
        except (urllib.error.URLError, TimeoutError) as error:
            return {"text": None, "error": str(error)}

        if not body.get("ok"):
            return {"text": None, "error": body.get("error", "unknown")}

        result = body["result"]
        usage = result.get("usage", {})
        return {
            "text": _text_of(result),
            "input_tokens": usage.get("prompt_tokens", 0),
            "output_tokens": usage.get("completion_tokens", 0),
            # 思考トークンで打ち切られたか。安いはずのモデルが
            # 思考で出力枠を使い切ると、費用も精度も崩れる。
            "truncated": _finish_reason(result) == "length",
            "usd": usage.get("neurons", 0) * USD_PER_NEURON,
        }


def _text_of(result: dict) -> str:
    """応答の形はモデルによって違う。

    OpenAI互換の `choices` を持つものと、`response` にそのまま入るものがある。
    両方を持っていて片方が空、ということもあるので、順に見て最初に
    中身があったものを採る。
    """
    for choice in result.get("choices", []):
        content = choice.get("message", {}).get("content")
        if isinstance(content, str) and content.strip():
            return content.strip()
    response = result.get("response")
    if isinstance(response, str):
        return response.strip()
    return ""


def _finish_reason(result: dict) -> str:
    for choice in result.get("choices", []):
        if choice.get("finish_reason"):
            return choice["finish_reason"]
    return ""


# 比べる相手。
#
# Claude は #41 で測った Sonnet 5 と、いま wrangler.jsonc に書いてある
# Haiku 4.5。Workers AI は中継サーバーと同じ Cloudflare 上で動くので、
# 通信の往復も課金先も増えないのが利点。
BACKENDS = {
    b.label: b
    for b in [
        ClaudeCli("claude-sonnet-5", "Sonnet 5", 3, 15, note="#41で測ったもの"),
        ClaudeCli(
            "claude-haiku-4-5-20251001", "Haiku 4.5", 1, 5, note="いまの設定値"
        ),
        WorkersAi("@cf/meta/llama-3.1-8b-instruct-fp8", "Llama 3.1 8B"),
        WorkersAi("@cf/meta/llama-3.2-3b-instruct", "Llama 3.2 3B"),
        WorkersAi("@cf/qwen/qwen3-30b-a3b-fp8", "Qwen3 30B", max_tokens=2048,
                  note="思考する。出力枠を大きく取る"),
        WorkersAi("@cf/google/gemma-4-26b-a4b-it", "Gemma 4 26B", max_tokens=2048,
                  note="思考する。出力枠を大きく取る"),
        WorkersAi("@cf/openai/gpt-oss-20b", "GPT-OSS 20B", max_tokens=2048),
        WorkersAi("@cf/meta/llama-3.3-70b-instruct-fp8-fast", "Llama 3.3 70B"),
        WorkersAi("@cf/mistralai/mistral-small-3.1-24b-instruct", "Mistral Small 24B"),
    ]
}
