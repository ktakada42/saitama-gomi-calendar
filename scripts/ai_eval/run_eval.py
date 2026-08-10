#!/usr/bin/env python3
"""AI分別相談の精度と費用を、モデルごとに測る（issue #41, #42）。

案Bの設計を確かめる。AIの役割は「利用者の言い方を辞書の品目に対応づけること」
だけで、区分そのものは辞書の記載をそのまま出す。だから測るべきは
「対応づけが当たるか」と「辞書に無いものを無いと言えるか」の2点。

候補の絞り込みはモデルによらず同じにしてある。そうしないと、
比べているのがモデルの差なのか絞り込みの差なのか分からなくなる。

  # Claude（claude CLI 経由）
  python3 scripts/ai_eval/run_eval.py --model "Haiku 4.5"

  # Workers AI（先に probe を立てておく）
  cd scripts/ai_eval/probe && npm ci && npm run dev
  python3 scripts/ai_eval/run_eval.py --model "Qwen3 30B"

  # 出揃ったら比べる
  python3 scripts/ai_eval/compare_models.py
"""
import argparse
import json
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from backends import BACKENDS, USD_JPY

ROOT = Path(__file__).resolve().parent.parent.parent
DICT = ROOT / "assets/data/dictionary.json"
CASES = Path(__file__).resolve().parent / "cases.json"
RESULTS = Path(__file__).resolve().parent / "results"

# 端末内検索で何件まで候補を渡すか。
#
# 多く渡すほど正解が候補に入りやすいが、AIが選び間違える余地も増える。
# それ以上に、候補が多いと送信量が増えて中継サーバーの費用に効く。
CANDIDATE_LIMIT = 30


def normalize(text: str) -> str:
    """lib/domain/waste_item.dart の _normalize と同じ規則。"""
    text = re.sub(r"[（）()【】\[\]・、。／/･]", "", text)
    text = re.sub(r"[〜~ー－―\-\s]", "", text)
    return text.lower()


def load_items():
    data = json.loads(DICT.read_text(encoding="utf-8"))
    return data["items"]


KATAKANA_TO_HIRAGANA = str.maketrans(
    "".join(chr(c) for c in range(0x30A1, 0x30F7)),
    "".join(chr(c - 0x60) for c in range(0x30A1, 0x30F7)),
)


def kana_fold(text: str) -> str:
    """カタカナをひらがなに寄せる。「だんぼーる」と「段ボール」を近づけるため。"""
    return text.translate(KATAKANA_TO_HIRAGANA)


def candidates(query: str, items):
    """端末内でできる範囲の絞り込み。

    アプリの検索（部分一致）だけでは「プラスチックの弁当箱」のような
    言い換えに何も当たらない。実機でも同じことが起きるので、
    文字の重なりでも拾えるようにして候補を広めに出す。
    最終的にどれかを選ぶのはAIの仕事。

    候補に正解が入っていなければAIは絶対に当てられないので、
    ここの取りこぼしがそのまま上限になる。
    """
    q = normalize(query)
    qk = kana_fold(q)
    # 2文字の並びで見ると、1文字ずつより語の近さを拾える
    # （「けいたいでんわ」と「携帯電話」は1文字も共有しないが、
    #  かなに寄せると「けいたい」で重なる）。
    q_bigrams = {qk[i : i + 2] for i in range(len(qk) - 1)} or {qk}

    scored = []
    for item in items:
        name = normalize(item["name"])
        if not name:
            continue
        nk = kana_fold(name)
        if q and (q in name or name in q):
            score = 1000 + len(name)
        elif qk and (qk in nk or nk in qk):
            score = 500 + len(nk)
        else:
            n_bigrams = {nk[i : i + 2] for i in range(len(nk) - 1)} or {nk}
            shared2 = len(q_bigrams & n_bigrams)
            shared1 = len(set(qk) & set(nk))
            score = shared2 * 10 + shared1
        if score > 0:
            scored.append((score, item))
    scored.sort(key=lambda x: -x[0])
    return [item for _, item in scored[:CANDIDATE_LIMIT]]


PROMPT = """あなたは、さいたま市のごみ分別を調べる手伝いをします。

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
{{"item": "選んだ品目名、または該当なしなら null"}}"""




def parse_answer(text: str) -> str | None:
    """モデルの出力から選ばれた品目名を取り出す。

    小さいモデルほど、余計な前置きを付けたりJSONを崩したりする。
    そこで落とすと「JSONの書き方が下手」を「分別が分からない」として
    数えてしまうので、最後のJSONらしき塊まで拾いにいく。
    """
    if not text:
        return "__PARSE_ERROR__"
    blocks = re.findall(r"\{[^{}]*\}", text, re.S)
    for block in reversed(blocks):
        try:
            parsed = json.loads(block)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict) and "item" in parsed:
            item = parsed["item"]
            return item if isinstance(item, str) else None
    return "__PARSE_ERROR__"


