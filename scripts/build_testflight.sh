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

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="$ROOT/build/ios/archive/Runner.xcarchive"
OUT="$ROOT/build/ios/testflight"

# pubspec.yamlのビルド番号。同じ番号は二度受け付けてもらえないので、
# 上げ忘れていないか先に見せる。
VERSION=$(grep '^version:' "$ROOT/pubspec.yaml" | sed 's/version: *//')
echo "==> $VERSION をビルドします"

# --no-codesignにしているのは、この後の書き出しで署名し直すため。
flutter build ipa --release --no-codesign

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
