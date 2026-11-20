#!/usr/bin/env bash
# design/app_icon_master.svg から iOS/Android のアプリアイコン一式を生成する。
#
# OSのマスク処理に合わせて、書き出すPNGは角丸なしの正方形フルブリード
# （マスターSVG自体が角丸を持たない）。iOSの通常（Light）アイコンおよびAndroidの
# ランチャーアイコンはアルファチャンネルを持たない 24-bit RGB PNG として書き出す
# （1024pxのApp Store提出用アイコンはアルファ無しが必須要件）。
#
# macOS 標準の Swift（WebKit + CoreGraphics）だけで動作するため、外部ツールの
# 追加インストールは不要。続けて design/generate_ios_appearances.swift を呼び出し、
# iOS の Dark / Tinted（および Liquid Glass クリア表示）用バリアントも更新する。
#
# 使い方: bash design/generate_app_icons.sh
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
master="$repo_root/design/app_icon_master.svg"
ios_dir="$repo_root/ios/Runner/Assets.xcassets/AppIcon.appiconset"
android_res="$repo_root/android/app/src/main/res"

echo "== マスターSVGから Light (iOS) / Android アイコンを生成 =="
swift - "$master" "$ios_dir" "$android_res" <<'SWIFTEOF'
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WebKit

@MainActor
final class MasterSVGRasterizer: NSObject, WKNavigationDelegate {
  private var webView: WKWebView!
  private var continuation: CheckedContinuation<CGImage, Error>?
  private let canvasSize: Int

  init(canvasSize: Int) {
    self.canvasSize = canvasSize
    super.init()
  }

  func rasterize(svgContent: String) async throws -> CGImage {
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
      html, body { width: \(canvasSize)px; height: \(canvasSize)px; overflow: hidden; background: #1E6444; }
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
          self.continuation?.resume(throwing: NSError(domain: "MasterSVGRasterizer", code: -1))
        }
        self.continuation = nil
      }
    }
  }
}

func writeOpaqueRGBPNG(_ source: CGImage, size: Int, to url: URL) throws {
  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
  guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
  ) else {
    fatalError("CGContext creation failed")
  }

  ctx.interpolationQuality = .high
  ctx.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))

  guard let opaqueCG = ctx.makeImage() else {
    fatalError("makeImage failed")
  }

  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )

  guard let dest = CGImageDestinationCreateWithURL(
    url as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
  ) else {
    fatalError("CGImageDestination creation failed")
  }
  CGImageDestinationAddImage(dest, opaqueCG, nil)
  guard CGImageDestinationFinalize(dest) else {
    fatalError("PNG finalize failed")
  }
}

let args = CommandLine.arguments
let masterURL = URL(fileURLWithPath: args[1])
let iosDir = URL(fileURLWithPath: args[2])
let androidRes = URL(fileURLWithPath: args[3])

let svgContent = try String(contentsOf: masterURL, encoding: .utf8)

Task { @MainActor in
  do {
    _ = NSApplication.shared
    let rasterizer = MasterSVGRasterizer(canvasSize: 1024)
    let hiRes = try await rasterizer.rasterize(svgContent: svgContent)

    let iosOut = iosDir.appendingPathComponent("Icon-App-1024x1024@1x.png")
    try writeOpaqueRGBPNG(hiRes, size: 1024, to: iosOut)
    print("  iOS: Icon-App-1024x1024@1x.png (1024x1024, RGB)")

    let androidTargets: [(Int, String)] = [
      (48, "mipmap-mdpi"),
      (72, "mipmap-hdpi"),
      (96, "mipmap-xhdpi"),
      (144, "mipmap-xxhdpi"),
      (192, "mipmap-xxxhdpi"),
    ]
    for (px, dir) in androidTargets {
      let out = androidRes.appendingPathComponent(dir).appendingPathComponent("ic_launcher.png")
      try writeOpaqueRGBPNG(hiRes, size: px, to: out)
      print("  Android: \(dir)/ic_launcher.png (\(px)x\(px), RGB)")
    }
    exit(0)
  } catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
  }
}

RunLoop.main.run()
SWIFTEOF

echo "== iOS Dark / Tinted バリアントを生成 =="
swift "$repo_root/design/generate_ios_appearances.swift"

echo "完了。ios/ と android/ 配下のアイコンを更新しました。"
