import 'package:shared_preferences/shared_preferences.dart';

/// アプリ内レビュー依頼の表示条件を判定・記録するためのリポジトリ。
///
/// レビュー依頼は、十分アプリを活用して価値を感じている利用者にのみ行い、
/// かつ過剰な頻度にならないよう制御する。
///
/// 【表示基準】
/// - 初回起動から14日以上経過していること
/// - 異なる日付で7日以上アプリを起動していること（放置された端末を除外）
/// - 前回のレビュー依頼から90日以上経過していること（クーリングオフ）
/// - 同一アプリバージョンでは最大1回のみ表示すること
class ReviewPromptRepository {
  const ReviewPromptRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _firstLaunchTimeKey = 'review_first_launch_time';
  static const _activeDatesKey = 'review_active_dates';
  static const _lastPromptTimeKey = 'review_last_prompt_time';
  static const _promptedVersionKey = 'review_prompted_version';

  static const int minimumDaysSinceFirstLaunch = 14;
  static const int minimumActiveDays = 7;
  static const int coolingOffDays = 90;

  static Future<ReviewPromptRepository> open() async =>
      ReviewPromptRepository(await SharedPreferences.getInstance());

  /// 起動日を記録する。
  ///
  /// 初回起動時刻が未記録なら現在時刻を記録し、
  /// 当日の日付文字列（yyyy-MM-dd）を起動日一覧に追加する。
  Future<void> recordLaunch({DateTime? now}) async {
    final current = now ?? DateTime.now();

    if (!_prefs.containsKey(_firstLaunchTimeKey)) {
      await _prefs.setInt(_firstLaunchTimeKey, current.millisecondsSinceEpoch);
    }

    final dateStr = _formatDate(current);
    final dates = _prefs.getStringList(_activeDatesKey) ?? <String>[];
    if (!dates.contains(dateStr)) {
      dates.add(dateStr);
      await _prefs.setStringList(_activeDatesKey, dates);
    }
  }

  /// レビュー依頼ダイアログを表示すべき条件を満たしているかを判定する。
  bool shouldRequestReview({required String currentVersion, DateTime? now}) {
    final current = now ?? DateTime.now();

    // 初回起動時刻の確認
    final firstLaunchMillis = _prefs.getInt(_firstLaunchTimeKey);
    if (firstLaunchMillis == null) return false;

    final firstLaunch = DateTime.fromMillisecondsSinceEpoch(firstLaunchMillis);
    if (current.difference(firstLaunch).inDays < minimumDaysSinceFirstLaunch) {
      return false;
    }

    // 累計起動日数の確認
    final activeDates = _prefs.getStringList(_activeDatesKey) ?? <String>[];
    if (activeDates.length < minimumActiveDays) {
      return false;
    }

    // 前回のレビュー依頼からの経過日数の確認（90日間のクーリングオフ）
    final lastPromptMillis = _prefs.getInt(_lastPromptTimeKey);
    if (lastPromptMillis != null) {
      final lastPrompt = DateTime.fromMillisecondsSinceEpoch(lastPromptMillis);
      if (current.difference(lastPrompt).inDays < coolingOffDays) {
        return false;
      }
    }

    // 同一バージョンでの重複表示防止
    final promptedVersion = _prefs.getString(_promptedVersionKey);
    if (promptedVersion == currentVersion) {
      return false;
    }

    return true;
  }

  /// レビュー依頼を実行したことを記録する。
  Future<void> markReviewPrompted({
    required String currentVersion,
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    await _prefs.setInt(_lastPromptTimeKey, current.millisecondsSinceEpoch);
    await _prefs.setString(_promptedVersionKey, currentVersion);
  }

  /// 記録された初回起動日時を取得する（主にテスト・デバッグ用）。
  DateTime? readFirstLaunchTime() {
    final millis = _prefs.getInt(_firstLaunchTimeKey);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// 記録されたアクティブ日の一覧を取得する（主にテスト・デバッグ用）。
  List<String> readActiveDates() =>
      _prefs.getStringList(_activeDatesKey) ?? <String>[];

  /// 最後にレビューを依頼した日時を取得する（主にテスト・デバッグ用）。
  DateTime? readLastPromptTime() {
    final millis = _prefs.getInt(_lastPromptTimeKey);
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// レビューを依頼したバージョンを取得する（主にテスト・デバッグ用）。
  String? readPromptedVersion() => _prefs.getString(_promptedVersionKey);

  static String _formatDate(DateTime dt) {
    final year = dt.year.toString().padLeft(4, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
