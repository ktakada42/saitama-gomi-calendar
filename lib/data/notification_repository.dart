import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/collection_reminder.dart';

/// 収集日前夜の通知を、OSの通知センターに予約する。
///
/// `CollectionReminderPlanner`が「いつ何を通知するか」を決め、こちらは
/// それをOSに渡すことだけを担う。ここにはごみ収集のルールを持たない。
///
/// 通知はすべて端末内で完結する（サーバーとは通信しない）。
///
/// ウィジェットテストではOSの通知プラグインを初期化できないため、
/// テストからは[NoopNotificationRepository]に差し替える
/// （[docs/next-phase.md] B.4節）。
abstract class NotificationRepository {
  /// 通知の許可を求める。許可されたら true。
  Future<bool> requestPermission();

  /// 予約済みの通知をすべて消してから、[reminders]を予約し直す。
  Future<void> reschedule(List<CollectionReminder> reminders);

  Future<void> cancelAll();

  static Future<NotificationRepository> open() =>
      _PluginNotificationRepository.open();
}

/// 何もしない実装。テストで使う。
class NoopNotificationRepository implements NotificationRepository {
  const NoopNotificationRepository();

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> reschedule(List<CollectionReminder> reminders) async {}

  @override
  Future<void> cancelAll() async {}
}

class _PluginNotificationRepository implements NotificationRepository {
  _PluginNotificationRepository(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channelId = 'collection_reminder';
  static const _channelName = 'ごみ収集のお知らせ';
  static const _channelDescription = '翌日に出せるごみを前夜にお知らせします';

  static Future<NotificationRepository> open() async {
    tz_data.initializeTimeZones();
    // 日本国内向けのアプリなので固定でよい。端末のタイムゾーンを見に行くと
    // flutter_timezone等の追加依存が必要になるうえ、日本以外で使う想定もない。
    tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(
          // 許可を求めるのは利用者が通知をONにしたときなので、起動時には求めない。
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    return _PluginNotificationRepository(plugin);
  }

  /// iOSでは一度拒否されると再度ダイアログは出せない（設定アプリから
  /// 変えてもらうしかない）ので、呼び出し側は false のときに案内を出す。
  @override
  Future<bool> requestPermission() async {
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return false;
  }

  /// 差分更新ではなく毎回全部張り直すのは、地区や通知時刻を変えたときに
  /// 古い予約が残らないようにするため（[docs/next-phase.md] B.3節）。
  @override
  Future<void> reschedule(List<CollectionReminder> reminders) async {
    await cancelAll();
    for (final reminder in reminders) {
      await _plugin.zonedSchedule(
        id: reminder.id,
        title: 'ごみ収集のお知らせ',
        body: reminder.body,
        scheduledDate: tz.TZDateTime.from(reminder.scheduledAt, tz.local),
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(),
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.defaultImportance,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}
