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
# Xcode 15 以降の Single Size (1024x1024) 方式。各サイズはビルド時に actool が生成する。
render 1024 "Icon-App-1024x1024@1x.png"
echo "  Icon-App-1024x1024@1x.png (1024x1024)"

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

ios_names = ["Icon-App-1024x1024@1x.png"]
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

echo "== iOS Dark / Tinted バリアントを生成 =="
swift "$repo_root/design/generate_ios_appearances.swift"

echo "完了。ios/ と android/ 配下のアイコンを更新しました。"
