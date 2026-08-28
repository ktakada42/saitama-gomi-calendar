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
#     （AuthKey_<KEY_ID>.p8 の形で置く）
#
#   - issuer IDが ~/.appstoreconnect/issuers にあること
#     （`<key-id> <issuer-id>` を1行ずつ。引数や環境変数でも渡せる）
#
# 使い方:
#   scripts/build_testflight.sh [issuer-id] [key-id]
#
# issuer IDとkey IDはこのリポジトリの持ち主に固有の値なので、公開リポジトリには
# 書かない。ただし毎回ブラウザで調べ直すのも無駄なので、手元の
# ~/.appstoreconnect/ に置いて、そこから拾う。どちらもふだんは省略してよい。
#
#   key ID    : private_keys/ に鍵が1つだけならファイル名から拾う
#   issuer ID : issuers ファイルの、そのkey IDの行から拾う
#
# 引数 > 環境変数 (ASC_ISSUER_ID / ASC_KEY_ID) > ファイル の順に優先する。
#
# issuer IDは秘密ではない（App Store ConnectのKeysページに平文で出るUUIDで、
# .p8 秘密鍵が無ければJWTを署名できず何もできない）。平文で置いてよい。
# 秘密なのは private_keys/*.p8 のほうだけ。

set -euo pipefail

ASC_DIR="$HOME/.appstoreconnect"
KEYS_DIR="$ASC_DIR/private_keys"
ISSUERS_FILE="$ASC_DIR/issuers"

# issuer IDはkey IDごとに引くので、key IDを先に決める。
API_KEY_ID="${2:-${ASC_KEY_ID:-}}"
if [ -z "$API_KEY_ID" ]; then
  # AuthKey_XXXX.p8 が1つだけならファイル名から拾う。
  # 複数あると取り違えるので、その場合は明示させる。
  found=("$KEYS_DIR"/AuthKey_*.p8)
  if [ "${#found[@]}" -eq 1 ] && [ -e "${found[0]}" ]; then
    API_KEY_ID="$(basename "${found[0]}" .p8)"
    API_KEY_ID="${API_KEY_ID#AuthKey_}"
  else
    echo "APIキーを特定できません。key-id を渡すか ASC_KEY_ID を設定してください。" >&2
    echo "  探した場所: $KEYS_DIR" >&2
    exit 1
  fi
fi

ISSUER_ID="${1:-${ASC_ISSUER_ID:-}}"
if [ -z "$ISSUER_ID" ] && [ -f "$ISSUERS_FILE" ]; then
  # `<key-id> <issuer-id>` の並び。'#' 以降はコメント。
  ISSUER_ID=$(awk -v k="$API_KEY_ID" '
    { sub(/#.*/, "") }
    $1 == k { print $2; exit }
  ' "$ISSUERS_FILE")
fi
if [ -z "$ISSUER_ID" ]; then
  echo "issuer IDが分かりません。次のどれかで渡してください:" >&2
  echo "  1. $ISSUERS_FILE に1行足す: $API_KEY_ID  <issuer-id>" >&2
  echo "  2. 環境変数 ASC_ISSUER_ID を設定する" >&2
  echo "  3. 引数で渡す: $0 <issuer-id>" >&2
  echo "  調べる場所: https://appstoreconnect.apple.com/access/integrations/api" >&2
  exit 1
fi

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
LEDGER="$ROOT/store_assets/app_store/BUILDS.md"

# pubspec.yamlのビルド番号。同じ番号は二度受け付けてもらえないので、
# 上げ忘れていないか先に見せる。
VERSION=$(grep '^version:' "$ROOT/pubspec.yaml" | sed 's/version: *//')
echo "==> $VERSION をビルドします"

# ビルドする瞬間のコミットと作業ツリーの状態を控える。ビルドが終われば
# git statusは失われ、あとから「どのコミットから作ったか」を突き止める
# 手立てがなくなるため（v1.1.1のビルド23で実際に迷った）。
GIT_SHA=$(git -C "$ROOT" rev-parse HEAD)
GIT_SHORT_SHA=$(git -C "$ROOT" rev-parse --short HEAD)
DIRTY_FILES=$(git -C "$ROOT" status --porcelain)
if [ -n "$DIRTY_FILES" ]; then
  DIRTY_COUNT=$(echo "$DIRTY_FILES" | wc -l | tr -d ' ')
  WORKTREE_STATE="dirty（${DIRTY_COUNT}件）"
  echo "==> 作業ツリーがdirty（${DIRTY_COUNT}件）。$LEDGER には元のSHAとして"
  echo "    ${GIT_SHORT_SHA} を記録するが、これは基点であって全内容ではない。"
  echo "    あとで対応するコミットができたら「対応するコミット」列を埋めること。"
else
  WORKTREE_STATE="clean"
fi

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
# 出力をtee経由でも残す。Delivery UUIDを記録に拾うため。
# pipefailが効いているので、altoolが失敗すればここで止まる。
ALTOOL_LOG="$OUT/altool.log"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$API_KEY_ID" --apiIssuer "$ISSUER_ID" 2>&1 | tee "$ALTOOL_LOG"
DELIVERY_UUID=$(grep -oE 'Delivery UUID: [0-9a-f-]+' "$ALTOOL_LOG" | awk '{print $3}' || true)
DELIVERY_UUID="${DELIVERY_UUID:-不明}"

# ビルドとコミットの対応を記録に残す。「対応するコミット」列だけは手で埋める
# （dirtyなビルドが最終的にどのコミットになったかは、ビルドした時点では
# まだ分からないため）。詳しくは store_assets/app_store/BUILDS.md を参照。
REPO_URL="https://github.com/ktakada42/saitama-gomi-calendar"
printf '| %s | %s | [`%s`](%s/commit/%s) | %s | – | `%s` |\n' \
  "$VERSION" "$(date '+%Y-%m-%d %H:%M')" "$GIT_SHORT_SHA" "$REPO_URL" "$GIT_SHA" \
  "$WORKTREE_STATE" "$DELIVERY_UUID" >> "$LEDGER"

echo "==> 完了。処理が終わるまで数分かかります。"
echo "    処理が終わればTestFlightの内部テストグループへ自動で配信されます。"
echo "==> $LEDGER に記録した。対応するコミットが決まったら手で埋めること。"
