/// iOS 26 で導入された Liquid Glass デザインを適用するかの判定。
///
/// `Platform` を直接読む部分を引数に押し出し、OS バージョン文字列の多様な表記
/// （実機の `"Version 26.5 (Build 23F77)"` や `"26.0"` など）に対する判定を
/// 純粋な Dart の単体テストで検証できるようにする。
class LiquidGlassSupport {
  const LiquidGlassSupport._();

  /// Liquid Glass（`UIGlassEffect`）が導入された最初の iOS メジャーバージョン。
  static const minimumIosMajorVersion = 26;

  /// `Platform.operatingSystemVersion` の文字列からメジャーバージョンを取り出す。
  ///
  /// iOS の Dart VM は `"Version 26.5 (Build 23F77)"` のような文字列を返すが、
  /// 環境によっては `"26.0"` や `"iOS 26.1"` の形もあり得るため、最初の `<数値>.<数値>`
  /// （または単独の数値）からメジャー番号を読む。読めなければ null。
  static int? parseIosMajorVersion(String versionString) {
    final dotted = RegExp(r'(\d+)\.\d+').firstMatch(versionString);
    if (dotted != null) {
      return int.tryParse(dotted.group(1)!);
    }
    final plain = RegExp(r'\b(\d+)\b').firstMatch(versionString);
    if (plain != null) {
      return int.tryParse(plain.group(1)!);
    }
    return null;
  }

  /// 現在の実行環境が Liquid Glass の対象（iOS 26 以降）かどうか。
  ///
  /// プロジェクトの `IPHONEOS_DEPLOYMENT_TARGET` は 18.0 なので、iOS 18〜25 や
  /// Android では false になり、従来の Material 3 表示をそのまま保つ。
  static bool isSupported({
    required bool isIOS,
    required String operatingSystemVersion,
  }) {
    if (!isIOS) return false;
    final major = parseIosMajorVersion(operatingSystemVersion);
    return major != null && major >= minimumIosMajorVersion;
  }
}
