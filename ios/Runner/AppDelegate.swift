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
    registerLiquidGlassViews(engineBridge.pluginRegistry)
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

  /// iOS 26 以降の Liquid Glass コンポーネント（UIGlassEffect 面・純正 UITabBar）を登録する。
  private func registerLiquidGlassViews(_ registry: FlutterPluginRegistry) {
    if let surfaceRegistrar = registry.registrar(forPlugin: "LiquidGlassSurfacePlugin") {
      surfaceRegistrar.register(
        LiquidGlassSurfaceFactory(messenger: surfaceRegistrar.messenger()),
        withId: "io.github.ktakada42.saitamagomicalendar/liquid_glass_surface"
      )
    }
    if let tabBarRegistrar = registry.registrar(forPlugin: "LiquidGlassTabBarPlugin") {
      tabBarRegistrar.register(
        LiquidGlassTabBarFactory(messenger: tabBarRegistrar.messenger()),
        withId: "io.github.ktakada42.saitamagomicalendar/liquid_glass_tab_bar"
      )
    }
  }

  private static let appGroupId = "group.io.github.ktakada42.saitamagomicalendar"
  private static let payloadKey = "widget_payload"
}

// MARK: - Liquid Glass 共通ユーティリティ

private enum LiquidGlassColor {
  /// Dart の `Color.toARGB32()` から渡された整数値を `UIColor` に変換する。
  static func fromARGB(_ raw: Int) -> UIColor {
    let bits = UInt32(bitPattern: Int32(truncatingIfNeeded: raw))
    let a = CGFloat((bits >> 24) & 0xFF) / 255.0
    let r = CGFloat((bits >> 16) & 0xFF) / 255.0
    let g = CGFloat((bits >> 8) & 0xFF) / 255.0
    let b = CGFloat(bits & 0xFF) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: a)
  }
}

// MARK: - Liquid Glass Surface (UIVisualEffectView + UIGlassEffect)

private struct GlassSurfaceParams {
  var style: String = "regular"
  var interactive: Bool = false
  var shape: String = "capsule"
  var cornerRadius: Double = 24.0
  var tintColor: Int?
  var isDark: Bool = false

  init(dictionary: [String: Any]?) {
    guard let dict = dictionary else { return }
    if let s = dict["style"] as? String { style = s }
    if let i = dict["interactive"] as? Bool { interactive = i }
    if let sh = dict["shape"] as? String { shape = sh }
    if let r = (dict["cornerRadius"] as? NSNumber)?.doubleValue { cornerRadius = r }
    if let t = (dict["tintColor"] as? NSNumber)?.intValue { tintColor = t }
    if let d = dict["isDark"] as? Bool { isDark = d }
  }
}

private final class GlassSurfaceHostView: UIView {
  let effectView = UIVisualEffectView()

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    // 背景用のガラス面なので、タッチは常に上層の Flutter ウィジェットへ通す。
    isUserInteractionEnabled = false

    effectView.frame = bounds
    effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    effectView.backgroundColor = .clear
    addSubview(effectView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

private final class LiquidGlassSurfacePlatformView: NSObject, FlutterPlatformView {
  private let hostView: GlassSurfaceHostView
  private let channel: FlutterMethodChannel

  init(
    frame: CGRect,
    viewId: Int64,
    arguments: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    hostView = GlassSurfaceHostView(frame: frame)
    channel = FlutterMethodChannel(
      name: "io.github.ktakada42.saitamagomicalendar/liquid_glass_surface_\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    apply(GlassSurfaceParams(dictionary: arguments as? [String: Any]), animated: false)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      if call.method == "update" {
        let params = GlassSurfaceParams(dictionary: call.arguments as? [String: Any])
        self.apply(params, animated: true)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView {
    hostView
  }

  private func apply(_ params: GlassSurfaceParams, animated: Bool) {
    let work = {
      self.hostView.overrideUserInterfaceStyle = params.isDark ? .dark : .light
      if #available(iOS 26.0, *) {
        let style: UIGlassEffect.Style = (params.style == "clear") ? .clear : .regular
        let glass = UIGlassEffect(style: style)
        glass.isInteractive = params.interactive
        if let argb = params.tintColor {
          glass.tintColor = LiquidGlassColor.fromARGB(argb)
        }
        self.hostView.effectView.effect = glass
        switch params.shape {
        case "rounded":
          self.hostView.effectView.cornerConfiguration = .corners(
            radius: .fixed(params.cornerRadius)
          )
        case "topRounded":
          self.hostView.effectView.cornerConfiguration = .uniformTopRadius(
            .fixed(params.cornerRadius)
          )
        default:
          self.hostView.effectView.cornerConfiguration = .capsule()
        }
      } else {
        self.hostView.effectView.effect = UIBlurEffect(style: .systemChromeMaterial)
        self.hostView.effectView.clipsToBounds = true
        self.hostView.effectView.layer.cornerRadius =
          params.shape == "capsule"
          ? min(self.hostView.bounds.width, self.hostView.bounds.height) / 2
          : CGFloat(params.cornerRadius)
      }
    }

    if animated {
      UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: work)
    } else {
      work()
    }
  }
}

private final class LiquidGlassSurfaceFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    LiquidGlassSurfacePlatformView(
      frame: frame,
      viewId: viewId,
      arguments: args,
      messenger: messenger
    )
  }
}

// MARK: - Liquid Glass TabBar (純正 UITabBarController)

private final class TabBarPassthroughContainerView: UIView {
  weak var managedTabBar: UITabBar?
  var isTouchEnabled: Bool = true
  var onCapsuleRectChanged: ((CGRect) -> Void)?
  private var lastReportedRect: CGRect = .zero

