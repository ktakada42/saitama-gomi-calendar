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

  /// iOS 26 以降の Liquid Glass コンポーネント（UIGlassEffect 面・純正 UITabBar・五十音索引）を登録する。
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
    if let kanaIndexRegistrar = registry.registrar(forPlugin: "LiquidGlassKanaIndexPlugin") {
      kanaIndexRegistrar.register(
        LiquidGlassKanaIndexFactory(messenger: kanaIndexRegistrar.messenger()),
        withId: "io.github.ktakada42.saitamagomicalendar/liquid_glass_kana_index"
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

// MARK: - Liquid Glass Kana Index (連続レンズ追従型の五十音インデックス)

private struct RGBAComponents: Equatable {
  var r: CGFloat
  var g: CGFloat
  var b: CGFloat
  var a: CGFloat

  static func fromARGB(_ raw: Int) -> RGBAComponents {
    let bits = UInt32(bitPattern: Int32(truncatingIfNeeded: raw))
    return RGBAComponents(
      r: CGFloat((bits >> 16) & 0xFF) / 255.0,
      g: CGFloat((bits >> 8) & 0xFF) / 255.0,
      b: CGFloat(bits & 0xFF) / 255.0,
      a: CGFloat((bits >> 24) & 0xFF) / 255.0
    )
  }

  var uiColor: UIColor {
    UIColor(red: r, green: g, blue: b, alpha: a)
  }

  func interpolatedStruct(to other: RGBAComponents, t: CGFloat) -> RGBAComponents {
    let c = min(max(t, 0), 1)
    return RGBAComponents(
      r: r + (other.r - r) * c,
      g: g + (other.g - g) * c,
      b: b + (other.b - b) * c,
      a: a + (other.a - a) * c
    )
  }

  func interpolatedColor(to other: RGBAComponents, t: CGFloat) -> UIColor {
    interpolatedStruct(to: other, t: t).uiColor
  }
}

private final class KanaDisplayLinkProxy {
  weak var target: KanaIndexInteractiveView?

  init(_ target: KanaIndexInteractiveView) {
    self.target = target
  }

  @objc func step(_ link: CADisplayLink) {
    target?.handleDisplayLink(link)
  }
}

private final class KanaIndexInteractiveView: UIView {
  /// 毎フレーム UIFont を生成しないための 9 段階ウェイトキャッシュ（Regular〜Bold）。
  private static let weightFonts: [UIFont] = {
    let minW = UIFont.Weight.regular.rawValue
    let maxW = UIFont.Weight.bold.rawValue
    return (0...8).map { step in
      let t = CGFloat(step) / 8.0
      let w = UIFont.Weight(rawValue: minW + (maxW - minW) * t)
      return UIFont.systemFont(ofSize: 11.5, weight: w)
    }
  }()

  private let trackEffectView = UIVisualEffectView()
  private let lensShadowContainer = UIView()
  private let lensEffectView = UIVisualEffectView()
  private let labelsContainerView = UIView()
  private var labels: [UILabel] = []

  private let selectionFeedback = UISelectionFeedbackGenerator()
  private var displayLink: CADisplayLink?
  private var lastTimestamp: CFTimeInterval?

  private(set) var heads: [String] = []
  private(set) var selectedIndex: Int = 0
  var isTouchEnabled: Bool = true
  private var isDark: Bool = false

  private var tintRGB = RGBAComponents(r: 0.184, g: 0.478, b: 0.310, a: 1.0)
  private var labelRGB = RGBAComponents(r: 0.110, g: 0.106, b: 0.094, a: 1.0)
  private var mutedLabelRGB = RGBAComponents(r: 0.361, g: 0.353, b: 0.322, a: 1.0)

  private var isActive: Bool = false
  private var hasInitializedPosition: Bool = false
  private var lastLayoutHeight: CGFloat = 0

  // 連続スプリング状態
  private var lensY: CGFloat = 0
  private var lensTargetY: CGFloat = 0
  private var lensVelY: CGFloat = 0
  private var lensScale: CGFloat = 1.0
  private var lensVelScale: CGFloat = 0
  private var activeProgress: CGFloat = 0

  var onScrubStart: (() -> Void)?
  var onSelect: ((Int) -> Void)?
  var onScrubEnd: (() -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    isMultipleTouchEnabled = false
    isExclusiveTouch = true

    trackEffectView.backgroundColor = .clear
    trackEffectView.isUserInteractionEnabled = false
    trackEffectView.alpha = 0
    trackEffectView.transform = CGAffineTransform(scaleX: 0.72, y: 0.98)
    addSubview(trackEffectView)

    lensShadowContainer.backgroundColor = .clear
    lensShadowContainer.isUserInteractionEnabled = false
    lensShadowContainer.layer.shadowColor = UIColor.black.cgColor
    lensShadowContainer.layer.shadowOffset = CGSize(width: 0, height: 1.5)
    lensShadowContainer.layer.shadowRadius = 4
    lensShadowContainer.layer.shadowOpacity = 0.08
    addSubview(lensShadowContainer)

    lensEffectView.frame = lensShadowContainer.bounds
    lensEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    lensEffectView.backgroundColor = .clear
    lensEffectView.isUserInteractionEnabled = false
    lensShadowContainer.addSubview(lensEffectView)

    labelsContainerView.backgroundColor = .clear
    labelsContainerView.isUserInteractionEnabled = false
    addSubview(labelsContainerView)

    isAccessibilityElement = true
    accessibilityLabel = "五十音の索引"
    accessibilityTraits = .adjustable

    refreshGlassEffects()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    displayLink?.invalidate()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      if displayLink == nil {
        let link = CADisplayLink(
          target: KanaDisplayLinkProxy(self),
          selector: #selector(KanaDisplayLinkProxy.step(_:))
        )
        if #available(iOS 15.0, *) {
          link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 60,
            maximum: 120,
            preferred: 120
          )
        }
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        displayLink = link
      }
    } else {
      displayLink?.invalidate()
      displayLink = nil
      lastTimestamp = nil
    }
  }

  private func wakeDisplayLink() {
    guard let link = displayLink, link.isPaused else { return }
    lastTimestamp = nil
    link.isPaused = false
  }

  private func itemHeight() -> CGFloat {
    guard !heads.isEmpty, bounds.height > 0 else { return 0 }
    return bounds.height / CGFloat(heads.count)
  }

  private func centerOfIndex(_ index: Int) -> CGFloat {
    let h = itemHeight()
    guard h > 0 else { return 0 }
    let clamped = min(max(index, 0), heads.count - 1)
    return CGFloat(clamped) * h + h * 0.5
  }

  func apply(_ dict: [String: Any]?) {
    guard let dict else { return }

    var needsGlassRefresh = false
    var headsChanged = false

    if let nextDark = dict["isDark"] as? Bool, nextDark != isDark {
      isDark = nextDark
      overrideUserInterfaceStyle = isDark ? .dark : .light
      needsGlassRefresh = true
    }
    if let rawTint = (dict["tintColor"] as? NSNumber)?.intValue {
      let nextTint = RGBAComponents.fromARGB(rawTint)
      if nextTint != tintRGB {
        tintRGB = nextTint
        needsGlassRefresh = true
      }
    }
    if let rawLabel = (dict["labelColor"] as? NSNumber)?.intValue {
      labelRGB = RGBAComponents.fromARGB(rawLabel)
    }
    if let rawMuted = (dict["mutedLabelColor"] as? NSNumber)?.intValue {
      mutedLabelRGB = RGBAComponents.fromARGB(rawMuted)
    }
    if let enabled = dict["touchEnabled"] as? Bool {
      isTouchEnabled = enabled
      if !enabled && isActive {
        cancelInteractionQuietly()
      }
    }
    if let nextHeads = dict["heads"] as? [String], nextHeads != heads {
      heads = nextHeads
      rebuildLabels()
      headsChanged = true
    }

    if let nextIndex = (dict["selectedIndex"] as? NSNumber)?.intValue, !heads.isEmpty {
      let clamped = min(max(nextIndex, 0), heads.count - 1)
      if !isActive {
        // 利用者が直接一覧をスクロールしたときは、レンズを新しい行へ滑らかにスライドさせる。
        let changed = clamped != selectedIndex
        selectedIndex = clamped
        updateAccessibilityValue()
        if bounds.height > 0 {
          if !hasInitializedPosition || headsChanged {
            hasInitializedPosition = true
            lensY = centerOfIndex(clamped)
            lensTargetY = lensY
            lensVelY = 0
          } else if changed {
            lensTargetY = centerOfIndex(clamped)
            wakeDisplayLink()
          }
        }
      }
    }

    if needsGlassRefresh {
      refreshGlassEffects()
    }
    if headsChanged {
      setNeedsLayout()
    }
    updateVisuals()
  }

  private func rebuildLabels() {
    while labels.count > heads.count {
      labels.removeLast().removeFromSuperview()
    }
    while labels.count < heads.count {
      let label = UILabel()
      label.textAlignment = .center
      label.font = Self.weightFonts[0]
      label.isUserInteractionEnabled = false
      labelsContainerView.addSubview(label)
      labels.append(label)
    }
    for (i, head) in heads.enumerated() {
      labels[i].text = head
    }
    updateAccessibilityValue()
  }

  private func updateAccessibilityValue() {
    if selectedIndex >= 0 && selectedIndex < heads.count {
      accessibilityValue = "\(heads[selectedIndex])行"
    } else {
      accessibilityValue = nil
    }
  }

  private func refreshGlassEffects() {
    overrideUserInterfaceStyle = isDark ? .dark : .light
    if #available(iOS 26.0, *) {
      let trackGlass = UIGlassEffect(style: .regular)
      trackGlass.isInteractive = true
      trackEffectView.effect = trackGlass
      trackEffectView.cornerConfiguration = .capsule()

      let lensGlass = UIGlassEffect(style: .regular)
      lensGlass.isInteractive = true
      lensEffectView.effect = lensGlass
      lensEffectView.cornerConfiguration = .capsule()
    } else {
      trackEffectView.effect = UIBlurEffect(style: .systemChromeMaterial)
      trackEffectView.clipsToBounds = true
      lensEffectView.effect = UIBlurEffect(style: .systemThickMaterial)
      lensEffectView.clipsToBounds = true
    }
  }

  private func setTrackActive(_ active: Bool) {
    refreshGlassEffects()
    UIView.animate(
      withDuration: 0.22,
      delay: 0,
      usingSpringWithDamping: 0.82,
      initialSpringVelocity: 0,
      options: [.beginFromCurrentState, .allowUserInteraction]
    ) {
      self.trackEffectView.alpha = active ? 1.0 : 0.0
      self.trackEffectView.transform = active
        ? .identity
        : CGAffineTransform(scaleX: 0.72, y: 0.98)
      self.lensShadowContainer.layer.shadowOpacity = active ? 0.15 : 0.08
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    labelsContainerView.frame = bounds

    // トラックは左右 2pt インセットした縦カプセル。
    let prevTrackTransform = trackEffectView.transform
    trackEffectView.transform = .identity
    trackEffectView.frame = bounds.insetBy(dx: 2, dy: 0)
    if #unavailable(iOS 26.0) {
      trackEffectView.layer.cornerRadius = trackEffectView.bounds.width * 0.5
    }
    trackEffectView.transform = prevTrackTransform

    guard bounds.height > 0, !heads.isEmpty else { return }

    if !hasInitializedPosition {
      hasInitializedPosition = true
      lastLayoutHeight = bounds.height
      lensY = centerOfIndex(selectedIndex)
      lensTargetY = lensY
      lensVelY = 0
    } else if lastLayoutHeight > 0 && abs(bounds.height - lastLayoutHeight) > 0.01 {
      // お知らせバナーの開閉で高さがアニメーション変化している間も文字との相対位置を保つ。
      let ratio = bounds.height / lastLayoutHeight
      lensY *= ratio
      lensTargetY = isActive ? (lensTargetY * ratio) : centerOfIndex(selectedIndex)
      lastLayoutHeight = bounds.height
    } else if !isActive && (displayLink?.isPaused ?? true) {
      lensY = centerOfIndex(selectedIndex)
      lensTargetY = lensY
    }

    let h = itemHeight()
    for (i, label) in labels.enumerated() {
      let prevTransform = label.transform
      label.transform = .identity
      label.frame = CGRect(x: 0, y: CGFloat(i) * h, width: bounds.width, height: h)
      label.transform = prevTransform
    }

    updateVisuals()
  }

  fileprivate func handleDisplayLink(_ link: CADisplayLink) {
    guard hasInitializedPosition, bounds.height > 0, !heads.isEmpty else {
      link.isPaused = true
      lastTimestamp = nil
      return
    }

    let now = link.targetTimestamp
    guard let prev = lastTimestamp else {
      lastTimestamp = now
      return
    }
    lastTimestamp = now

    let rawDt = CGFloat(now - prev)
    guard rawDt > 0 else { return }
    let clampedDt = min(rawDt, 0.1)
    let maxStep: CGFloat = 1.0 / 240.0

    let targetScale: CGFloat = isActive ? 1.24 : 1.0
    let targetActive: CGFloat = isActive ? 1.0 : 0.0
    let omegaY: CGFloat = isActive ? 42.0 : 28.0
    let zetaY: CGFloat = isActive ? 0.90 : 0.85

    var remaining = clampedDt
    while remaining > 0 {
      let dt = min(remaining, maxStep)
      remaining -= dt

      let ay = omegaY * omegaY * (lensTargetY - lensY) - 2.0 * zetaY * omegaY * lensVelY
      lensVelY += ay * dt
      lensY += lensVelY * dt

      let omegaS: CGFloat = 32.0
      let zetaS: CGFloat = 0.86
      let aScale = omegaS * omegaS * (targetScale - lensScale) - 2.0 * zetaS * omegaS * lensVelScale
      lensVelScale += aScale * dt
      lensScale += lensVelScale * dt

      activeProgress += (targetActive - activeProgress) * min(1.0, dt * 18.0)
    }

    let settled = abs(lensTargetY - lensY) < 0.06
      && abs(lensVelY) < 0.4
      && abs(targetScale - lensScale) < 0.003
      && abs(lensVelScale) < 0.04
      && abs(targetActive - activeProgress) < 0.008

    if settled {
      lensY = lensTargetY
      lensVelY = 0
      lensScale = targetScale
      lensVelScale = 0
      activeProgress = targetActive
      link.isPaused = true
      lastTimestamp = nil
    }

    updateVisuals()
  }

  private func updateVisuals() {
    let h = itemHeight()
    guard h > 0, bounds.width > 0 else { return }

    let baseSize = min(22.0, max(12.0, h * 0.88))
    let stretch = min(0.20, abs(lensVelY) / 1400.0)
    let scaleX = lensScale * (1.0 - stretch * 0.32)
    let scaleY = lensScale * (1.0 + stretch)

    lensShadowContainer.transform = .identity
    lensShadowContainer.bounds = CGRect(x: 0, y: 0, width: baseSize, height: baseSize)
    lensShadowContainer.center = CGPoint(x: bounds.midX, y: lensY)
    if #unavailable(iOS 26.0) {
      lensEffectView.layer.cornerRadius = baseSize * 0.5
    }
    lensShadowContainer.transform = CGAffineTransform(scaleX: scaleX, y: scaleY)

    let unselectedBase = mutedLabelRGB.interpolatedStruct(to: labelRGB, t: activeProgress)
    let maxBoost: CGFloat = 0.04 + 0.14 * activeProgress

    for (i, label) in labels.enumerated() {
      let cy = CGFloat(i) * h + h * 0.5
      let dist = abs(cy - lensY) / max(1.0, h)
      let proximity = min(max(1.0 - dist, 0.0), 1.0)
      let t = proximity * proximity * (3.0 - 2.0 * proximity)

      label.textColor = unselectedBase.interpolatedColor(to: tintRGB, t: t)
      let weightIdx = min(8, max(0, Int((t * 8.0).rounded())))
      let nextFont = Self.weightFonts[weightIdx]
      if label.font !== nextFont {
        label.font = nextFont
      }
      let scale = 1.0 + maxBoost * t
      label.transform = CGAffineTransform(scaleX: scale, y: scale)
    }
  }

  // MARK: - Touch Handling

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard isTouchEnabled, !heads.isEmpty, !isHidden, alpha > 0.01 else {
      return nil
    }
    return self.point(inside: point, with: event) ? self : nil
  }

  private func processTouch(at y: CGFloat) {
    let h = itemHeight()
    guard h > 0, !heads.isEmpty else { return }

    let minCenter = h * 0.5
    let maxCenter = bounds.height - h * 0.5
    lensTargetY = min(max(y, minCenter), maxCenter)
    wakeDisplayLink()

    let idx = min(max(Int(floor(y / h)), 0), heads.count - 1)
    if idx != selectedIndex {
      selectedIndex = idx
      updateAccessibilityValue()
      selectionFeedback.selectionChanged()
      selectionFeedback.prepare()
      onSelect?(idx)
    }
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard isTouchEnabled, let touch = touches.first, !heads.isEmpty else { return }
    isActive = true
    selectionFeedback.prepare()
    setTrackActive(true)
    onScrubStart?()
    processTouch(at: touch.location(in: self).y)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard isActive, let touch = touches.first else { return }
    processTouch(at: touch.location(in: self).y)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    finishInteraction(notify: true)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    finishInteraction(notify: true)
  }

  private func cancelInteractionQuietly() {
    finishInteraction(notify: false)
  }

  private func finishInteraction(notify: Bool) {
    guard isActive else { return }
    isActive = false
    lensTargetY = centerOfIndex(selectedIndex)
    setTrackActive(false)
    wakeDisplayLink()
    if notify {
      onScrubEnd?()
    }
  }

  // MARK: - VoiceOver Adjustable

  override func accessibilityIncrement() {
    stepAccessibility(delta: 1)
  }

  override func accessibilityDecrement() {
    stepAccessibility(delta: -1)
  }

  private func stepAccessibility(delta: Int) {
    guard !heads.isEmpty else { return }
    let next = min(max(selectedIndex + delta, 0), heads.count - 1)
    guard next != selectedIndex else { return }
    selectedIndex = next
    updateAccessibilityValue()
    lensTargetY = centerOfIndex(next)
    wakeDisplayLink()
    onScrubStart?()
    onSelect?(next)
    onScrubEnd?()
  }
}

