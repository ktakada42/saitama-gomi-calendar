#!/usr/bin/env swift
// design/app_icon_master.svg と同じベクター構成から、iOS の Dark / Tinted（および
// iOS 26 のクリア＝Liquid Glass 表示）向け 1024x1024 アイコンを生成する。
//
// Light（通常表示）はアルファなしの Icon-App-1024x1024@1x.png を使う。
// Dark / Tinted は背景を透過（RGBA）にしておくことで、iOS がダークプレートや
// Liquid Glass の屈折レイヤーをモチーフの背後に合成できるようにする。

import AppKit
import CoreGraphics
import Foundation
import WebKit

@MainActor
final class AppearanceSVGRasterizer: NSObject, WKNavigationDelegate {
  private var webView: WKWebView!
  private var continuation: CheckedContinuation<CGImage, Error>?
  private let canvasSize: Int

  init(canvasSize: Int) {
    self.canvasSize = canvasSize
    super.init()
  }

  func rasterizeTransparent(svgContent: String) async throws -> CGImage {
    let config = WKWebViewConfiguration()
    webView = WKWebView(
      frame: NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize),
      configuration: config
    )
    webView.setValue(false, forKey: "drawsBackground")
    webView.navigationDelegate = self

    let html = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <style>
      * { margin: 0; padding: 0; box-sizing: border-box; }
      html, body { width: \(canvasSize)px; height: \(canvasSize)px; overflow: hidden; background: transparent; }
      svg { display: block; width: \(canvasSize)px; height: \(canvasSize)px; }
    </style>
    </head>
    <body>\(svgContent)</body>
    </html>
    """

    return try await withCheckedThrowingContinuation { cont in
      self.continuation = cont
      webView.loadHTMLString(html, baseURL: nil)
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
      let snap = WKSnapshotConfiguration()
      snap.rect = CGRect(x: 0, y: 0, width: self.canvasSize, height: self.canvasSize)
      snap.snapshotWidth = NSNumber(value: self.canvasSize)
      webView.takeSnapshot(with: snap) { image, error in
        if let error = error {
          self.continuation?.resume(throwing: error)
        } else if let image = image,
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
          self.continuation?.resume(returning: cg)
        } else {
          self.continuation?.resume(throwing: NSError(domain: "AppearanceSVGRasterizer", code: -1))
        }
        self.continuation = nil
      }
    }
  }
}

func writeTransparentRGBAPNG(_ source: CGImage, size: Int, to url: URL) throws {
  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
  guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  ) else {
    fatalError("CGContext creation failed")
  }
  ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
  ctx.interpolationQuality = .high
  ctx.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))

  guard let outCG = ctx.makeImage() else {
    fatalError("makeImage failed")
  }
  let rep = NSBitmapImageRep(cgImage: outCG)
  guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG encoding failed")
  }
  try pngData.write(to: url)
}

func extractSaitamaLogoPaths(from masterSVG: String) -> String {
  guard let startRange = masterSVG.range(of: "<g id=\"saitama-logo\""),
        let openTagEnd = masterSVG[startRange.lowerBound...].firstIndex(of: ">"),
        let closeRange = masterSVG[openTagEnd...].range(of: "</g>") else {
    fatalError("saitama-logo group not found in app_icon_master.svg")
  }
  let innerStart = masterSVG.index(after: openTagEnd)
  return String(masterSVG[innerStart..<closeRange.lowerBound])
}

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let masterURL = repoRoot.appendingPathComponent("design/app_icon_master.svg")
let appIconDir = repoRoot.appendingPathComponent("ios/Runner/Assets.xcassets/AppIcon.appiconset")

let masterSVG = try String(contentsOf: masterURL, encoding: .utf8)
let saitamaPaths = extractSaitamaLogoPaths(from: masterSVG)

// 1. Dark バリアント SVG（透過背景＋ダークフロスト・カレンダーカード＋高視認ダーク区分セル＋純白袋）
let darkSVG = """
<svg viewBox="0 0 240 240" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="d-card" x1="0.1" y1="0" x2="0.9" y2="1">
      <stop offset="0%" stop-color="#22352C" stop-opacity="0.95"/>
      <stop offset="55%" stop-color="#1A2922" stop-opacity="0.92"/>
      <stop offset="100%" stop-color="#13201A" stop-opacity="0.94"/>
    </linearGradient>
    <linearGradient id="d-hdr" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#2B8A58" stop-opacity="0.95"/>
      <stop offset="100%" stop-color="#1B633E" stop-opacity="0.96"/>
    </linearGradient>
    <linearGradient id="d-rim" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.72"/>
      <stop offset="30%" stop-color="#80FFBF" stop-opacity="0.32"/>
      <stop offset="55%" stop-color="#FFFFFF" stop-opacity="0.12"/>
      <stop offset="80%" stop-color="#72EFDD" stop-opacity="0.38"/>
      <stop offset="100%" stop-color="#FFFFFF" stop-opacity="0.68"/>
    </linearGradient>
    <linearGradient id="d-prism" x1="0" y1="1" x2="1" y2="0">
      <stop offset="0%" stop-color="#66E3FF" stop-opacity="0.45"/>
      <stop offset="50%" stop-color="#FFFFFF" stop-opacity="0.0"/>
      <stop offset="100%" stop-color="#A3F7BF" stop-opacity="0.45"/>
    </linearGradient>
    <radialGradient id="d-orb" cx="30%" cy="25%" r="75%">
      <stop offset="0%" stop-color="#74F2B3" stop-opacity="0.68"/>
      <stop offset="45%" stop-color="#278556" stop-opacity="0.86"/>
      <stop offset="85%" stop-color="#11422B" stop-opacity="0.95"/>
      <stop offset="100%" stop-color="#5CE6A0" stop-opacity="0.85"/>
    </radialGradient>
    <filter id="d-blur" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="8"/>
    </filter>
    <filter id="d-drop" x="-22%" y="-18%" width="145%" height="150%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="8" result="blur"/>
      <feOffset in="blur" dx="0" dy="8" result="offsetBlur"/>
      <feComponentTransfer in="offsetBlur" result="shadow">
        <feFuncA type="linear" slope="0.55"/>
      </feComponentTransfer>
      <feMerge>
        <feMergeNode in="shadow"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
    <filter id="d-bag-drop" x="-25%" y="-25%" width="150%" height="150%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="3" result="blur"/>
      <feOffset in="blur" dx="0" dy="3" result="offsetBlur"/>
      <feComponentTransfer in="offsetBlur" result="shadow">
        <feFuncA type="linear" slope="0.34"/>
      </feComponentTransfer>
      <feMerge>
        <feMergeNode in="shadow"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
    <clipPath id="d-card-clip">
      <rect x="30" y="34" width="156" height="162" rx="30"/>
    </clipPath>
    <clipPath id="d-orb-clip">
      <circle cx="172" cy="166" r="46"/>
    </clipPath>
  </defs>

