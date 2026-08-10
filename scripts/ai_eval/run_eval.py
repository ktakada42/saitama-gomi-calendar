#!/usr/bin/env python3
"""AI分別相談の精度を測る（issue #41）。

案Bの設計を確かめる。AIの役割は「利用者の言い方を辞書の品目に対応づけること」
だけで、区分そのものは辞書の記載をそのまま出す。だから測るべきは
「対応づけが当たるか」と「辞書に無いものを無いと言えるか」の2点。

サーバーは立てない。手元の claude CLI に投げて答え合わせするだけ。

  python3 scripts/ai_eval/run_eval.py            # 全件
  python3 scripts/ai_eval/run_eval.py --limit 5  # 抜き取り
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
DICT = ROOT / "assets/data/dictionary.json"
CASES = Path(__file__).resolve().parent / "cases.json"

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


def ask(query: str, cands) -> str | None:
    listing = "\n".join(f"- {c['name']}" for c in cands)
    prompt = PROMPT.format(query=query, candidates=listing or "(候補なし)")
    result = subprocess.run(
        ["claude", "-p"],
        input=prompt,
        capture_output=True,
        text=True,
        timeout=180,
    )
    out = result.stdout.strip()
    match = re.search(r"\{.*\}", out, re.S)
    if not match:
        return "__PARSE_ERROR__"
    try:
        return json.loads(match.group(0)).get("item")
    except json.JSONDecodeError:
        return "__PARSE_ERROR__"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int)
    parser.add_argument("--out", default=str(Path(__file__).parent / "result.json"))
    args = parser.parse_args()

    items = load_items()
    cases = json.loads(CASES.read_text(encoding="utf-8"))["cases"]
    if args.limit:
        cases = cases[: args.limit]

    records = []
    for i, case in enumerate(cases, 1):
        cands = candidates(case["q"], items)
        answer = ask(case["q"], cands)
        expected = case["expected"]
        in_candidates = expected is None or any(
            c["name"] == expected for c in cands
        )
        # 判断が割れる問いは、どちらの答えも正解として扱う
        # （例：「ペットボトルのフタ」に本体を出すか、該当なしと言うか）。
        accepted = [expected, *case.get("accept_also", [])]
        ok = answer in accepted
        records.append(
            {
                "q": case["q"],
                "kind": case["kind"],
                "expected": expected,
                "answer": answer,
                "ok": ok,
                "expected_in_candidates": in_candidates,
            }
        )
        mark = "OK " if ok else "NG "
        print(f"{mark}[{i}/{len(cases)}] {case['q']} -> {answer} (正解: {expected})",
              flush=True)

    Path(args.out).write_text(
        json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    total = len(records)
    correct = sum(1 for r in records if r["ok"])
    none_cases = [r for r in records if r["expected"] is None]
    none_ok = sum(1 for r in none_cases if r["ok"])
    named = [r for r in records if r["expected"] is not None]
    named_ok = sum(1 for r in named if r["ok"])
    recall = sum(1 for r in named if r["expected_in_candidates"])

    print()
    print(f"全体          : {correct}/{total} ({correct / total:.0%})")
    if named:
        print(f"品目の対応づけ: {named_ok}/{len(named)} ({named_ok / len(named):.0%})")
        print(f"  うち候補に正解が入っていた: {recall}/{len(named)}")
    if none_cases:
        print(f"該当なしを言えた: {none_ok}/{len(none_cases)} "
              f"({none_ok / len(none_cases):.0%})")


if __name__ == "__main__":
    sys.exit(main())
