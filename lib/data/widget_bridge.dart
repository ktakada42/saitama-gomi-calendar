import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/widget_payload.dart';

/// ホーム画面ウィジェットに内容を渡す口。
///
/// iOSのウィジェットはアプリとは別のプロセスなので、通常の
/// `shared_preferences` では読めない。App Groupで共有した領域に書き、
/// ウィジェット側からはそこを読む。書き込みと再描画の指示は
/// ネイティブ側（AppDelegate.swift）に頼む。
///
/// ウィジェットテストではプラットフォームチャネルが動かないので、
/// テストからは[NoopWidgetBridge]に差し替える。
abstract class WidgetBridge {
  /// 内容を共有領域に書き、ウィジェットに再描画を促す。
  Future<void> update(WidgetPayload payload);

  /// 地区が未設定に戻ったときなど、出すものが無くなったとき。
  Future<void> clear();

  static WidgetBridge create() => const _MethodChannelWidgetBridge();
}

/// 何もしない実装。テストで使う。
class NoopWidgetBridge implements WidgetBridge {
  const NoopWidgetBridge();

  @override
  Future<void> update(WidgetPayload payload) async {}

  @override
  Future<void> clear() async {}
}

class _MethodChannelWidgetBridge implements WidgetBridge {
  const _MethodChannelWidgetBridge();

  static const _channel = MethodChannel(
    'io.github.ktakada42.saitamagomicalendar/widget',
  );

  @override
  Future<void> update(WidgetPayload payload) =>
      _invoke('update', jsonEncode(payload.toJson()));

  @override
  Future<void> clear() => _invoke('clear', null);

  /// ウィジェットの更新に失敗しても、アプリ本体の動作は止めない。
  ///
  /// ウィジェットが古いままになるだけで、収集日を確認するという主目的は
  /// 妨げられない。Androidや、App Groupを持たない環境でも動くようにする。
  Future<void> _invoke(String method, String? argument) async {
    try {
      await _channel.invokeMethod<void>(method, argument);
    } on MissingPluginException {
      // このプラットフォームには実装が無い（Android・テスト環境など）。
    } on PlatformException {
      // 共有領域に書けなかった。次にアプリを開いたときに書き直される。
    }
  }
}
