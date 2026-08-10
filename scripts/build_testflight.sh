#!/bin/bash
# TestFlightに配信するビルドを作ってアップロードする。
#
# `flutter build ipa` を使わないのは、あれが自動署名を前提にしていて
# Xcodeにサインイン済みのアカウントを探しに行くため。CLIだけで完結させたいので、
# アーカイブまでをflutterに任せ、書き出しは手動署名で行う。
#
# 事前に必要なもの:
#   - 配布証明書 (Apple Distribution) がキーチェーンにあること
#   - 配布プロファイルが ~/Library/Developer/Xcode/UserData/Provisioning Profiles/
#     に入っていること (Xcodeで一度配信するか、App Store Connect APIで作る)
#   - App Store Connect APIキーが ~/.appstoreconnect/private_keys/ にあること
#
# 使い方: scripts/build_testflight.sh <issuer-id>
#   issuer IDは秘密情報なので、ファイルに書かず引数で渡す。

set -euo pipefail

ISSUER_ID="${1:-}"
if [ -z "$ISSUER_ID" ]; then
  echo "使い方: $0 <issuer-id>" >&2
  exit 1
fi

API_KEY_ID="G5TVPJHS7M"
TEAM_ID="R9DDB6ZX39"
BUNDLE_ID="io.github.ktakada42.saitamagomicalendar"
PROFILE_NAME="Saitama Gomi Calendar App Store"
# ホーム画面ウィジェットは別のバンドルなので、専用のプロファイルが要る。
# 書き忘れると「Provisioning profile ... doesn't match」で書き出しに失敗する。
WIDGET_BUNDLE_ID="$BUNDLE_ID.GomiWidget"
WIDGET_PROFILE_NAME="Saitama Gomi Widget App Store"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="$ROOT/build/ios/archive/Runner.xcarchive"
OUT="$ROOT/build/ios/testflight"

# pubspec.yamlのビルド番号。同じ番号は二度受け付けてもらえないので、
# 上げ忘れていないか先に見せる。
VERSION=$(grep '^version:' "$ROOT/pubspec.yaml" | sed 's/version: *//')
echo "==> $VERSION をビルドします"

# 署名ありでアーカイブする。--no-codesignだと、entitlements（App Group）が
# アーカイブに残らず、後から書き出しても署名に入らない。ウィジェットが
# 共有領域を読めなくなるので、ここで署名させる。
#
# Release構成は手動署名に固定してある（PROVISIONING_PROFILE_SPECIFIER）。
# 自動署名のままだと 'iOS Team Provisioning Profile: *' が選ばれ、
# App Groupを含まないためアーカイブが落ちる。
#
# 書き出しでflutterがコケるのは想定どおり（自前のExportOptionsに
# ウィジェットのプロファイルが無いため）。アーカイブさえできればよい。
flutter build ipa --release || true

if [ ! -d "$ARCHIVE" ]; then
  echo "アーカイブが作られなかった" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>$BUNDLE_ID</key>
    <string>$PROFILE_NAME</string>
    <key>$WIDGET_BUNDLE_ID</key>
    <string>$WIDGET_PROFILE_NAME</string>
  </dict>
  <key>uploadSymbols</key><true/>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST

echo "==> 書き出します"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT"

IPA=$(find "$OUT" -name '*.ipa' -maxdepth 1 | head -1)
echo "==> アップロードします: $IPA"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$API_KEY_ID" --apiIssuer "$ISSUER_ID"

echo "==> 完了。処理が終わるまで数分かかります。"
echo "    処理が終わればTestFlightの内部テストグループへ自動で配信されます。"
