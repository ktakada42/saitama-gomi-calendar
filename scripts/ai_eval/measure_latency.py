#!/usr/bin/env python3
"""待たされる時間を測る。

費用と精度が並んだら、次に効くのはこれ。分別を調べている人は
画面の前で待っている。
"""
import json
import statistics
import sys
import time

from backends import BACKENDS
from run_eval import PROMPT, candidates, load_items

CASES = ["こわれた傘", "プラスチックの弁当箱", "けいたいでんわ", "むかしの写真", "電子レンジ"]


def main():
    items = load_items()
    prompts = [
        PROMPT.format(
            query=q,
            candidates="\n".join(f"- {c['name']}" for c in candidates(q, items)),
        )
        for q in CASES
    ]

    for label in sys.argv[1:]:
        backend = BACKENDS[label]
        times = []
        for prompt in prompts * 2:
            start = time.monotonic()
            backend.ask(prompt)
            times.append(time.monotonic() - start)
        times.sort()
        print(f"{label:<20} 中央値 {statistics.median(times):>5.2f}秒  "
              f"最遅 {times[-1]:>5.2f}秒")


if __name__ == "__main__":
    sys.exit(main())