  <!-- 背面に傾いたセカンド・ダークガラスシート -->
  <g transform="rotate(-5.5 110 115)">
    <rect x="38" y="38" width="148" height="156" rx="29" fill="#2A4438" fill-opacity="0.42" stroke="url(#d-rim)" stroke-width="1.5"/>
  </g>

  <!-- メインのダークフロスト・カレンダーカード -->
  <g filter="url(#d-drop)">
    <rect x="30" y="34" width="156" height="162" rx="30" fill="url(#d-card)"/>

    <g clip-path="url(#d-card-clip)">
      <circle cx="165" cy="112" r="52" fill="#38D9A9" opacity="0.14" filter="url(#d-blur)"/>
      <circle cx="52" cy="176" r="46" fill="#48CAE4" opacity="0.12" filter="url(#d-blur)"/>

      <rect x="30" y="34" width="156" height="48" fill="url(#d-hdr)"/>
      <path d="M30,52 Q95,34 186,60 L186,34 L30,34 Z" fill="#96F2D7" opacity="0.18"/>
      <line x1="30" y1="82" x2="186" y2="82" stroke="#FFFFFF" stroke-opacity="0.28" stroke-width="1.2"/>

      <circle cx="47" cy="48" r="3.8" fill="#FFFFFF" fill-opacity="0.32" stroke="#FFFFFF" stroke-opacity="0.55" stroke-width="1"/>
      <circle cx="169" cy="48" r="3.8" fill="#FFFFFF" fill-opacity="0.32" stroke="#FFFFFF" stroke-opacity="0.55" stroke-width="1"/>

