import Flutter
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // ごみ収集の前夜通知（flutter_local_notifications）を、アプリを開いている間にも
    // 表示できるようにする。設定しないと、前面にいる間は通知が出ない。
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerWidgetChannel(engineBridge.pluginRegistry)
  }

  /// ホーム画面ウィジェットに収集日を渡す口。
  ///
  /// ウィジェットは別プロセスなので、Flutter側の保存領域からは読めない。
  /// App Groupで共有した領域に書き、書いたらウィジェットに再描画を促す。
  /// 収集日の計算そのものはDart側で済ませてあり、ここは受け取ったJSONを
  /// そのまま置くだけ（lib/data/widget_bridge.dart と対応）。
  private func registerWidgetChannel(_ registry: FlutterPluginRegistry) {
    guard let messenger = registry.registrar(forPlugin: "GomiWidgetChannel")?.messenger()
    else { return }

    let channel = FlutterMethodChannel(
      name: "io.github.ktakada42.saitamagomicalendar/widget",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      let defaults = UserDefaults(suiteName: Self.appGroupId)
      guard let defaults else {
        // App Groupが有効でない（entitlementが無い等）。ウィジェットを
        // 更新できないだけなので、アプリ本体は動き続けてよい。
        result(FlutterError(code: "no_app_group", message: nil, details: nil))
        return
      }

      switch call.method {
      case "update":
        guard let json = call.arguments as? String else {
          result(FlutterError(code: "bad_argument", message: nil, details: nil))
          return
        }
        defaults.set(json, forKey: Self.payloadKey)
      case "clear":
        defaults.removeObject(forKey: Self.payloadKey)
      default:
        result(FlutterMethodNotImplemented)
        return
      }

      if #available(iOS 14.0, *) {
        WidgetCenter.shared.reloadAllTimelines()
      }
      result(nil)
    }
  }

  private static let appGroupId = "group.io.github.ktakada42.saitamagomicalendar"
  private static let payloadKey = "widget_payload"
}
