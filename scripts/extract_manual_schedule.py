#!/usr/bin/env python3
"""さいたま市「家庭ごみの出し方マニュアル」PDFの
「地区別ごみ収集曜日一覧表」から、町丁目ごとの収集曜日を抽出する。

これまでこのリポジトリの areas.json は、市の公式サイトが内部で使っている
第三者ベンダー(gomisuke/株式会社G-Place)の非公開APIから生成していた
(#18で運用リスクとして指摘)。gomisukeは自治体向けの有料SaaS製品で、
その編集済みデータベースをアプリに同梱することには著作権・利用規約上の
懸念があった。

このスクリプトは、さいたま市自身が公開しているPDFマニュアルに含まれる
「地区別ごみ収集曜日一覧表」（P18-19、町丁目ごとに収集曜日を一覧にした表）を
直接読み取ることで、gomisukeを一切経由せずに同じ情報を取得する。
これは市が住民向けに配布している一次資料そのものであり、市の内部システムへの
無断アクセスにはあたらない。

表の見方（マニュアル自身の凡例より）:
  燃 …もえるごみ
  不燃…もえないごみ
  資1…資源物1類（びん・かん・ペット・容器包装プラ）
  資2…資源物2類（古紙類・繊維）
  危険…有害危険ごみ
この表では「不燃・資2・危険」の3区分が1本の共通の曜日列にまとまっている
（実際にこの3区分は同じ曜日にまとめて収集される地区がほとんどであることは
lib/domain/collection_area.dart のコメントにも既に書かれている）。

使い方:
    python3 -m venv .venv && .venv/bin/pip install pdfplumber
    .venv/bin/python3 scripts/extract_manual_schedule.py > scripts/manual_schedule.json

前提: PDFがA4見開き2ページ(表の1ページ目・2ページ目)にまたがって1つの
座標空間として埋め込まれている(見開き印刷用データの名残と見られる)。
pdfplumberでどちらか一方のページを読むだけで見開き全体の文字が取得できる。
"""
import json
import re
import sys
import urllib.request

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

# 区名: (列位置キー, この区のデータ開始top, 次にこの列に来る区の開始top or None)
# 列位置キー・top値は「地区別ごみ収集曜日一覧表」ページの実測値(2026年8月時点のPDF)。
# マニュアルが改版されてレイアウトが変わった場合はここを再計測する必要がある。
WARDS = [
    ("西区", 57.0, 94.4, 473.1),
    ("北区", 57.0, 473.1, 682.9),
    ("中央区", 57.0, 682.9, None),
    ("大宮区", 266.8, 94.4, 400.5),
    ("見沼区", 266.8, 400.5, None),
    ("桜区", 476.6, 94.4, 397.0),
    ("浦和区", 476.6, 397.0, None),
    ("南区", 731.7, 52.0, 407.3),
    ("緑区", 731.7, 407.3, None),
    ("岩槻区", 941.5, 52.0, None),
]

# 列位置キー -> (町名開始x, 燃開始x, 共通(不燃/資2/危険)開始x, 資1開始x, 次列開始x)
# ヘッダーラベルの位置ではなく、実データの語の左端を直接測って求めた値。
# (ラベル文字とデータ文字で幅が違うため、ラベル基準だと数px〜十数pxずれる)
COL_BOUNDS = {
    57.0: (82.2, 168.5, 199.7, 225.3, 266.8),
    266.8: (292.0, 378.4, 409.3, 434.8, 476.6),
    476.6: (501.7, 633.3, 664.5, 689.9, 731.7),
    731.7: (756.8, 843.1, 874.1, 899.6, 941.5),
    941.5: (966.6, 1052.9, 1083.9, 1109.4, 1174.2),
}

# 縦書きの「西部清掃事務所」「東部清掃事務所」バナー、およびページ右端の
# 縦書きタイトル「一収地区別ごみ／覧表別収集曜日」の実測x座標。
# 資1列のすぐ右に重なって誤爆するため、ピンポイントで除外する。
BANNER_X = [
    243.07, 452.83, 707.95, 708.45, 917.71, 917.99, 1127.48,
    1151.45, 1153.2, 1162.79, 1174.13,
]

