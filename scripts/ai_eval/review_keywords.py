#!/usr/bin/env python3
"""生成した言い換えを、合流させる前に確認する（issue #44）。

generate_keywords.py は「既存の品目名と完全一致する言い換え」は自動で
落とすが、それだけでは足りない。実測で見つかった危険な形をここでも洗う。

  python3 scripts/ai_eval/review_keywords.py
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
GENERATED = Path(__file__).resolve().parent / "generated_keywords.json"


def normalize(text: str) -> str:
    text = re.sub(r"[（）()【】\[\]・、。／/･]", "", text)
    return re.sub(r"[〜~ー－―\-\s]", "", text).lower()


def main():
    items = []
    for name in ("dictionary.json", "dictionary_extra.json"):
        data = json.loads((ROOT / "assets/data" / name).read_text(encoding="utf-8"))
        items.extend(data["items"])
    by_name = {i["name"]: i for i in items}

    generated = json.loads(GENERATED.read_text(encoding="utf-8"))

    print(f"生成された言い換え: {len(generated)}品目")
    print(f"  語数: {sum(len(v) for v in generated.values())}語\n")

    # ① 生成対象どうしで、同じ言い換え語を持ち、区分が違う。
    #    「クーラー」→「エアコン」（収集できないもの）と「クーラーボックス」
    #    （もえないごみ）の両方に付く、というような形。検索すると両方出るだけ
    #    なので①より実害は小さいが、狙いと違う結果に見える。
    word_to = {}
    for name, words in generated.items():
        for w in words:
            word_to.setdefault(w, []).append(name)
    conflicts = {
        w: names
        for w, names in word_to.items()
        if len(names) > 1
        and len({by_name[n]["categoryLabel"] for n in names}) > 1
    }
    if conflicts:
        print(f"=== 区分の違う複数品目に付いた言い換え（{len(conflicts)}語）===")
        print("同じ言葉で検索したとき、両方が出る。狙いと違う結果に見えないか確認。\n")
        for w, names in conflicts.items():
            for n in names:
                print(f"  「{w}」→ {n}（{by_name[n]['categoryLabel']}）")
            print()

    # ② 早見表の品目名の一部を、そのまま切り出しただけの言い換え。
    #    実害は無いが、検索の逆方向一致（waste_item.dart）が既に拾っている
    #    ので冗長。同梱サイズを増やすだけなので削ってよい候補として出す。
    redundant = []
    for name, words in generated.items():
        base = normalize(re.sub(r"[（(][^）)]*[）)]", "", name))
        for w in words:
            if normalize(w) == base:
                redundant.append((name, w))
    if redundant:
        print(f"=== 品目名の主要部と同じだけの言い換え（{len(redundant)}件・削ってよい）===")
        for name, w in redundant[:20]:
            print(f"  {name} の「{w}」")
        if len(redundant) > 20:
            print(f"  …他{len(redundant) - 20}件")
        print()

    print("上を確認したうえで、次のコマンドで合流させる:")
    print("  python3 scripts/ai_eval/merge_keywords.py")


if __name__ == "__main__":
    sys.exit(main())
