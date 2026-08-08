"""撮影した素のスクリーンショットに、案Bの装飾（上にコピー、下に画面）を当てる。

App Store一覧での見え方を作るためのもので、アプリ本体は変えない。
コピーの文言は STRIPS にまとめてあるので、ここだけ直せば作り直せる。
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "store_assets/screenshots/6.9-inch"
OUT = REPO / "store_assets/screenshots/6.9-inch-decorated"
FONT = REPO / "assets/fonts/NotoSansJP-Variable.ttf"

W, H = 1320, 2868
BAND = int(H * 0.27)          # 上の帯。ここにコピーを置く
CREAM = (252, 250, 245)       # アプリの地の色に合わせる
INK = (25, 28, 25)
GREEN = (47, 107, 79)         # アイコンと同じ緑
RADIUS = 40                   # 画面の上端の丸み
PAD_X = int(W * 0.08)

# 画面の上端にあるステータスバー（時刻・電波・電池）を落とす高さ。
# 帯のすぐ下にステータスバーが来ると、帯と二重の「上端」ができて
# 画面を貼り付けただけに見えるため、切って地続きに見せる。
STATUS_BAR = 170

# (元ファイル, コピー（改行は\nで）, 添え書き)
STRIPS = [
    ("00_onboarding.png", "郵便番号だけで\nすぐ使える", "地区を選ぶのは最初の一度きり"),
    ("00_home.png", "明日は何ごみ？", "開いた瞬間に分かる"),
    ("01_calendar.png", "今月の収集日が\nひと目で", "なぞって月をめくる"),
    ("02_dictionary.png", "443品目を\n五十音で探せる", "市の早見表がそのまま"),
    ("03_settings.png", "前日の夜に\nお知らせ", "出し忘れを防ぐ"),
]


def font(size, weight):
    f = ImageFont.truetype(str(FONT), size)
    f.set_variation_by_axes([weight])
    return f


def rounded_top_mask(size, radius):
    """上の角だけ丸いマスク。下は切り落とすので丸めない。"""
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle((0, 0, size[0], size[1] + radius), radius=radius, fill=255)
    return mask


def build(src_name, copy, sub):
    canvas = Image.new("RGB", (W, H), CREAM)

    # ── 下：画面。幅いっぱいに置き、帯からはみ出した下側は切る ──
    shot = Image.open(SRC / src_name).convert("RGB")
    if shot.size != (W, H):
        shot = shot.resize((W, H), Image.LANCZOS)
    visible_h = H - BAND
    shot = shot.crop((0, STATUS_BAR, W, STATUS_BAR + visible_h))
    canvas.paste(shot, (0, BAND), rounded_top_mask(shot.size, RADIUS))

    # 帯と画面の境目に、ごく薄い影を落として層を分ける
    shade = Image.new("RGBA", (W, 24), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    for i in range(24):
        a = int(26 * (1 - i / 24))
        sd.line([(0, 23 - i), (W, 23 - i)], fill=(25, 28, 25, a))
    canvas.paste(
        Image.alpha_composite(
            canvas.crop((0, BAND - 24, W, BAND)).convert("RGBA"), shade
        ).convert("RGB"),
        (0, BAND - 24),
    )

    # ── 上：コピー ──
    #
    # 縦位置は、行送りではなく実際に描かれる字面（textbbox）で決める。
    # Noto Sans JPは字面の上下に余白を持つので、行送りで計算すると
    # 見た目が上に寄る。
    draw = ImageDraw.Draw(canvas)
    copy_font = font(92, 800)
    sub_font = font(50, 600)

    lines = copy.split("\n")
    line_h = int(92 * 1.32)
    gap = 26

    def ink_top(text, f):
        """指定フォントで描いたときの、原点から字面の上端までの距離。"""
        return draw.textbbox((0, 0), text, font=f)[1]

    def ink_bottom(text, f):
        return draw.textbbox((0, 0), text, font=f)[3]

    # 1行目の字面の上端から、添え書きの字面の下端までを本文の高さとする。
    first_top = ink_top(lines[0], copy_font)
    last_baseline = line_h * (len(lines) - 1) + gap + line_h
    visual_h = last_baseline + ink_bottom(sub, sub_font) - first_top
    y = (BAND - visual_h) // 2 - first_top

    for line in lines:
        draw.text((PAD_X, y), line, font=copy_font, fill=INK)
        y += line_h
    draw.text((PAD_X, y + gap), sub, font=sub_font, fill=GREEN)

    return canvas


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for src_name, copy, sub in STRIPS:
        img = build(src_name, copy, sub)
        dest = OUT / src_name
        img.save(dest, "PNG")
        print(f"{dest.name}: {img.size[0]}x{img.size[1]}")


if __name__ == "__main__":
    main()
