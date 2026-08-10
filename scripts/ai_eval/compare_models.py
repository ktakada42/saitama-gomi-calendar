#!/usr/bin/env python3
"""測り終えたモデルを並べる。

  python3 scripts/ai_eval/compare_models.py

判断の順番を間違えないこと。**まず「該当なし」を見る**。
分別を間違えて伝えるのは、答えないより悪い。安さは、そこを満たした
モデルの中でだけ意味がある。
"""
import json
import sys
from pathlib import Path

RESULTS = Path(__file__).resolve().parent / "results"

# 利用者1人が月に5問使うとして、この人数ぶんの月額を出す。
SCALES = [(100, 500), (1_000, 5_000), (10_000, 50_000)]


def main():
    files = sorted(RESULTS.glob("*.json"))
    if not files:
        print("results/ が空です。先に run_eval.py を回してください。", file=sys.stderr)
        return 1

    rows = [json.loads(f.read_text(encoding="utf-8"))["summary"] for f in files]
    # 該当なしの正答率、次に全体、最後に安さ。
    rows.sort(key=lambda r: (-_rate(r, "none"), -_rate(r, "all"), r["jpy_per_question"]))

    print(f"{'モデル':<20} {'該当なし':>9} {'対応づけ':>9} {'全体':>9} "
          f"{'崩れ':>5} {'円/問':>9} {'1,000人の月額':>13}")
    print("-" * 84)
    for r in rows:
        monthly = monthly_jpy(r, 5_000)
        print(
            f"{r['label']:<20} "
            f"{r['none_correct']:>3}/{r['none_total']:<5} "
            f"{r['named_correct']:>3}/{r['named_total']:<5} "
            f"{r['correct']:>3}/{r['total']:<5} "
            f"{r['parse_errors']:>5} "
            f"{r['jpy_per_question']:>9.4f} "
            f"{monthly:>12,.0f}円"
        )

    print()
    print("月額（1人が月5問として）")
    print(f"{'モデル':<20}" + "".join(f"{u:>11,}人" for u, _ in SCALES))
    print("-" * 56)
    for r in rows:
        cells = "".join(f"{monthly_jpy(r, q):>11,.0f}円" for _, q in SCALES)
        print(f"{r['label']:<20}{cells}")
    print()
    print("Workers AI の分は1日10,000 neuron の無料枠を差し引いてある。")

    notes = [r for r in rows if r["truncated"] or r["errors"] or r["note"]]
    if notes:
        print()
        print("備考")
        for r in notes:
            bits = []
            if r["note"]:
                bits.append(r["note"])
            if r["truncated"]:
                bits.append(f"出力枠切れ{r['truncated']}件")
            if r["errors"]:
                bits.append(f"呼び出し失敗{r['errors']}件")
            bits.append(f"出力{r['avg_output_tokens']:.0f}トークン平均")
            print(f"  {r['label']}: " + "、".join(bits))
    return 0


def monthly_jpy(row: dict, questions_per_month: int) -> float:
    """月にいくら請求されるか。

    Workers AI には1日ぶんの無料枠がある。使い切らない限り0円なので、
    差し引かずに並べると、実際より高く見える。
    """
    cost = row["jpy_per_question"] * questions_per_month
    free = row.get("free_jpy_per_day", 0.0) * 30
    return max(0.0, cost - free)


def _rate(row: dict, kind: str) -> float:
    if kind == "none":
        return row["none_correct"] / row["none_total"] if row["none_total"] else 0
    return row["correct"] / row["total"] if row["total"] else 0


if __name__ == "__main__":
    sys.exit(main())
