#!/usr/bin/env bash
# design/app_icon_master.svg から iOS/Android のアプリアイコン一式を生成する。
#
# OSのマスク処理に合わせて、書き出すPNGは角丸なしの正方形フルブリード
# （マスターSVG自体が角丸を持たない）。iOSのアイコンはアルファチャンネルを
# 持たないことが要件（1024pxのマーケティング用アイコンは特に必須）なので、
# 生成後にPillowでRGBへ変換しアルファを落とす。
#
# 必要なもの: rsvg-convert（`brew install librsvg`）、Python3 + Pillow
#
# 使い方: bash design/generate_app_icons.sh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
master="$repo_root/design/app_icon_master.svg"
ios_dir="$repo_root/ios/Runner/Assets.xcassets/AppIcon.appiconset"
android_res="$repo_root/android/app/src/main/res"

command -v rsvg-convert >/dev/null || { echo "rsvg-convert が見つかりません。'brew install librsvg' を実行してください。" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

render() {
  local size="$1" out="$2"
  rsvg-convert -w "$size" -h "$size" "$master" -o "$tmp/$(basename "$out")"
}

echo "== iOS =="
# Contents.json のfilenameとサイズの対応（$repo_root/ios/.../Contents.json 参照）
declare -a ios_map=(
  "20:Icon-App-20x20@1x.png"
  "40:Icon-App-20x20@2x.png"
  "60:Icon-App-20x20@3x.png"
  "29:Icon-App-29x29@1x.png"
  "58:Icon-App-29x29@2x.png"
  "87:Icon-App-29x29@3x.png"
  "40:Icon-App-40x40@1x.png"
  "80:Icon-App-40x40@2x.png"
  "120:Icon-App-40x40@3x.png"
  "120:Icon-App-60x60@2x.png"
  "180:Icon-App-60x60@3x.png"
  "76:Icon-App-76x76@1x.png"
  "152:Icon-App-76x76@2x.png"
  "167:Icon-App-83.5x83.5@2x.png"
  "1024:Icon-App-1024x1024@1x.png"
)
for entry in "${ios_map[@]}"; do
  size="${entry%%:*}"
  name="${entry#*:}"
  render "$size" "$name"
  echo "  $name (${size}x${size})"
done

echo "== Android =="
declare -a android_map=(
  "48:mipmap-mdpi"
  "72:mipmap-hdpi"
  "96:mipmap-xhdpi"
  "144:mipmap-xxhdpi"
  "192:mipmap-xxxhdpi"
)
for entry in "${android_map[@]}"; do
  size="${entry%%:*}"
  dir="${entry#*:}"
  render "$size" "ic_launcher_${dir}.png"
  echo "  $dir/ic_launcher.png (${size}x${size})"
done

echo "== アルファチャンネルを落として配置 =="
python3 - "$tmp" "$ios_dir" "$android_res" <<'PYEOF'
import sys
from pathlib import Path
from PIL import Image

tmp, ios_dir, android_res = (Path(p) for p in sys.argv[1:4])

ios_names = [
    "Icon-App-20x20@1x.png", "Icon-App-20x20@2x.png", "Icon-App-20x20@3x.png",
    "Icon-App-29x29@1x.png", "Icon-App-29x29@2x.png", "Icon-App-29x29@3x.png",
    "Icon-App-40x40@1x.png", "Icon-App-40x40@2x.png", "Icon-App-40x40@3x.png",
    "Icon-App-60x60@2x.png", "Icon-App-60x60@3x.png",
    "Icon-App-76x76@1x.png", "Icon-App-76x76@2x.png",
    "Icon-App-83.5x83.5@2x.png", "Icon-App-1024x1024@1x.png",
]
for name in ios_names:
    im = Image.open(tmp / name).convert("RGB")
    im.save(ios_dir / name)

android_dirs = ["mipmap-mdpi", "mipmap-hdpi", "mipmap-xhdpi", "mipmap-xxhdpi", "mipmap-xxxhdpi"]
for d in android_dirs:
    im = Image.open(tmp / f"ic_launcher_{d}.png").convert("RGB")
    out_dir = android_res / d
    out_dir.mkdir(parents=True, exist_ok=True)
    im.save(out_dir / "ic_launcher.png")

print("done")
PYEOF

echo "完了。ios/ と android/ 配下のアイコンを更新しました。"
