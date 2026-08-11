#!/usr/bin/env python3
"""目視確認した言い換えを dictionary_keywords.json へ合流させる（issue #44）。

  python3 scripts/ai_eval/merge_keywords.py
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
GENERATED = Path(__file__).resolve().parent / "generated_keywords.json"
GENERATED_BRANDS = Path(__file__).resolve().parent / "generated_brands.json"
TARGET = ROOT / "assets/data/dictionary_keywords.json"

# 何品目に付いたら「メーカー名」とみなして落とすか。
#
# 製品名・シリーズ名（iQOS・ルンバ・ブラビア）は品目を特定できるので
# 役に立つ。メーカー名（パナソニック・象印・ヤマハ）は特定できず、
# 打っても区分の違う品目が10件並ぶだけでノイズになる。
# 実測では「パナソニック」が10品目、「象印」が7品目に付いた。
MAKER_THRESHOLD = 3


def normalize(text: str) -> str:
    text = re.sub(r"[（）()【】\[\]・、。／/･]", "", text)
    return re.sub(r"[〜~ー－―\-\s]", "", text).lower()


def drop_maker_names(brands: dict) -> tuple[dict, list[str]]:
    """複数の品目に付いた語を、メーカー名とみなして落とす。"""
    count: dict[str, int] = {}
    for words in brands.values():
        for w in words:
            count[w.lower()] = count.get(w.lower(), 0) + 1

    cleaned: dict[str, list[str]] = {}
    dropped = sorted({w for w, n in count.items() if n >= MAKER_THRESHOLD})
    for name, words in brands.items():
        kept = [w for w in words if count[w.lower()] < MAKER_THRESHOLD]
        if kept:
            cleaned[name] = kept
    return cleaned, dropped


def main():
    generated = json.loads(GENERATED.read_text(encoding="utf-8"))
    target = json.loads(TARGET.read_text(encoding="utf-8"))

    if GENERATED_BRANDS.exists():
        brands, makers = drop_maker_names(
            json.loads(GENERATED_BRANDS.read_text(encoding="utf-8"))
        )
        print(f"メーカー名として落とした語: {len(makers)}語")
        print("  " + "、".join(makers[:18]) + " …")
        for name, words in brands.items():
            generated[name] = sorted(set(generated.get(name, [])) | set(words))
        print(f"商品名を {len(brands)}品目に足しました\n")

    added_words = 0
    dropped_noise = 0
    for name, words in generated.items():
        base = normalize(re.sub(r"[（(][^）)]*[）)]", "", name))
        filtered = []
        for w in words:
            key = normalize(w)
            if key == base:
                continue
            # 品目名を丸ごと含むだけのものは削る（「ろうそく（キャンドル）」
            # 「スピーカー機器」）。その品目名で検索すれば既に当たるので、
            # 語数を増やすだけで何も拾えるようにならない。
            # Workers AI で生成したぶんに、この形が298件あった。
            #
            # ただし1文字の品目名（「石」「土」）は例外。
            # lib/domain/waste_item.dart の逆方向一致は、1文字だと長い入力に
            # たまたま含まれやすいので働かない。だから「石」に対する
            # 「小石」「石ころ」のような言い換えは、ここでしか拾えない。
            if len(base) >= 2 and base in key:
                dropped_noise += 1
                continue
            filtered.append(w)
        if filtered:
            # 上書きではなく足す。既にある言い換え（#103 で目視確認した分や、
            # 手で入れた商品名）を消してしまうため。実際、商品名パスの
            # 合流で「携帯電話・ＰＨＳ」の「けいたいでんわ」「ガラケー」が
            # iPhone だけに置き換わった。
            merged = list(dict.fromkeys(target["keywords"].get(name, []) + filtered))
            target["keywords"][name] = merged
            added_words += len(filtered)

    TARGET.write_text(
        json.dumps(target, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"品目名を含むだけの言い換えを {dropped_noise}語 落としました。")
    print(f"{len(generated)}品目・{added_words}語を合流しました。")
    print(f"合計: {len(target['keywords'])}品目")


if __name__ == "__main__":
    sys.exit(main())