      <g fill="#FFFFFF">
        \(saitamaPaths)
      </g>

      <!-- 平日5曜日ドット -->
      <g>
        <circle cx="54" cy="92.5" r="2.6" fill="#88A094"/>
        <circle cx="81" cy="92.5" r="2.6" fill="#88A094"/>
        <circle cx="108" cy="92.5" r="2.6" fill="#88A094"/>
        <circle cx="135" cy="92.5" r="2.6" fill="#88A094"/>
        <circle cx="162" cy="92.5" r="2.6" fill="#88A094"/>
      </g>

      <!-- ダークモード用 5列×3週 平日カレンダー格子（CategoryStyle.dark カラー連動・縦一列同色＆アンダーバー統一） -->
      <rect x="43" y="102" width="22" height="22" rx="5.6" fill="#FF922B" fill-opacity="0.24"/>
      <rect x="46" y="115.6" width="16" height="4.4" rx="2.2" fill="#FF922B"/>
      <rect x="70" y="102" width="22" height="22" rx="5.6" fill="#38D9A9" fill-opacity="0.24"/>
      <rect x="73" y="115.6" width="16" height="4.4" rx="2.2" fill="#38D9A9"/>
      <rect x="97" y="102" width="22" height="22" rx="5.6" fill="#FFFFFF" fill-opacity="0.09"/>
      <rect x="124" y="102" width="22" height="22" rx="5.6" fill="#FF922B" fill-opacity="0.24"/>
      <rect x="127" y="115.6" width="16" height="4.4" rx="2.2" fill="#FF922B"/>
      <rect x="151" y="102" width="22" height="22" rx="5.6" fill="#748FFC" fill-opacity="0.26"/>
      <rect x="154" y="115.6" width="16" height="4.4" rx="2.2" fill="#748FFC"/>

      <rect x="43" y="130" width="22" height="22" rx="5.6" fill="#FF922B" fill-opacity="0.24"/>
      <rect x="46" y="143.6" width="16" height="4.4" rx="2.2" fill="#FF922B"/>
      <rect x="70" y="130" width="22" height="22" rx="5.6" fill="#38D9A9" fill-opacity="0.24"/>
      <rect x="73" y="143.6" width="16" height="4.4" rx="2.2" fill="#38D9A9"/>
      <rect x="97" y="130" width="22" height="22" rx="5.6" fill="#FFFFFF" fill-opacity="0.09"/>
      <rect x="124" y="130" width="22" height="22" rx="5.6" fill="#FF922B" fill-opacity="0.24"/>
      <rect x="127" y="143.6" width="16" height="4.4" rx="2.2" fill="#FF922B"/>
      <rect x="151" y="130" width="22" height="22" rx="5.6" fill="#748FFC" fill-opacity="0.26"/>
      <rect x="154" y="143.6" width="16" height="4.4" rx="2.2" fill="#748FFC"/>

      <rect x="43" y="158" width="22" height="22" rx="5.6" fill="#FF922B" fill-opacity="0.24"/>
      <rect x="46" y="171.6" width="16" height="4.4" rx="2.2" fill="#FF922B"/>
      <rect x="70" y="158" width="22" height="22" rx="5.6" fill="#38D9A9" fill-opacity="0.24"/>
      <rect x="73" y="171.6" width="16" height="4.4" rx="2.2" fill="#38D9A9"/>
      <rect x="97" y="158" width="22" height="22" rx="5.6" fill="#FFFFFF" fill-opacity="0.09"/>
      <rect x="124" y="158" width="22" height="22" rx="5.6" fill="#FF922B" fill-opacity="0.24"/>
      <rect x="127" y="171.6" width="16" height="4.4" rx="2.2" fill="#FF922B"/>
      <rect x="151" y="158" width="22" height="22" rx="5.6" fill="#748FFC" fill-opacity="0.26"/>
      <rect x="154" y="171.6" width="16" height="4.4" rx="2.2" fill="#748FFC"/>
    </g>

