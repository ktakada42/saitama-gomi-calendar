#!/usr/bin/env python3
"""さいたま市「家庭ごみの出し方マニュアル」の「ごみの分別早見表」から、
品目ごとの分別区分と出し方の注意点を抽出して assets/data/dictionary.json を作る。

地区データ（scripts/extract_manual_schedule.py）と同じ考え方で、市が住民向けに
配布している一次資料から直接読み取る。市の公式サイトの分別辞典ページは
第三者ベンダー（gomisuke / 株式会社G-Place）の非公開APIで動いており、
そちらを使うと #18 と同じライセンス上の問題が再発するため経由しない。

使い方:
    python3 -m venv .venv && .venv/bin/pip install pdfplumber
    .venv/bin/python3 scripts/extract_waste_dictionary.py
"""
import json
import re
import sys
import urllib.request
from collections import Counter
from pathlib import Path

try:
    import pdfplumber
except ImportError:
    print(
        "pdfplumberが必要です。 python3 -m venv .venv && .venv/bin/pip install pdfplumber",
        file=sys.stderr,
    )
    raise

MANUAL_URL = (
    "https://www.city.saitama.lg.jp/001/006/010/003/p005300_d/fil/r8_jp_gomimanual_tan.pdf"
)

OUTPUT = Path(__file__).resolve().parent.parent / "assets" / "data" / "dictionary.json"

# 早見表は4ブロック横並び。各ブロックは (品目開始x, 区分開始x, 注意点開始x, ブロック終端x)。
# ヘッダーのラベル位置ではなく、実データの語の左端から計測した値。
BLOCKS = [
    (71.0, 160.0, 182.0, 330.0),
    (335.0, 424.0, 446.0, 636.0),
    (641.0, 730.0, 752.0, 900.0),
    (905.0, 994.0, 1016.0, 1160.0),
]

# 品目名の隣に置かれた「プラマーク付き」等のバッジは、本文より一回り小さい
# フォントで描かれている（本文8.5pt に対して 4.9〜5.2pt）。品目名に混ざると
# 「食品トレイマ付ーきク」のような読めない文字列になるので、大きさで落とす。
MIN_BODY_FONT_HEIGHT = 7.0

# 表の下端。これより下はページ脚注（★の説明など）なので、
# 最後の品目の注意点がそこまで巻き込まないように切る。
TABLE_BOTTOM = 800.0

# 表の凡例にある分別区分。アプリの5区分に収まらないもの（粗大・小型家電・電池・
# 排出禁止）も、利用者が知りたいのはまさにそこなので id を与えて持っておく。
CATEGORIES = {
    "燃": ("burnable", "もえるごみ"),
    "不燃": ("nonBurnable", "もえないごみ"),
    "資1": ("recyclable1", "資源物1類"),
    "資2": ("recyclable2", "資源物2類"),
    "危険": ("hazardous", "有害危険ごみ"),
    "粗大": ("oversized", "粗大ごみ・適正処理困難物"),
    "小型": ("smallAppliance", "小型家電"),
    "電池": ("battery", "電池回収ボックス"),
    "×": ("notAccepted", "収集できないもの"),
}

# 表以外の要素（ヘッダーの凡例・脚注・縦書きの帯）を落とすためのキーワード
NOISE_SUBSTRINGS = (
    "ごみの分別早見表",
    "もえるごみ",
    "もえないごみ",
    "資源物1類",
    "資源物2類",
    "有害危険ごみ",
    "粗大ごみ・適正処理困難物",
    "小型家電",
    "排出禁止",
    "出し方の注意点等",
    "★1…",
    "★2…",
    "★3…",
    "★4…",
    "★5…",
    "★6…",
    "早見表に記載のない品目",
    "収集所は地元のみなさん",
    "収集曜日を必ず守り",
    "解体できる",
    "で囲まれているもので",
    "ごみ分別辞典",
    "アプリ対応",
    "iOS版",
    "Android版",
    "https://",
    "さいたま市",
    "検索",
)


