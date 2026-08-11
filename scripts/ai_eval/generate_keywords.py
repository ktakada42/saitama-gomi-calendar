#!/usr/bin/env python3
"""品目ごとに、利用者が打ちそうな言い換えをAIに作らせる（issue #44）。

実行時にAIへ問い合わせる代わりに、ビルド時に1回だけ生成して同梱する。
通信ゼロ・費用ゼロで、しかも出す前に全部を目視で確認できる
（実行時のAIだと、危ない答えが出てから気づく）。

「椅子」で「いす」が出なかった、という実例がきっかけ。かな書きの品目に
対して、利用者は漢字で打つことが多い。AIに列挙させたほうが、手で
埋めるより網羅的だと分かった実測（scripts/ai_eval/ の別実験）を踏まえる。

  python3 scripts/ai_eval/generate_keywords.py --limit 20   # 少量で試す
  python3 scripts/ai_eval/generate_keywords.py              # 全件
"""
import argparse
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
OUT = Path(__file__).resolve().parent / "generated_keywords.json"
OUT_BRANDS = Path(__file__).resolve().parent / "generated_brands.json"

BATCH_SIZE = 15

# Workers AI を使うときの足場（scripts/ai_eval/probe を wrangler dev で起動）。
# claude CLI にはセッションの使用量上限があり、途中で止まる。同じ生成を
# 別の口からも流せるようにしておく。
PROBE_URL = "http://127.0.0.1:8790"

BRAND_PROMPT = """さいたま市のごみ分別アプリの検索を改善します。

以下の品目について、利用者が検索欄に打ちそうな**商品名・ブランド名・俗称**を
挙げてください。一般名詞ではなく、固有名詞だけを求めています。

例:
- 加熱式電子たばこ → アイコス、iQOS、プルーム、Ploom、グロー、glo
- 掃除機 → ルンバ、ダイソン
- ラップ類 → サランラップ、クレラップ

守ること:
- **カタカナと英字の両方**を挙げること（「アイコス」と「iQOS」は別々に打たれる）
- その品目そのものを指す固有名詞だけ。似た別品目の商品名は挙げない
- 固有名詞が思いつかない品目は、結果に含めないこと。一般名詞で埋めない
- 商品名が存在しない品目のほうが多い。無理に出さないこと

品目:
{items}

次のJSON配列だけを出力してください。説明は書かないでください。
[
  {{"name": "品目名", "words": ["商品名1", "商品名2"]}}
]"""

PROMPT = """さいたま市のごみ分別アプリの検索を改善します。

以下は市の資料に載っている品目名です。それぞれについて、利用者が
検索欄に打ちそうな「別の言い方」を3〜6個挙げてください。

観点:
- 漢字表記（市はかなで書くことが多い。例：「いす」→「椅子」）
- カタカナ／ひらがなの揺れ
- 口語・略語・俗称
- 材質や状態を添えた言い方（例：「かばん」→「革のかばん」ではなく、
  逆に材質が省略された言い方があれば）

守ること:
- その品目**そのもの**を指す言葉だけを挙げること。似ているが別の品目は
  挙げない（例：「座いす」の言い換えに「車いす」を含めない）
- 区分（もえるごみ等）や出し方には触れない。言葉だけを挙げる
- 分からなければ、その品目は結果に含めなくてよい（無理に埋めない）

品目:
{items}

次のJSON配列だけを出力してください。説明は書かないでください。
[
  {{"name": "品目名", "words": ["言い換え1", "言い換え2"]}}
]"""


def load_all_items() -> list[dict]:
    all_items = []
    for name in ("dictionary.json", "dictionary_extra.json"):
        data = json.loads((ROOT / "assets/data" / name).read_text(encoding="utf-8"))
        all_items.extend(data["items"])
    return all_items


def load_items(all_items: list[dict]) -> list[dict]:
    existing = set(
        json.loads(
            (ROOT / "assets/data/dictionary_keywords.json").read_text(encoding="utf-8")
        )["keywords"]
    )
    # 生成済みのぶんも外す。取りこぼしだけを流し直せるようにするため。
    # 全部を毎回投げ直すと、使用量の上限にすぐ当たる。
    for path in (OUT, OUT_BRANDS):
        if path.exists():
            existing |= set(json.loads(path.read_text(encoding="utf-8")))
    # #103 で目視確認済みのものは二重生成しない。
    return [i for i in all_items if i["name"] not in existing]


def _normalize(text: str) -> str:
    text = re.sub(r"[（）()【】\[\]・、。／/･]", "", text)
    return re.sub(r"[〜~ー－―\-\s]", "", text).lower()


def filter_dangerous(results: dict, items: list[dict]) -> tuple[dict, list[str]]:
    """危険な言い換えを機械的に落とす。

    実測したところ、AIは「植木鉢」の言い換えに実在の別品目「プランター」を
    挙げるようなことをする（区分が違う: もえるごみ vs もえないごみ）。
    言い換え語が既存の品目名と完全一致するなら、その語で検索すればもう
    本物の品目がヒットする。言い換えとして残す理由がなく、むしろ
    紛れの元になるので落とす。
    """
    all_norm_names = {_normalize(i["name"]) for i in items}

    cleaned: dict[str, list[str]] = {}
    dropped: list[str] = []
    for name, words in results.items():
        kept = []
        for w in words:
            if _normalize(w) in all_norm_names:
                dropped.append(f"{name} の「{w}」← 実在の別品目名と一致")
                continue
            kept.append(w)
        if kept:
            cleaned[name] = kept
    return cleaned, dropped


class UsageLimitReached(Exception):
    """claude CLI の使用量上限。これ以降は回しても無駄なので止める。"""


