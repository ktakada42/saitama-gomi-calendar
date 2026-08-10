import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'data/area_catalog.dart';
import 'data/notification_repository.dart';
import 'data/settings_repository.dart';
import 'data/widget_bridge.dart';
import 'data/waste_dictionary.dart';
import 'domain/not_accepted_guide.dart';
import 'domain/oversized_guide.dart';
import 'domain/collection_area.dart';
import 'domain/collection_calendar.dart';
import 'domain/collection_reminder.dart';
import 'domain/widget_payload.dart';

final settingsRepositoryProvider = FutureProvider<SettingsRepository>(
  (ref) => SettingsRepository.open(),
);

final notificationRepositoryProvider = FutureProvider<NotificationRepository>(
  (ref) => NotificationRepository.open(),
);

final areaCatalogProvider = FutureProvider<AreaCatalog>(
  (ref) => AreaCatalog.load(),
);

/// アプリのバージョン。「このアプリについて」で出す。
///
/// pubspec.yamlの値を埋め込むのではなく、実際にインストールされている
/// パッケージから読む。手元のソースではなく、その端末に入っているものが
/// どれなのかを知りたいため。
final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

/// 品目から出し先を引く分別早見表。
final wasteDictionaryProvider = FutureProvider<WasteDictionary>(
  (ref) => WasteDictionary.load(),
);

/// 粗大ごみの料金と申込み方法。早見表には金額も窓口も書かれていない。
final oversizedGuideProvider = FutureProvider<OversizedGuide>(
  (ref) => OversizedGuide.load(),
);

/// 市では収集・処理できないものの持って行き先。
final notAcceptedGuideProvider = FutureProvider<NotAcceptedGuide>(
  (ref) => NotAcceptedGuide.load(),
);

/// 設定済みの地区。null は「まだ設定していない」＝初回起動。
class SelectedArea extends AsyncNotifier<CollectionArea?> {
  @override
  Future<CollectionArea?> build() async {
    final repository = await ref.watch(settingsRepositoryProvider.future);
    return repository.readArea();
  }

  Future<void> save(CollectionArea area) async {
    final repository = await ref.read(settingsRepositoryProvider.future);
    await repository.writeArea(area);
    state = AsyncData(area);
  }

  Future<void> clear() async {
    final repository = await ref.read(settingsRepositoryProvider.future);
    await repository.clear();
    state = const AsyncData(null);
  }
}

final selectedAreaProvider =
    AsyncNotifierProvider<SelectedArea, CollectionArea?>(SelectedArea.new);

/// 外観設定（ライト／ダーク／システム）。デフォルトはライトモード。
class ThemeModeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    final repository = await ref.watch(settingsRepositoryProvider.future);
    return repository.readThemeMode();
  }

  Future<void> save(ThemeMode mode) async {
    final repository = await ref.read(settingsRepositoryProvider.future);
    await repository.writeThemeMode(mode);
    state = AsyncData(mode);
  }
}

final themeModeProvider = AsyncNotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

/// 今日の日付（時刻は落としてある）。
///
/// `DateTime.now()` を画面から直接呼ばずここに集約しておくと、
/// テストで `overrideWithValue` して任意の日付の表示を確認できる。
final todayProvider = Provider<DateTime>(
  (ref) => CollectionCalendar.dateOnly(ref.watch(nowProvider)),
);

/// 時刻まで含めた現在時刻。
///
/// 「その日のごみをまだ出せるか」は時刻で決まるので、日付だけでは足りない。
/// [todayProvider] と同じく、テストから差し替えられるようにここに集約する。
final nowProvider = Provider<DateTime>((ref) => DateTime.now());

/// 設定済み地区のカレンダー。地区が未設定なら null。
final calendarProvider = Provider<CollectionCalendar?>((ref) {
  final area = ref.watch(selectedAreaProvider).value;
  return area == null ? null : CollectionCalendar(area);
});

/// 収集日前夜の通知の設定と、OSへの予約。
///
/// 通知は差分更新せず、設定や地区が変わるたびに全部張り直す。
/// 古い予約が残らないので、状態のずれを考えなくて済む
/// （[docs/next-phase.md] B.3節）。
class NotificationController extends AsyncNotifier<NotificationSettings> {
  @override
  Future<NotificationSettings> build() async {
    final repository = await ref.watch(settingsRepositoryProvider.future);
    final settings = repository.readNotificationSettings();
    // 地区が変わったら、その地区の曜日で通知を張り直す必要がある。
    ref.listen(selectedAreaProvider, (_, _) => _resyncQuietly());
    return settings;
  }

  /// 通知をONにする。許可が取れなければ false を返し、設定は変えない。
  Future<bool> enable() async {
    final notifications = await ref.read(notificationRepositoryProvider.future);
    final granted = await notifications.requestPermission();
    if (!granted) return false;

    final current = state.value ?? const NotificationSettings.defaults();
    await _save(current.copyWith(enabled: true));
    return true;
  }

  Future<void> disable() async {
    final current = state.value ?? const NotificationSettings.defaults();
    await _save(current.copyWith(enabled: false));
  }

  Future<void> setTime(Duration timeOfDay) async {
    final current = state.value ?? const NotificationSettings.defaults();
    await _save(current.copyWith(timeOfDay: timeOfDay));
  }

  Future<void> _save(NotificationSettings settings) async {
    final repository = await ref.read(settingsRepositoryProvider.future);
    await repository.writeNotificationSettings(settings);
    state = AsyncData(settings);
    await _resync(settings);
  }

  /// 通知の予約を、いまの設定・地区に合わせて張り直す。
  Future<void> _resync(NotificationSettings settings) async {
    final notifications = await ref.read(notificationRepositoryProvider.future);
    final calendar = ref.read(calendarProvider);

    if (!settings.enabled || calendar == null) {
      await notifications.cancelAll();
      return;
    }
    final reminders = CollectionReminderPlanner(
      calendar,
    ).plan(from: DateTime.now(), notifyAt: settings.timeOfDay);
    await notifications.reschedule(reminders);
  }

  /// 地区の変更など、利用者の操作以外の理由で張り直すとき用。
  /// 失敗しても画面には出さない（通知が出ないだけで、アプリの利用は続けられる）。
  Future<void> _resyncQuietly() async {
    final settings = state.value;
    if (settings == null) return;
    try {
      await _resync(settings);
    } on Exception {
      // 通知の予約に失敗しても、収集日の確認という主目的は妨げない。
    }
  }
}

final notificationProvider =
    AsyncNotifierProvider<NotificationController, NotificationSettings>(
      NotificationController.new,
    );

/// ホーム画面ウィジェットへの書き出し口。テストからは差し替える。
final widgetBridgeProvider = Provider<WidgetBridge>(
  (ref) => WidgetBridge.create(),
);

/// 地区が変わるたびに、ホーム画面ウィジェットの内容を書き直す。
///
/// ウィジェットはアプリが起動していなくても表示され続けるので、
/// 「アプリを開いたとき」に先の分までまとめて渡しておく。
/// 日付が変わったときの切り替えはウィジェット側が自分で行う
/// （WidgetPayloadに複数日ぶん入っている）。
class WidgetSync {
  const WidgetSync(this._bridge);

  final WidgetBridge _bridge;

  Future<void> sync(CollectionCalendar? calendar, DateTime now) async {
    if (calendar == null || calendar.area.isEmpty) {
      await _bridge.clear();
      return;
    }
    await _bridge.update(WidgetPayload.build(calendar, now));
  }
}

final widgetSyncProvider = Provider<WidgetSync>(
  (ref) => WidgetSync(ref.watch(widgetBridgeProvider)),
);