  /// iOS 26 の浮遊カプセル部分の矩形（このビュー座標系）を返す。
  ///
  /// `UITabBar` 自身の `bounds` は画面横幅いっぱい（左右余白込み）を持つため、
  /// `tabBar.hitTest` だけだと左右の余白でも `tabBar` 自身が返ってしまう。
  /// 実際のガラスカプセル部分だけを当たり判定の対象にする。
  func capsuleRect() -> CGRect {
    guard bounds.width > 0, bounds.height > 0 else { return .zero }
    if let tabBar = managedTabBar {
      // iOS 26 の UITabBar 内部にある左右インセット済みのカプセル背景ビューを探す。
      for sub in tabBar.subviews {
        let w = sub.frame.width
        let h = sub.frame.height
        if w > tabBar.bounds.width * 0.5,
           w < tabBar.bounds.width - 16,
           h >= 44,
           h <= 76 {
          return convert(sub.frame, from: tabBar)
        }
      }
    }
    let bottomSafe = safeAreaInsets.bottom
    let bottomMargin = bottomSafe > 0 ? max(12.0, bottomSafe - 13.0) : 12.0
    let capsuleHeight: CGFloat = 62.0
    let y = max(0.0, bounds.height - bottomMargin - capsuleHeight)
    return CGRect(
      x: 20.0,
      y: y,
      width: max(0.0, bounds.width - 40.0),
      height: min(capsuleHeight, bounds.height - y)
    )
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.managedTabBar?.layoutIfNeeded()
      let rect = self.capsuleRect()
      if !rect.equalTo(self.lastReportedRect) {
        self.lastReportedRect = rect
        self.onCapsuleRectChanged?(rect)
      }
    }
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard isTouchEnabled,
          let tabBar = managedTabBar,
          !tabBar.isHidden,
          tabBar.alpha > 0.01,
          capsuleRect().contains(point)
    else {
      return nil
    }
    let pointInTabBar = convert(point, to: tabBar)
    if tabBar.bounds.contains(pointInTabBar),
       let hit = tabBar.hitTest(pointInTabBar, with: event) {
      return hit
    }
    return nil
  }
}

private final class LiquidGlassTabBarPlatformView: NSObject, FlutterPlatformView, UITabBarControllerDelegate {
  private let containerView: TabBarPassthroughContainerView
  private let tabBarController: UITabBarController
  private let channel: FlutterMethodChannel

  init(
    frame: CGRect,
    viewId: Int64,
    arguments: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    containerView = TabBarPassthroughContainerView(frame: frame)
    containerView.backgroundColor = .clear
    containerView.isOpaque = false

    tabBarController = UITabBarController()
    channel = FlutterMethodChannel(
      name: "io.github.ktakada42.saitamagomicalendar/liquid_glass_tab_bar_\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    setupTabBar()
    apply(arguments as? [String: Any])

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      if call.method == "update" {
        self.apply(call.arguments as? [String: Any])
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView {
    containerView
  }

  private func setupTabBar() {
    let items: [(title: String, symbol: String, selectedSymbol: String)] = [
      ("ホーム", "house", "house.fill"),
      ("カレンダー", "calendar", "calendar"),
      ("分別", "magnifyingglass", "magnifyingglass"),
      ("設定", "gearshape", "gearshape.fill"),
    ]

    let controllers = items.enumerated().map { index, item -> UIViewController in
      let vc = UIViewController()
      vc.view.backgroundColor = .clear
      vc.view.isOpaque = false
      vc.view.isUserInteractionEnabled = false
      vc.tabBarItem = UITabBarItem(
        title: item.title,
        image: UIImage(systemName: item.symbol),
        selectedImage: UIImage(systemName: item.selectedSymbol)
      )
      vc.tabBarItem.tag = index
      return vc
    }

    tabBarController.viewControllers = controllers
    tabBarController.delegate = self
    tabBarController.view.frame = containerView.bounds
    tabBarController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    tabBarController.view.backgroundColor = .clear
    tabBarController.view.isOpaque = false

    containerView.addSubview(tabBarController.view)
    containerView.managedTabBar = tabBarController.tabBar
    containerView.onCapsuleRectChanged = { [weak self] rect in
      self?.channel.invokeMethod(
        "onHitRect",
        arguments: [
          "left": Double(rect.minX),
          "top": Double(rect.minY),
          "right": Double(rect.maxX),
          "bottom": Double(rect.maxY),
        ]
      )
    }
  }

  private func apply(_ dict: [String: Any]?) {
    guard let dict else { return }
    if let isDark = dict["isDark"] as? Bool {
      let style: UIUserInterfaceStyle = isDark ? .dark : .light
      containerView.overrideUserInterfaceStyle = style
      tabBarController.overrideUserInterfaceStyle = style
    }
    if let tint = (dict["tintColor"] as? NSNumber)?.intValue {
      tabBarController.tabBar.tintColor = LiquidGlassColor.fromARGB(tint)
    }
    if let index = (dict["selectedIndex"] as? NSNumber)?.intValue,
       index >= 0,
       index < (tabBarController.viewControllers?.count ?? 0),
       tabBarController.selectedIndex != index {
      tabBarController.selectedIndex = index
    }
    if let touchEnabled = dict["touchEnabled"] as? Bool {
      containerView.isTouchEnabled = touchEnabled
    }
  }

  func tabBarController(
    _ tabBarController: UITabBarController,
    didSelect viewController: UIViewController
  ) {
    channel.invokeMethod("onSelect", arguments: viewController.tabBarItem.tag)
  }
}

private final class LiquidGlassTabBarFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    LiquidGlassTabBarPlatformView(
      frame: frame,
      viewId: viewId,
      arguments: args,
      messenger: messenger
    )
  }
}