def ask_workers_ai(prompt: str) -> str:
    body = json.dumps(
        {"model": "@cf/openai/gpt-oss-20b", "prompt": prompt, "maxTokens": 4096}
    ).encode()
    request = urllib.request.Request(
        PROBE_URL, data=body, headers={"content-type": "application/json"}
    )
    try:
        with urllib.request.urlopen(request, timeout=240) as response:
            payload = json.load(response)
    except (urllib.error.URLError, TimeoutError) as error:
        print(f"  probeに繋がらない: {error}", file=sys.stderr)
        return ""
    if not payload.get("ok"):
        print(f"  失敗: {str(payload.get('error'))[:120]}", file=sys.stderr)
        return ""

    result = payload["result"]
    for choice in result.get("choices", []):
        content = choice.get("message", {}).get("content")
        if content:
            return content
    response_text = result.get("response")
    return response_text if isinstance(response_text, str) else ""


def ask(batch: list[dict], brands: bool = False, workers_ai: bool = False) -> list[dict]:
    listing = "\n".join(f"- {i['name']}" for i in batch)
    template = BRAND_PROMPT if brands else PROMPT

    if workers_ai:
        text = ask_workers_ai(template.format(items=listing))
        match = re.search(r"\[.*\]", text, re.S)
        if not match:
            return []
        try:
            return json.loads(match.group(0))
        except json.JSONDecodeError:
            return []

    try:
        result = subprocess.run(
            ["claude", "-p", "--model", "claude-haiku-4-5-20251001"],
            input=template.format(items=listing),
            capture_output=True,
            text=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        # 1バッチ落ちても、残りは回す。全体を止めるほどのことではない。
        print("  応答なし（180秒）。このバッチは飛ばす", file=sys.stderr)
        return []
    # 使用量の上限に当たったら、以降を回しても全部失敗する。
    # 呼び出し側に伝えて止める。
    if "session limit" in result.stdout or "usage limit" in result.stdout:
        raise UsageLimitReached(result.stdout.strip()[:120])

    match = re.search(r"\[.*\]", result.stdout, re.S)
    if not match:
        print(f"  読み取れず: {result.stdout[:200]}", file=sys.stderr)
        return []
    try:
        return json.loads(match.group(0))
    except json.JSONDecodeError:
        print(f"  JSON崩れ: {match.group(0)[:200]}", file=sys.stderr)
        return []


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int)
    parser.add_argument(
        "--batch-size",
        type=int,
        default=BATCH_SIZE,
        help="1回に投げる品目数。まとめて投げると取りこぼす品目があるので、"
        "残りを埋めるときは小さくする",
    )
    parser.add_argument(
        "--workers-ai",
        action="store_true",
        help="claude CLI ではなく Workers AI で生成する。CLIの使用量上限に"
        "当たったときの逃げ道（先に scripts/ai_eval/probe を起動しておく）",
    )
    parser.add_argument(
        "--brands",
        action="store_true",
        help="商品名・ブランド名だけを集める。英字の綴りは一般語の生成では"
        "出てこないので、別のパスにしてある（iQOS・Ploom・ルンバなど）",
    )
    args = parser.parse_args()

    all_items = load_all_items()
    # ブランド名は、既に言い換えを持つ品目にも足したい（別の観点なので）。
    items = all_items if args.brands else load_items(all_items)
    if args.limit:
        items = items[: args.limit]
    valid_names = {i["name"] for i in items}

    size = args.batch_size
    batches = [items[i : i + size] for i in range(0, len(items), size)]
    print(f"{len(items)}品目を{len(batches)}バッチで生成します", flush=True)

    results: dict[str, list[str]] = {}
    for n, batch in enumerate(batches, 1):
        try:
            out = ask(batch, brands=args.brands, workers_ai=args.workers_ai)
        except UsageLimitReached as limit:
            print(f"\n使用量の上限に達しました: {limit}", file=sys.stderr)
            print(f"{n - 1}/{len(batches)}バッチまでの結果を書き出します。", file=sys.stderr)
            break
        got = 0
        for entry in out:
            name = entry.get("name")
            words = entry.get("words")
            # 品目名を書き換えて返してくることがある。存在しない名前で
            # 書き出すと、誰にも当たらない言い換えになる。
            if name not in valid_names or not isinstance(words, list):
                continue
            results[name] = [w for w in words if isinstance(w, str) and w.strip()]
            got += 1
        print(f"  [{n}/{len(batches)}] {got}/{len(batch)}品目", flush=True)

    # 突き合わせは全品目に対して行う。生成対象から外れた65品目
    # （#103 で既に言い換えを持つもの）の名前とも衝突しうるため。
    # 1件も取れなかったら書かない。空で上書きすると、前回の結果が消える。
    if not results:
        print("1件も生成できませんでした。出力は書き換えません。", file=sys.stderr)
        return 1

    cleaned, dropped = filter_dangerous(results, all_items)
    out_path = OUT_BRANDS if args.brands else OUT
    # 前回の結果に足す。取りこぼしだけを流し直したときに、
    # 前回ぶんが消えてしまうため（実際に403品目を失った）。
    previous = (
        json.loads(out_path.read_text(encoding="utf-8"))
        if out_path.exists()
        else {}
    )
    previous.update(cleaned)
    out_path.write_text(
        json.dumps(previous, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    cleaned = previous
    if dropped:
        print(f"\n機械的に落とした言い換え（{len(dropped)}件）:")
        for d in dropped:
            print(f"  - {d}")
    print(f"\n{len(cleaned)}品目ぶんを {out_path} に書き出しました。")
    print("次は目視で確認してから assets/data/dictionary_keywords.json へ合流させる。")


if __name__ == "__main__":
    sys.exit(main())