private final class LiquidGlassKanaIndexPlatformView: NSObject, FlutterPlatformView {
  private let indexView: KanaIndexInteractiveView
  private let channel: FlutterMethodChannel

  init(
    frame: CGRect,
    viewId: Int64,
    arguments: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    indexView = KanaIndexInteractiveView(frame: frame)
    channel = FlutterMethodChannel(
      name: "io.github.ktakada42.saitamagomicalendar/liquid_glass_kana_index_\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    indexView.onScrubStart = { [weak self] in
      self?.channel.invokeMethod("onScrubStart", arguments: nil)
    }
    indexView.onSelect = { [weak self] index in
      self?.channel.invokeMethod("onSelect", arguments: index)
    }
    indexView.onScrubEnd = { [weak self] in
      self?.channel.invokeMethod("onScrubEnd", arguments: nil)
    }

    indexView.apply(arguments as? [String: Any])

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      if call.method == "update" {
        self.indexView.apply(call.arguments as? [String: Any])
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView {
    indexView
  }
}

private final class LiquidGlassKanaIndexFactory: NSObject, FlutterPlatformViewFactory {
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
    LiquidGlassKanaIndexPlatformView(
      frame: frame,
      viewId: viewId,
      arguments: args,
      messenger: messenger
    )
  }
}