def run_case(backend, case, items):
    cands = candidates(case["q"], items)
    listing = "\n".join(f"- {c['name']}" for c in cands)
    prompt = PROMPT.format(query=case["q"], candidates=listing or "(候補なし)")

    reply = backend.ask(prompt)
    text = reply.get("text") or ""
    answer = parse_answer(text)

    expected = case["expected"]
    # 判断が割れる問いは、どちらの答えも正解として扱う
    # （例：「ペットボトルのフタ」に本体を出すか、該当なしと言うか）。
    accepted = [expected, *case.get("accept_also", [])]

    # 費用。Workers AI は応答に実際のneuron数が入る。Claude は
    # CLI越しなので測れず、トークン数と公表価格から出す。
    input_tokens = reply.get("input_tokens", 0)
    output_tokens = reply.get("output_tokens", 0)
    usd = reply.get("usd")
    if usd is None and hasattr(backend, "usd_of"):
        usd = backend.usd_of(input_tokens or estimate_tokens(prompt), output_tokens or 20)

    return {
        "q": case["q"],
        "kind": case["kind"],
        "expected": expected,
        "answer": answer,
        "ok": answer in accepted,
        "expected_in_candidates": expected is None
        or any(c["name"] == expected for c in cands),
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "truncated": reply.get("truncated", False),
        "error": reply.get("error"),
        # 読み取れなかったときに、モデルが何と言ったのかを残す。
        # これが無いと「モデルが下手」と「こちらの呼び方が悪い」を
        # 取り違える。実際 #41 の再現でそれをやった。
        "raw": text[:300] if answer == "__PARSE_ERROR__" else None,
        "usd": usd or 0.0,
        "prompt_chars": len(prompt),
    }


def estimate_tokens(text: str) -> int:
    """Claude のトークン数の当たり。

    APIキーが無いので数えられない。日本語はおおむね1文字1トークン、
    ASCIIは4文字1トークンとして見る。比べたい差（10倍〜50倍）に対して
    この粗さは効かない。
    """
    ascii_chars = sum(1 for c in text if ord(c) < 128)
    return round((len(text) - ascii_chars) + ascii_chars / 4)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True, choices=sorted(BACKENDS))
    parser.add_argument("--limit", type=int)
    parser.add_argument("--jobs", type=int)
    args = parser.parse_args()

    backend = BACKENDS[args.model]
    jobs = min(args.jobs or backend.max_jobs, backend.max_jobs)
    items = load_items()
    cases = json.loads(CASES.read_text(encoding="utf-8"))["cases"]
    if args.limit:
        cases = cases[: args.limit]

    print(f"== {backend.label} ({backend.name}) ==", flush=True)
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        records = list(pool.map(lambda c: run_case(backend, c, items), cases))

    for i, r in enumerate(records, 1):
        mark = "OK " if r["ok"] else "NG "
        extra = " [出力枠切れ]" if r["truncated"] else ""
        if r["error"]:
            extra += f" [{r['error'][:40]}]"
        print(f"{mark}[{i}/{len(records)}] {r['q']} -> {r['answer']} "
              f"(正解: {r['expected']}){extra}", flush=True)

    summary = summarize(backend, records)
    RESULTS.mkdir(exist_ok=True)
    (RESULTS / f"{backend.slug}.json").write_text(
        json.dumps({"summary": summary, "records": records}, ensure_ascii=False,
                   indent=2) + "\n",
        encoding="utf-8",
    )
    report(summary)


def summarize(backend, records) -> dict:
    total = len(records)
    named = [r for r in records if r["expected"] is not None]
    none_cases = [r for r in records if r["expected"] is None]
    usd = sum(r["usd"] for r in records)
    return {
        "label": backend.label,
        "model": backend.name,
        "note": backend.note,
        "total": total,
        "correct": sum(1 for r in records if r["ok"]),
        "named_total": len(named),
        "named_correct": sum(1 for r in named if r["ok"]),
        "recall": sum(1 for r in named if r["expected_in_candidates"]),
        "none_total": len(none_cases),
        "none_correct": sum(1 for r in none_cases if r["ok"]),
        "parse_errors": sum(1 for r in records if r["answer"] == "__PARSE_ERROR__"),
        "truncated": sum(1 for r in records if r["truncated"]),
        "errors": sum(1 for r in records if r["error"]),
        "jpy_per_question": usd * USD_JPY / total if total else 0.0,
        "free_jpy_per_day": backend.free_jpy_per_day,
        "avg_output_tokens": (
            sum(r["output_tokens"] for r in records) / total if total else 0
        ),
    }


def report(s: dict):
    print()
    print(f"全体            : {s['correct']}/{s['total']} "
          f"({s['correct'] / s['total']:.0%})")
    if s["named_total"]:
        print(f"品目の対応づけ  : {s['named_correct']}/{s['named_total']} "
              f"({s['named_correct'] / s['named_total']:.0%})")
        print(f"  候補に正解あり: {s['recall']}/{s['named_total']}")
    if s["none_total"]:
        print(f"該当なしを言えた: {s['none_correct']}/{s['none_total']} "
              f"({s['none_correct'] / s['none_total']:.0%})")
    print(f"形式を崩した    : {s['parse_errors']}")
    if s["truncated"]:
        print(f"出力枠切れ      : {s['truncated']}")
    if s["errors"]:
        print(f"呼び出し失敗    : {s['errors']}")
    print(f"費用            : {s['jpy_per_question']:.4f}円/問 "
          f"（出力{s['avg_output_tokens']:.0f}トークン平均）")


if __name__ == "__main__":
    sys.exit(main())