FOOTNOTE_MARKERS = (
    "もえるごみ」の早朝地区",
    "旧指扇地区の範囲は",
    "でご確認ください。",
    "収集所の場所と曜日については",
    "https://",
)

HEADER_TOKENS = {
    "燃", "不燃", "資1", "資2", "危険", "担当", "不資危", "燃2険", "当", "▼",
    "西部清掃事務所", "東部清掃事務所",
}

WEEKDAY_RE = re.compile(r"^[月火水木金土日](・[月火水木金土日])*$")
KANA_PREFIX_RE = re.compile(r"^[ぁ-ん](?=[一-龥Ａ-Ｚａ-ｚA-Za-z0-9０-９（〜～、・★])")

WEEKDAY_TO_INT = {"月": 1, "火": 2, "水": 3, "木": 4, "金": 5, "土": 6, "日": 7}


def fetch_pdf_bytes():
    req = urllib.request.Request(MANUAL_URL, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as res:
        return res.read()


def find_table_page(pdf):
    """「地区別ごみ収集曜日一覧表」を含むページを探す。
    見開き構成でどちらのページからも全文が読めるため、最初に見つかった1枚でよい。"""
    for i, page in enumerate(pdf.pages):
        text = page.extract_text() or ""
        if "地区別" in text and "収集曜日一覧表" in text and "内野本郷" in text:
            return page
    raise RuntimeError("「地区別ごみ収集曜日一覧表」ページが見つかりませんでした。PDFの構成が変わった可能性があります。")


def is_banner(w):
    return any(abs(w["x0"] - bx) < 0.5 for bx in BANNER_X)


def cluster_by_top(words, tol=2.0):
    words = sorted(words, key=lambda w: w["top"])
    groups = []
    for w in words:
        if groups and w["top"] - groups[-1][-1]["top"] <= tol:
            groups[-1].append(w)
        else:
            groups.append([w])
    result = []
    for g in groups:
        g.sort(key=lambda w: w["x0"])
        text = "".join(w["text"] for w in g)
        top = sum(w["top"] for w in g) / len(g)
        result.append((top, text))
    return result


def nearest(groups, target_top, tol=5.0):
    best, best_diff = None, tol
    for top, text in groups:
        diff = abs(top - target_top)
        if diff <= best_diff:
            best, best_diff = text, diff
    return best or ""


def parse_ward(all_words, ward_name, col_key, top_start, top_end):
    town_x, burn_x, shared_x, res1_x, next_col_x = COL_BOUNDS[col_key]
    lo = top_start - 3
    hi = top_end - 3 if top_end is not None else 900

    def in_block(w):
        return town_x - 20 <= w["x0"] < next_col_x - 15 and lo <= w["top"] < hi

    words = [
        w for w in all_words
        if in_block(w)
        and w["text"] not in HEADER_TOKENS
        and not w["text"].startswith("※")
        and "清掃事務所" not in w["text"]
        and not is_banner(w)
        and not any(marker in w["text"] for marker in FOOTNOTE_MARKERS)
    ]

    town_groups = cluster_by_top([w for w in words if w["x0"] < burn_x - 3])
    burn_groups = cluster_by_top([w for w in words if burn_x - 3 <= w["x0"] < shared_x - 3])
    shared_groups = cluster_by_top([w for w in words if shared_x - 3 <= w["x0"] < res1_x - 3])
    res1_groups = cluster_by_top([w for w in words if res1_x - 3 <= w["x0"] < next_col_x - 15])

    entries = []
    for top, town in town_groups:
        # 未知グリフの補正はかな行インデックス除去より先に行う
        # ((cid:...)のままだとlookaheadが次の文字を漢字と認識できない)。
        town = town.replace("(cid:7665)", "櫛").replace("(cid:8267)", "辻")
        m = KANA_PREFIX_RE.match(town)
        if m:
            town = town[1:]
        if not town:
            continue

        burnable = nearest(burn_groups, top)
        shared = nearest(shared_groups, top)
        res1 = nearest(res1_groups, top)
        entries.append({
            "ward": ward_name, "town": town,
            "burnable": burnable, "shared": shared, "recyclable1": res1,
        })
    return entries


def to_rule_list(weekday_text):
    """「火・金」のような文字列を [2, 5] のような曜日番号リストに変換する。"""
    if not weekday_text:
        return []
    return [WEEKDAY_TO_INT[d] for d in weekday_text.split("・") if d in WEEKDAY_TO_INT]


def build_area(entry, idx):
    town = entry["town"]
    early_morning = "★1" in town
    # ★3は市自身が「近隣の方や地元自治会にお尋ねください」としている、
    # つまりこの一覧表だけでは曜日を確定できないという市の申告。
    # 自動で不確かな情報を提示するよりは、地区が見つからない代替経路
    # (曜日の手入力)にフォールバックさせる方が誠実なので、生成対象から除く。
    uncertain = "★3" in town

    display_name = re.sub(r"★[0-9]", "", town).strip()

    rules = {}
    burn_days = to_rule_list(entry["burnable"])
    if burn_days:
        rules["burnable"] = [{"weekday": d} for d in burn_days]
    shared_days = to_rule_list(entry["shared"])
    if shared_days:
        rule = [{"weekday": d} for d in shared_days]
        rules["nonBurnable"] = rule
        rules["hazardous"] = rule
        rules["recyclable2"] = rule
    res1_days = to_rule_list(entry["recyclable1"])
    if res1_days:
        rules["recyclable1"] = [{"weekday": d} for d in res1_days]

    return {
        "id": f"manual-{idx}",
        "ward": entry["ward"],
        "name": display_name,
        "earlyMorning": early_morning,
        "note": (
            "さいたま市「家庭ごみの出し方マニュアル」の"
            "地区別ごみ収集曜日一覧表（令和8年3月1日時点）より"
        ),
        "rules": rules,
    }, uncertain


def main():
    pdf_bytes = fetch_pdf_bytes()
    tmp_path = "/tmp/gomimanual.pdf"
    with open(tmp_path, "wb") as f:
        f.write(pdf_bytes)

    with pdfplumber.open(tmp_path) as pdf:
        page = find_table_page(pdf)
        words = page.extract_words(use_text_flow=False, keep_blank_chars=False)

    all_entries = []
    for ward_name, col_key, top_start, top_end in WARDS:
        entries = parse_ward(words, ward_name, col_key, top_start, top_end)
        print(f"{ward_name}: {len(entries)}件", file=sys.stderr)
        all_entries.append((ward_name, entries))

    total = sum(len(e) for _, e in all_entries)
    print(f"合計: {total}件", file=sys.stderr)
    if not (250 <= total <= 400):
        print(
            f"警告: 抽出件数({total})が想定範囲(250〜400)外です。"
            "PDFのレイアウトが変わり、列位置の再計測が必要かもしれません。",
            file=sys.stderr,
        )

    areas = []
    skipped_uncertain = []
    idx = 0
    for ward_name, entries in all_entries:
        for entry in entries:
            burnable_days = to_rule_list(entry["burnable"])
            shared_days = to_rule_list(entry["shared"])
            res1_days = to_rule_list(entry["recyclable1"])
            if not (burnable_days and shared_days and res1_days):
                print(f"警告: 曜日が不完全な行をスキップ: {entry}", file=sys.stderr)
                continue
            idx += 1
            area, uncertain = build_area(entry, idx)
            if uncertain:
                skipped_uncertain.append(area["ward"] + " " + area["name"])
                continue
            areas.append(area)

    if skipped_uncertain:
        print(
            f"★3(市が「近隣にお尋ねください」としている)地区を{len(skipped_uncertain)}件除外:",
            file=sys.stderr,
        )
        for s in skipped_uncertain:
            print("  " + s, file=sys.stderr)

    print(f"最終的な地区数: {len(areas)}", file=sys.stderr)
    json.dump(areas, sys.stdout, ensure_ascii=False, indent=2)
    print(file=sys.stdout)


if __name__ == "__main__":
    main()