    <rect x="31" y="35" width="154" height="160" rx="29" fill="none" stroke="url(#d-prism)" stroke-width="1.4"/>
    <rect x="30" y="34" width="156" height="162" rx="30" fill="none" stroke="url(#d-rim)" stroke-width="1.8"/>
  </g>

  <!-- 右下プリズムガラス球 + 純白ゴミ袋（緑系持ち手・108%拡大） -->
  <g filter="url(#d-drop)">
    <circle cx="172" cy="166" r="46" fill="url(#d-orb)"/>
    <g clip-path="url(#d-orb-clip)">
      <ellipse cx="153" cy="136" rx="27" ry="12" fill="#FFFFFF" opacity="0.28" transform="rotate(-28 153 136)"/>
      <ellipse cx="191" cy="196" rx="26" ry="10" fill="#72EFDD" opacity="0.32" transform="rotate(-25 191 196)"/>
    </g>
    <circle cx="172" cy="166" r="44.5" fill="none" stroke="url(#d-prism)" stroke-width="1.8"/>
    <circle cx="172" cy="166" r="46" fill="none" stroke="url(#d-rim)" stroke-width="2.0"/>

    <g filter="url(#d-bag-drop)" transform="translate(172, 167) scale(1.08) translate(-174, -168)">
      <path d="M174,142 C166.5,135 158.5,134 155.5,138.5 C157.5,142.5 165,145.5 174,146.5 Z" fill="#FFFFFF"/>
      <path d="M174,142 C181.5,135 189.5,134 192.5,138.5 C190.5,142.5 183,145.5 174,146.5 Z" fill="#B2F2BB"/>
      <path d="M163.5,147.5 C152,151.5 145,161 143,173.5 C141.5,182.5 144.5,190.5 152.5,193.5 C161,196 187,196 195.5,193.5 C203.5,190.5 206.5,182.5 205,173.5 C203,161 196,151.5 184.5,147.5 Z" fill="#FFFFFF"/>
      <path d="M159,159 C155.5,166.5 156,176 159.5,182" fill="none" stroke="#9EE6C4" stroke-width="2.8" stroke-linecap="round" opacity="0.82"/>
      <rect x="166.5" y="142.8" width="15" height="7.4" rx="3.7" fill="#12B886"/>
    </g>
  </g>
</svg>
"""

// 2. Tinted / Clear (Liquid Glass) バリアント SVG（透過背景＋グレースケール濃淡マスク）
let tintedSVG = """
<svg viewBox="0 0 240 240" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <!-- カレンダーカードと右下ガラス球が重なって濁らないよう球体領域をくり抜くマスク -->
    <mask id="card-cutout-mask">
      <rect width="240" height="240" fill="white"/>
      <circle cx="172" cy="166" r="49" fill="black"/>
    </mask>

    <!-- ゴミ袋内部のシワと結束リング境界を抜いて単色ティントでも立体感を出すマスク -->
    <mask id="bag-detail-mask">
      <rect x="120" y="110" width="110" height="110" fill="white"/>
      <path d="M159,159 C155.5,166.5 156,176 159.5,182" fill="none" stroke="black" stroke-width="3.2" stroke-linecap="round"/>
      <rect x="165" y="141.6" width="18" height="9.8" rx="4.9" fill="black"/>
    </mask>

    <clipPath id="t-card-clip">
      <rect x="30" y="34" width="156" height="162" rx="30"/>
    </clipPath>
  </defs>