def fetch_pdf_bytes():
    req = urllib.request.Request(MANUAL_URL, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as res:
        return res.read()


def is_noise(text: str) -> bool:
    return any(s in text for s in NOISE_SUBSTRINGS)


def is_body_text(word) -> bool:
    return word.get("height", 0) >= MIN_BODY_FONT_HEIGHT


def cluster_rows(words, tol=3.0):
    """topが近い語を1行にまとめる。"""
    words = sorted(words, key=lambda w: w["top"])
    rows = []
    for w in words:
        if rows and w["top"] - rows[-1][-1]["top"] <= tol:
            rows[-1].append(w)
        else:
            rows.append([w])
    return rows


def join_row(words):
    return "".join(w["text"] for w in sorted(words, key=lambda w: w["x0"])).strip()


def extract_page(page):
    words = page.extract_words(use_text_flow=False, keep_blank_chars=False)
    entries = []

    for item_x, cat_x, note_x, end_x in BLOCKS:
        block = [
            w
            for w in words
            # 品目列の左には、かな行インデックス（あ・い・う…）が置かれている。
            # 少し左まで含めてから、後で1文字のかなを落とす。
            if item_x - 14 <= w["x0"] < end_x and not is_noise(w["text"])
        ]
        if not block:
            continue

        # 品目名にはバッジの小さな文字を混ぜない。
        item_words = [w for w in block if w["x0"] < cat_x - 3 and is_body_text(w)]
        cat_words = [w for w in block if cat_x - 3 <= w["x0"] < note_x - 3]
        # ブロックの右端には、ページをまたぐ縦書きの装飾帯が重なっていることがある。
        # 注意点の実データはブロック終端より十分内側に収まるので、手前で切る。
        note_words = [w for w in block if note_x - 3 <= w["x0"] < end_x - 12]

        item_rows = cluster_rows(item_words)
        # 各品目行の代表topを先に出しておく。注意点は「この品目行から
        # 次の品目行の手前まで」に入るものを全部拾う（複数行になるため）。
        item_tops = [sum(w["top"] for w in r) / len(r) for r in item_rows]

        for index, row in enumerate(item_rows):
            top = item_tops[index]
            next_top = (
                item_tops[index + 1] if index + 1 < len(item_tops) else float("inf")
            )

            name = join_row(row)
            # 行頭のかな行インデックス（1文字）を落とす。
            name = re.sub(r"^[ぁ-ん](?=[^ぁ-ん]|$)", "", name).strip()
            if not name:
                continue

            def nearest(candidates, tol=6.0):
                best, best_d = [], tol
                for r in cluster_rows(candidates):
                    t = sum(w["top"] for w in r) / len(r)
                    d = abs(t - top)
                    if d <= best_d:
                        best, best_d = r, d
                return join_row(best) if best else ""

            category_raw = nearest(cat_words)
            category = CATEGORIES.get(category_raw)
            if category is None:
                # 区分が読めない行は表の一部ではない（脚注など）。
                continue
            category_id, category_label = category

            note_parts = [
                w
                for w in note_words
                if top - 4 <= w["top"] < min(next_top - 4, TABLE_BOTTOM)
            ]
            note = "".join(
                w["text"]
                for w in sorted(note_parts, key=lambda w: (round(w["top"], 1), w["x0"]))
            ).strip()

            entries.append(
                {
                    "name": name,
                    "category": category_id,
                    "categoryLabel": category_label,
                    "note": note,
                }
            )
    return entries


def find_table_pages(pdf):
    """早見表のページを探す。

    このPDFは見開きで作られていて、同じ内容が2つのページに別々の座標系で入る。
    座標系が素直な方（BLOCKSの値がそのまま使える方）だけを返す。
    """
    pages = []
    for page in pdf.pages:
        text = page.extract_text() or ""
        if "分別" not in text or "出し方の注意点等" not in text:
            continue
        words = page.extract_words(use_text_flow=False, keep_blank_chars=False)
        counts = Counter(round(w["x0"]) for w in words)
        # BLOCKS[0] の品目列に語が集まっていれば、こちら側の座標系。
        base = BLOCKS[0][0]
        if any(n >= 20 for x, n in counts.items() if base - 11 <= x <= base + 9):
            pages.append(page)
    return pages


def main():
    pdf_bytes = fetch_pdf_bytes()
    tmp_path = "/tmp/gomimanual_dictionary.pdf"
    with open(tmp_path, "wb") as f:
        f.write(pdf_bytes)

    all_entries = []
    with pdfplumber.open(tmp_path) as pdf:
        pages = find_table_pages(pdf)
        if not pages:
            raise RuntimeError(
                "「ごみの分別早見表」のページが見つかりませんでした。"
                "PDFの構成が変わった可能性があります。"
            )
        for page in pages:
            page_entries = extract_page(page)
            print(f"page {page.page_number}: {len(page_entries)}件", file=sys.stderr)
            all_entries.extend(page_entries)

    # 同じ品目が複数ページに出ることはないが、念のため重複を除く
    seen = set()
    items = []
    for e in all_entries:
        key = (e["name"], e["category"])
        if key in seen:
            continue
        seen.add(key)
        items.append(e)

    items.sort(key=lambda e: e["name"])

    print(f"合計: {len(items)}件", file=sys.stderr)
    counts = Counter(e["categoryLabel"] for e in items)
    for label, n in counts.most_common():
        print(f"  {label}: {n}件", file=sys.stderr)

    if not (300 <= len(items) <= 700):
        print(
            f"警告: 抽出件数({len(items)})が想定範囲(300〜700)外です。"
            "PDFのレイアウトが変わり、列位置の再計測が必要かもしれません。",
            file=sys.stderr,
        )

    payload = {
        "version": 1,
        "source": "さいたま市「家庭ごみの出し方マニュアル」ごみの分別早見表（令和8年度版）",
        "sourceUrl": "https://www.city.saitama.lg.jp/001/006/010/003/p005300.html",
        "items": items,
    }
    OUTPUT.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"完了: {OUTPUT} に書き込みました。", file=sys.stderr)


if __name__ == "__main__":
    main()
