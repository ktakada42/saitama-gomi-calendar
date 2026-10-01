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
# 脚注の位置が読み取れなかったときの値で、ふだんは find_table_bottom が決める。
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

# 表以外の要素（ヘッダー・脚注・縦書きの帯）を落とすためのキーワード
NOISE_SUBSTRINGS = (
    "ごみの分別早見表",
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

# 表の上に置かれた凡例（区分の名前の一覧）。
#
# 区分の名前は注意点の本文にも出てくる（「金属製は、もえないごみ」
# 「※液体のものは、排出禁止」）。語の中身だけで落とすと、そういう注意点が
# 語ごと消える。凡例は表の見出しより上にしか無いので、位置と合わせて見る。
LEGEND_SUBSTRINGS = (
    "もえるごみ",
    "もえないごみ",
    "資源物1類",
    "資源物2類",
    "有害危険ごみ",
    "粗大ごみ・適正処理困難物",
    "小型家電",
    "排出禁止",
)

# 凡例の下端。凡例はtop 10〜22、表の最初の行はtop 35以降にある。
LEGEND_BOTTOM = 30.0

# 品目の行を囲む赤い枠。市が早見表の上に「□で囲まれているもので、全て
# プラスチック製で最長の辺が30㎝未満のものは、令和8年10月からプラスチック
# 資源として回収します」と書いている、その枠。行（品目・区分・注意点）を
# まるごと囲む、塗りのない線だけの四角として描かれている。
BOX_WIDTH = 235.0
BOX_MARK = "box"


def fetch_pdf_bytes():
    req = urllib.request.Request(MANUAL_URL, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as res:
        return res.read()


def is_noise(word) -> bool:
    text = word["text"]
    if any(s in text for s in NOISE_SUBSTRINGS):
        return True
    return word["top"] < LEGEND_BOTTOM and any(s in text for s in LEGEND_SUBSTRINGS)


def find_boxes(page):
    """品目の行を囲む赤い枠を拾う。"""
    return [
        r
        for r in page.rects
        if r.get("stroke")
        and not r.get("fill")
        and abs(r["width"] - BOX_WIDTH) < 2
        and is_red(r.get("stroking_color"))
    ]


def is_red(color) -> bool:
    if not color or len(color) != 3:
        return False
    red, green, blue = color
    return red > 0.8 and green < 0.2 and blue < 0.2


def find_table_bottom(words) -> float:
    """表の下端。脚注（★の説明）が始まる手前まで。

    脚注の位置はページによって違う（1ページ目はtop 818、2ページ目は804）。
    固定の値で切ると、脚注の遅いページでは最後の行の注意点が落ちる。
    """
    footnotes = [
        w["top"] for w in words if re.match(r"★[1-6１-６]…", w["text"])
    ]
    return min(footnotes) - 1 if footnotes else TABLE_BOTTOM


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
    """語を、上の行から下の行へ、行の中は左から右へ繋ぐ。

    折り返した品目名を1つにまとめたときのために行へ分けてから並べる。
    x0だけで並べると、2行目の語が1行目の語の間に食い込む。
    """
    return "".join(
        "".join(w["text"] for w in sorted(line, key=lambda w: w["x0"]))
        for line in cluster_rows(words)
    ).strip()


# 表の行の間隔はおよそ13.6pt。字を小さくして折り返した品目名の続きは、
# それより詰まった位置に置かれる。
WRAPPED_LINE_GAP = 10.0


def merge_wrapped_rows(rows):
    """小さい字で組まれた品目名の、折り返した続きを前の行に繋ぐ。

    「カセットボンベ（カートリッジ式ボンベ）」のように欄に収まらない品目名は、
    市が字を小さくして2行に折り返している。別の行のままにすると
    「（カートリッジ式ボンベ）」だけの品目ができる。
    """
    merged = []
    for row in rows:
        previous = merged[-1] if merged else None
        if (
            previous
            and all(not is_body_text(w) for w in row)
            and all(not is_body_text(w) for w in previous)
            and min(w["top"] for w in row) - max(w["top"] for w in previous)
            < WRAPPED_LINE_GAP
        ):
            previous.extend(row)
        else:
            merged.append(list(row))
    return merged


# 注意点の欄で、同じ行の語のあいだがこれ以上空いていたら別の但し書き。
#
# 「回収ボックスへ　もえないごみとしても出せます」のように、1つの欄に
# 但し書きを横に並べてある行がある。字の間隔は0前後で、但し書きどうしの
# あいだは2.3〜5.5空いている。
NOTE_GAP = 2.0

# 行の終わりがこの字なら、次の行へ文が続いている。
# 「電動歯ブラシは電池を抜いて、／回収ボックスへ」「まんが本等を／一緒に」
# 「厚さ10cm未満で／長さ90cm未満の場合のみ」「紙などでくるむか／洗剤などの」
WRAP_ENDINGS = ("、", "を", "で", "か")

# 行の始まりがこれなら、前の行から文が続いている。
# 「直径30㎝未満／の束にして」「フロンガス／を回収済み」
# 「回収ボックス／またはもえないごみへ」「紙パックとして／（雨の日は次回に）」
WRAP_BEGINNINGS = ("の", "を", "または", "（")


def is_katakana(char) -> bool:
    return "ァ" <= char <= "ヶ" or char == "ー"


def continues(previous: str, following: str) -> bool:
    """前の行から次の行へ、文が折り返して続いているか。

    欄に収まらない但し書きは2行に折り返してあり、別々の但し書きを2行に
    並べたものと、位置からは見分けられない（折り返した行が欄の幅いっぱい
    とは限らない）。文の切れ目として不自然なところで終わっているかを見る。
    """
    if not previous or not following:
        return True
    # 「〜まで」は文の終わり。「1日につき10個まで／戸別収集の場合は…」
    if previous.endswith(WRAP_ENDINGS) and not previous.endswith("まで"):
        return True
    if following.startswith(WRAP_BEGINNINGS):
        return True
    # 括弧が開いたまま：「（フタとラベルははずして容器包装／プラスチックへ）」
    opened = sum(previous.count(c) for c in "（(")
    closed = sum(previous.count(c) for c in "）)")
    if opened > closed:
        return True
    # カタカナ語の途中：「フロンガ／スを回収済み」
    return is_katakana(previous[-1]) and is_katakana(following[0])


def join_note(words):
    """注意点の語を繋ぐ。別々の但し書きのあいだには改行を入れる。

    区切らずに繋ぐと「金属製は、もえないごみ電池が外れないものは、
    小型家電回収ボックスへ」のように、どこで文が切れるのか読めなくなる。
    """
    pieces = []
    for line in cluster_rows(words):
        line = sorted(line, key=lambda w: w["x0"])
        # まず、間隔の空いたところで語をまとまりに分ける。
        runs = [line[0]["text"]]
        for left, right in zip(line, line[1:]):
            if right["x0"] - left["x1"] >= NOTE_GAP:
                runs.append("")
            runs[-1] += right["text"]

        text = ""
        glue = True
        for run in runs:
            if run in CATEGORIES:
                # 文の途中に置かれた区分のバッジ。「箱は口金部分をはずして
                # [資2] その他の紙へ」。冊子を持たない人には略号が通じないので
                # 区分の名前に直す。市も別の欄では「資源物2類のその他の紙
                # として」と書いている。
                text += CATEGORIES[run][1] + "の"
                glue = True
                continue
            # 印（「★2」）の前後と、括弧の但し書きの前は、文の途中。
            inline = MARK_ONLY.fullmatch(run) or run.startswith("（")
            if text and not glue and not inline:
                pieces.append(text)
                text = ""
            text += run
            glue = bool(MARK_ONLY.fullmatch(run))
        pieces.append(text)

    note = ""
    for piece in pieces:
        # 印は split_marks があとで取り除く。繋がるかどうかは印を除いて見る。
        bare_note = strip_marks(note.split("\n")[-1])
        note += ("" if continues(bare_note, strip_marks(piece)) else "\n") + piece
    return note.strip()


def tidy_note_lines(note: str) -> str:
    """印を取り除いたあとに残った、空の行と行頭・行末の空白を落とす。"""
    return "\n".join(line.strip() for line in note.split("\n") if line.strip())


def split_joined_kana_head(words, item_x):
    """かな行の見出しと品目名がくっついた語を分ける。

    「ほ（車の）ホイール」のように見出しのかなと品目名が続けて置かれると、
    pdfplumberはこれを1語として読む。語のx0は見出しの位置になるので、
    そのままでは品目列の外に落ちて品目ごと消え、見出しも拾えなくなる
    （「ほ」が抜けると、以降の品目が直前の「へ」に流れ込む）。
    """
    split = []
    for w in words:
        head = w["text"][:1]
        if (
            item_x - 16 <= w["x0"] < item_x - 6
            and len(w["text"]) > 1
            and "ぁ" <= head <= "ん"
        ):
            split.append({**w, "text": head})
            # 残りは品目名。x0は品目列の左端に置き直す。
            split.append({**w, "text": w["text"][1:], "x0": item_x})
        else:
            split.append(w)
    return split


def split_joined_category(words, item_x, cat_x):
    """品目名と区分がくっついた語を分ける。

    品目名が欄いっぱいまで伸びると、すぐ隣の区分とのあいだに隙間が無くなり、
    pdfplumberは「じょうろ（プラスチック製）不燃」のように1語として読む。
    そのままでは区分の列に何も無い行になり、品目ごと消える。
    """
    split = []
    for w in words:
        # 長いものから当てる。「不燃」を「燃」と読むと、名前に「不」が残る。
        code = next(
            (
                c
                for c in sorted(CATEGORIES, key=len, reverse=True)
                if w["text"].endswith(c) and w["text"] != c
            ),
            None,
        )
        if code and item_x - 6 <= w["x0"] < cat_x - 3 and w["x1"] > cat_x + 3:
            split.append({**w, "text": w["text"][: -len(code)], "x1": cat_x - 3})
            # 区分は区分列の左端に置き直す。
            split.append({**w, "text": code, "x0": cat_x})
        else:
            split.append(w)
    return split


def extract_page(page):
    all_words = page.extract_words(use_text_flow=False, keep_blank_chars=False)
    table_bottom = find_table_bottom(all_words)
    boxes = find_boxes(page)
    entries = []

    for item_x, cat_x, note_x, end_x in BLOCKS:
        words = split_joined_kana_head(all_words, item_x)
        words = split_joined_category(words, item_x, cat_x)
        block = [
            w
            for w in words
            # 品目列の左には、かな行インデックス（あ・い・う…）が置かれている。
            # 少し左まで含めてから、後で1文字のかなを落とす。
            # 「（パソコンの）マウス」のように括弧で始まる品目は、ブロックの
            # 基準位置より少し左（-3程度）から始まる。一方でかな行の列は
            # さらに左（-15程度）にあるので、-6 で切れば両方を取り違えない。
            if item_x - 6 <= w["x0"] < end_x and not is_noise(w)
        ]
        if not block:
            continue

        # 五十音の「行」を示すかな1文字は、品目名の左の細い列に置かれている。
        # 品目名の列とは分かれているので、別に集めて行の切り替わりを拾う。
        kana_words = [
            w
            for w in words
            if item_x - 16 <= w["x0"] < item_x - 6
            and len(w["text"]) == 1
            and "ぁ" <= w["text"] <= "ん"
        ]

        # 品目名にはバッジの小さな文字を混ぜない。
        #
        # ただし大きさだけで落とすと品目ごと消える。欄に収まらない品目名は
        # 市が本文より小さい字で組んでいて（「カセットボンベ（カートリッジ式
        # ボンベ）」6.4pt、「マーガリン・バターの容器（プラスチック製）」5.7pt）、
        # バッジと同じ大きさになる。バッジは区分列の手前に寄せて置かれ、
        # 品目名は列の左から始まるので、位置で見分ける。
        item_words = [
            w
            for w in block
            if w["x0"] < cat_x - 3 and (is_body_text(w) or w["x0"] < cat_x - 20)
        ]
        cat_words = [w for w in block if cat_x - 3 <= w["x0"] < note_x - 3]
        # ブロックの右端には、ページをまたぐ縦書きの装飾帯が重なっていることがある。
        # 注意点の実データはブロック終端より十分内側に収まるので、手前で切る。
        note_words = [w for w in block if note_x - 3 <= w["x0"] < end_x - 12]

        item_rows = merge_wrapped_rows(cluster_rows(item_words))
        # 各品目行の代表topを先に出しておく。注意点は「この品目行から
        # 次の品目行の手前まで」に入るものを全部拾う（複数行になるため）。
        item_tops = [sum(w["top"] for w in r) / len(r) for r in item_rows]

        for index, row in enumerate(item_rows):
            top = item_tops[index]
            next_top = (
                item_tops[index + 1] if index + 1 < len(item_tops) else float("inf")
            )

            name = join_row(row)
            if not name:
                continue

            # この品目の行に、かな行の切り替わりが置かれているか。
            # 「石」「鏡」のような漢字だけの品目でも、市の表がどの行に置いたかが
            # 分かるので、読みを推測せずに五十音順を再現できる。
            kana_head = None
            for kw in kana_words:
                if abs(kw["top"] - top) <= 4:
                    kana_head = kw["text"]
                    break

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
                if top - 4 <= w["top"] < min(next_top - 4, table_bottom)
            ]
            note, marks = split_marks(join_note(note_parts))
            note = tidy_note_lines(note)

            # 枠はこのブロックの行をまるごと囲んでいる。品目名の高さが
            # 枠の中に入っていれば、その品目の枠。
            if any(
                box["x0"] - 2 <= item_x <= box["x1"]
                and box["top"] - 2 <= top <= box["bottom"]
                for box in boxes
            ):
                # 一覧の行には先頭の印だけが出る。10月からの変更は、いま
                # いちばん伝えたいことなので前に置く。
                marks.insert(0, BOX_MARK)

            entries.append(
                {
                    "name": name,
                    "kanaHead": kana_head,
                    "category": category_id,
                    "categoryLabel": category_label,
                    "note": note,
                    "marks": marks,
                }
            )
    return entries


# 注意点の中の「★2」「▶P9参照」は、冊子の脚注や別ページを指す印。
# 冊子を持たない利用者には意味が通らないので、本文から切り出して
# アプリ側で言葉にする（lib/domain/waste_note.dart）。
#
# ★は1〜6の1桁だけ。2桁で拾うと「★290㎝未満にしばる」（★2 と
# 「90㎝未満にしばる」）を ★29 と読み違える。
MARK_PATTERNS = (
    (re.compile(r"★[1-6１-６]"), "star"),
    (re.compile(r"▶?[PpＰ]([0-9０-９]{1,2})\s*参照"), "page"),
)


# 印だけでできた語。
MARK_ONLY = re.compile(r"(★[1-6１-６]|▶?[PpＰ][0-9０-９]{1,2}\s*参照)+")


def strip_marks(text: str) -> str:
    for pattern, _ in MARK_PATTERNS:
        text = pattern.sub("", text)
    return text


def to_ascii_digits(text):
    return text.translate(str.maketrans("０１２３４５６７８９", "0123456789"))


def split_marks(note):
    """注意点から印を切り出し、（本文, 印のid一覧）を返す。

    印は現れた順に並べ、同じものは1つにまとめる。
    """
    marks = []
    spans = []
    for pattern, kind in MARK_PATTERNS:
        for match in pattern.finditer(note):
            if kind == "star":
                mark = "star" + to_ascii_digits(match.group(0)[1:])
            else:
                mark = "page" + to_ascii_digits(match.group(1))
            spans.append((match.start(), match.end(), mark))

    for _, _, mark in sorted(spans):
        if mark not in marks:
            marks.append(mark)

    for start, end, _ in sorted(spans, reverse=True):
        note = note[:start] + note[end:]

    return note.strip(), marks


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

    # かな行のインデックスは「行が変わる最初の品目」にしか付いていないので、
    # 次の行が来るまで直前の値を引き継ぐ。表は五十音順に並んでいるため、
    # 抽出した順（＝表の並び順）のまま前から埋めていけばよい。
    current = None
    for e in all_entries:
        if e["kanaHead"]:
            current = e["kanaHead"]
        else:
            e["kanaHead"] = current

    # 同じ品目が複数ページに出ることはないが、念のため重複を除く
    seen = set()
    items = []
    for e in all_entries:
        key = (e["name"], e["category"])
        if key in seen:
            continue
        seen.add(key)
        items.append(e)

    # 表の並びは市が付けた読みの五十音順なので、抽出した順を崩さない。
    # 品目名で並べ直すとUnicodeのコードポイント順になり、「アイロン」の次に
    # 「アルバム」、その後ろに「油」と、読みと無関係な並びになる。
    # かな行だけを見て安定ソートすれば、複数ページにまたがった行（「あ」が
    # 1ページ目の末尾と2ページ目の先頭に分かれる等）を繋ぎつつ、
    # 行の中は表どおりの読み順が残る。
    kana_order = "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん"
    def kana_rank(e):
        head = e["kanaHead"] or ""
        return kana_order.index(head) if head in kana_order and head else len(kana_order)

    items.sort(key=kana_rank)

    missing = [e["name"] for e in items if not e["kanaHead"]]
    if missing:
        print(
            f"警告: かな行が取れなかった品目が{len(missing)}件あります: "
            f"{missing[:5]}",
            file=sys.stderr,
        )

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