  <g mask="url(#card-cutout-mask)">
    <!-- 傾いたセカンド・ガラスシート -->
    <g transform="rotate(-5.5 110 115)">
      <rect x="38" y="38" width="148" height="156" rx="29" fill="#FFFFFF" fill-opacity="0.16" stroke="#FFFFFF" stroke-opacity="0.38" stroke-width="1.6"/>
    </g>

    <!-- メインカレンダー・ガラス面 -->
    <rect x="30" y="34" width="156" height="162" rx="30" fill="#FFFFFF" fill-opacity="0.28"/>

    <g clip-path="url(#t-card-clip)">
      <!-- ヘッダー帯 -->
      <rect x="30" y="34" width="156" height="48" fill="#FFFFFF" fill-opacity="0.28"/>
      <line x1="30" y1="82" x2="186" y2="82" stroke="#FFFFFF" stroke-opacity="0.65" stroke-width="1.4"/>

      <circle cx="47" cy="48" r="3.8" fill="#FFFFFF" fill-opacity="0.45"/>
      <circle cx="169" cy="48" r="3.8" fill="#FFFFFF" fill-opacity="0.45"/>

      <!-- 「さいたま」ロゴ（最高輝度 100% 白） -->
      <g fill="#FFFFFF">
        \(saitamaPaths)
      </g>

      <!-- 平日5曜日ドット -->
      <g fill="#FFFFFF" fill-opacity="0.65">
        <circle cx="54" cy="92.5" r="2.6"/>
        <circle cx="81" cy="92.5" r="2.6"/>
        <circle cx="108" cy="92.5" r="2.6"/>
        <circle cx="135" cy="92.5" r="2.6"/>
        <circle cx="162" cy="92.5" r="2.6"/>
      </g>

      <!-- 5列×3週 平日カレンダー格子（濃淡階層で収集日と非収集日を区別） -->
      <rect x="43" y="102" width="22" height="22" rx="5.6" fill="#FFFFFF" fill-opacity="0.40"/>
      <rect x="46" y="115.6" width="16" height="4.4" rx="2.2" fill="#FFFFFF" fill-opacity="0.95"/>
      <rect x="70" y="102" width="22" height="22" rx="5.6" fill="#FFFFFF" fill-opacity="0.40"/>
      <rect x="73" y="115.6" width="16" height="4.4" rx="2.2" fill="#FFFFFF" fill-opacity="0.95"/>
      <rect x="97" y="102" width="22" height="22" rx="5.6" fill="#FFFFFF" fill-opacity="0.12"/>
      <rect x="124" y="102" width="22" height="22" rx="5.6" fill="#FFFFFF" fill-opacity="0.40"/>
      <rect x="127" y="115.6" width="16" height="4.4" rx="2.2" fill="#FFFFFF" fill-opacity="0.95"/>
      <rect x="151" y="102" width="22" height="22" rx="5.6" fill="#FFFFFF" fill-opacity="0.40"/>
      <rect x="154" y="115.6" width="16" height="4.4" rx="2.2" fill="#FFFFFF" fill-opacity="0.95"/>

      <rect x="43" y="130" width="22" height="22" rx="5.6" fill="#FFFFFF" fill-opacity="0.40"/>
      <rect x="46" y="143.6" width="16" height="4.4" rx="2.2" fill="#FFFFFF" fill-opacity="0.95"/>
      <rect x="70" y="130" width="22" height="22" rx="5.6" fill="#FFFFFF" fill-opacity="0.40"/>
      <rect x="73" y="143.6" width="16" height="4.4" rx="2.2" fill="#FFFFFF" fill-opacity="0.95"/>
      <rect x="97" y="130" width="22" height="22" rx="5.6" fill="#FFFFFF" fill-opacity="0.12"/>
      <rect x="124" y="130" width="22" height="22" rx="5.6" fill="#FFFFFF" fill-opacity="0.40"/>
      <rect x="127" y="143.6" width="16" height="4.4" rx="2.2" fill="#FFFFFF" fill-opacity="0.95"/>
      <rect x="151" y="130" width="22" height="22" rx="5.6" fill="#FFFFFF" fill-opacity="0.40"/>
      <rect x="154" y="143.6" width="16" height="4.4" rx="2.2" fill="#FFFFFF" fill-opacity="0.95"/>

      <rect x="43" y="158" width="22" height="22" rx="5.6" fill="#FFFFFF" fill-opacity="0.40"/>
      <rect x="46" y="171.6" width="16" height="4.4" rx="2.2" fill="#FFFFFF" fill-opacity="0.95"/>
      <rect x="70" y="158" width="22" height="22" rx="5.6" fill="#FFFFFF" fill-opacity="0.40"/>
      <rect x="73" y="171.6" width="16" height="4.4" rx="2.2" fill="#FFFFFF" fill-opacity="0.95"/>
      <rect x="97" y="158" width="22" height="22" rx="5.6" fill="#FFFFFF" fill-opacity="0.12"/>
      <rect x="124" y="158" width="22" height="22" rx="5.6" fill="#FFFFFF" fill-opacity="0.40"/>
      <rect x="127" y="171.6" width="16" height="4.4" rx="2.2" fill="#FFFFFF" fill-opacity="0.95"/>
      <rect x="151" y="158" width="22" height="22" rx="5.6" fill="#FFFFFF" fill-opacity="0.40"/>
      <rect x="154" y="171.6" width="16" height="4.4" rx="2.2" fill="#FFFFFF" fill-opacity="0.95"/>
    </g>

    <rect x="30" y="34" width="156" height="162" rx="30" fill="none" stroke="#FFFFFF" stroke-opacity="0.82" stroke-width="2.2"/>
  </g>

  <!-- 右下ガラス球 + 高コントラスト白ゴミ袋 -->
  <circle cx="172" cy="166" r="46" fill="#FFFFFF" fill-opacity="0.30" stroke="#FFFFFF" stroke-opacity="0.90" stroke-width="2.4"/>
  <ellipse cx="153" cy="136" rx="24" ry="10" fill="#FFFFFF" fill-opacity="0.22" transform="rotate(-28 153 136)"/>

  <g transform="translate(172, 167) scale(1.08) translate(-174, -168)">
    <g mask="url(#bag-detail-mask)">
      <path d="M174,142 C166.5,135 158.5,134 155.5,138.5 C157.5,142.5 165,145.5 174,146.5 Z" fill="#FFFFFF"/>
      <path d="M174,142 C181.5,135 189.5,134 192.5,138.5 C190.5,142.5 183,145.5 174,146.5 Z" fill="#FFFFFF" fill-opacity="0.76"/>
      <path d="M163.5,147.5 C152,151.5 145,161 143,173.5 C141.5,182.5 144.5,190.5 152.5,193.5 C161,196 187,196 195.5,193.5 C203.5,190.5 206.5,182.5 205,173.5 C203,161 196,151.5 184.5,147.5 Z" fill="#FFFFFF"/>
    </g>
    <rect x="166.5" y="142.8" width="15" height="7.4" rx="3.7" fill="#FFFFFF" fill-opacity="0.88"/>
  </g>
</svg>
"""

Task { @MainActor in
  do {
    _ = NSApplication.shared
    let rasterizer = AppearanceSVGRasterizer(canvasSize: 1024)

    let darkCG = try await rasterizer.rasterizeTransparent(svgContent: darkSVG)
    let darkURL = appIconDir.appendingPathComponent("Icon-App-Dark-1024x1024@1x.png")
    try writeTransparentRGBAPNG(darkCG, size: 1024, to: darkURL)

    let tintedCG = try await rasterizer.rasterizeTransparent(svgContent: tintedSVG)
    let tintedURL = appIconDir.appendingPathComponent("Icon-App-Tinted-1024x1024@1x.png")
    try writeTransparentRGBAPNG(tintedCG, size: 1024, to: tintedURL)

    print("Generated Dark and Tinted icons in \(appIconDir.path)")
    exit(0)
  } catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
  }
}

RunLoop.main.run()
