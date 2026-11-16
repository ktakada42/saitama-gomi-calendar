#!/usr/bin/env swift
// design/app_icon_master.svg と同じベクター座標から、iOS の Dark / Tinted（および
// iOS 26 のクリア＝Liquid Glass 表示）向け 1024x1024 アイコンを生成する。
//
// Light（通常表示）はアルファなしの既存 Icon-App-1024x1024@1x.png をそのまま使う。
// Dark / Tinted は背景を透過にしておくことで、iOS がダークプレートや Liquid Glass の
// 屈折レイヤーをモチーフの背後に合成できるようにする。

import AppKit
import CoreGraphics
import Foundation

let size = 1024
let viewBox: CGFloat = 120.0

func makeBagPath() -> CGPath {
  let p = CGMutablePath()
  p.move(to: CGPoint(x: 46, y: 30))
  p.addCurve(to: CGPoint(x: 16, y: 60), control1: CGPoint(x: 30, y: 34), control2: CGPoint(x: 20, y: 45))
  p.addCurve(to: CGPoint(x: 12, y: 98), control1: CGPoint(x: 13, y: 72), control2: CGPoint(x: 12, y: 85))
  p.addCurve(to: CGPoint(x: 20, y: 109), control1: CGPoint(x: 12, y: 103), control2: CGPoint(x: 14, y: 106))
  p.addCurve(to: CGPoint(x: 60, y: 113), control1: CGPoint(x: 35, y: 112), control2: CGPoint(x: 48, y: 113))
  p.addCurve(to: CGPoint(x: 100, y: 109), control1: CGPoint(x: 72, y: 113), control2: CGPoint(x: 85, y: 112))
  p.addCurve(to: CGPoint(x: 108, y: 98), control1: CGPoint(x: 106, y: 106), control2: CGPoint(x: 108, y: 103))
  p.addCurve(to: CGPoint(x: 104, y: 60), control1: CGPoint(x: 108, y: 85), control2: CGPoint(x: 107, y: 72))
  p.addCurve(to: CGPoint(x: 74, y: 30), control1: CGPoint(x: 100, y: 45), control2: CGPoint(x: 90, y: 34))
  p.addCurve(to: CGPoint(x: 60, y: 27), control1: CGPoint(x: 68, y: 27), control2: CGPoint(x: 64, y: 26))
  p.addCurve(to: CGPoint(x: 46, y: 30), control1: CGPoint(x: 56, y: 26), control2: CGPoint(x: 52, y: 27))
  p.closeSubpath()
  return p
}

func makeCrease1() -> CGPath {
  let p = CGMutablePath()
  p.move(to: CGPoint(x: 40, y: 52))
  p.addCurve(to: CGPoint(x: 44, y: 74), control1: CGPoint(x: 36, y: 60), control2: CGPoint(x: 38, y: 70))
  p.addCurve(to: CGPoint(x: 46, y: 52), control1: CGPoint(x: 42, y: 64), control2: CGPoint(x: 42, y: 58))
  p.closeSubpath()
  return p
}

func makeCrease2() -> CGPath {
  let p = CGMutablePath()
  p.move(to: CGPoint(x: 64, y: 50))
  p.addCurve(to: CGPoint(x: 68, y: 64), control1: CGPoint(x: 62, y: 56), control2: CGPoint(x: 64, y: 62))
  p.addCurve(to: CGPoint(x: 69, y: 50), control1: CGPoint(x: 67, y: 58), control2: CGPoint(x: 67, y: 54))
  p.closeSubpath()
  return p
}

func makeCreaseLeft() -> CGPath {
  let p = CGMutablePath()
  p.move(to: CGPoint(x: 20, y: 75))
  p.addCurve(to: CGPoint(x: 24, y: 99), control1: CGPoint(x: 17, y: 85), control2: CGPoint(x: 18, y: 94))
  p.addCurve(to: CGPoint(x: 24, y: 75), control1: CGPoint(x: 22, y: 90), control2: CGPoint(x: 21, y: 83))
  p.closeSubpath()
  return p
}

func makeCreaseRight() -> CGPath {
  let p = CGMutablePath()
  p.move(to: CGPoint(x: 100, y: 75))
  p.addCurve(to: CGPoint(x: 96, y: 99), control1: CGPoint(x: 103, y: 85), control2: CGPoint(x: 102, y: 94))
  p.addCurve(to: CGPoint(x: 96, y: 75), control1: CGPoint(x: 98, y: 90), control2: CGPoint(x: 99, y: 83))
  p.closeSubpath()
  return p
}

func makeEarLeft() -> CGPath {
  let p = CGMutablePath()
  p.move(to: CGPoint(x: 60, y: 21))
  p.addCurve(to: CGPoint(x: 37, y: 17), control1: CGPoint(x: 51, y: 15), control2: CGPoint(x: 42, y: 13))
  p.addCurve(to: CGPoint(x: 60, y: 27), control1: CGPoint(x: 40, y: 22), control2: CGPoint(x: 49, y: 26))
  p.closeSubpath()
  return p
}

func makeEarRight() -> CGPath {
  let p = CGMutablePath()
  p.move(to: CGPoint(x: 60, y: 21))
  p.addCurve(to: CGPoint(x: 83, y: 17), control1: CGPoint(x: 69, y: 15), control2: CGPoint(x: 78, y: 13))
  p.addCurve(to: CGPoint(x: 60, y: 27), control1: CGPoint(x: 80, y: 22), control2: CGPoint(x: 71, y: 26))
  p.closeSubpath()
  return p
}

func makeKnot() -> CGPath {
  CGPath(
    ellipseIn: CGRect(x: 60 - 4.6, y: 22 - 4.6, width: 9.2, height: 9.2),
    transform: nil
  )
}

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
  CGColor(srgbRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
}

func renderIcon(to url: URL, draw: (CGContext) -> Void) throws {
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

  ctx.setAllowsAntialiasing(true)
  ctx.setShouldAntialias(true)
  // CoreGraphics は左下原点なので、SVG の左上原点（120x120）に合わせる。
  ctx.translateBy(x: 0, y: CGFloat(size))
  let scale = CGFloat(size) / viewBox
  ctx.scaleBy(x: scale, y: -scale)
  ctx.setLineJoin(.round)
  ctx.setLineCap(.round)

  draw(ctx)

  guard let cgImage = ctx.makeImage() else {
    fatalError("makeImage failed")
  }
  let rep = NSBitmapImageRep(cgImage: cgImage)
  guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG encoding failed")
  }
  try pngData.write(to: url)
}

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let appIconDir = repoRoot.appendingPathComponent("ios/Runner/Assets.xcassets/AppIcon.appiconset")

let bag = makeBagPath()
let c1 = makeCrease1()
let c2 = makeCrease2()
let cl = makeCreaseLeft()
let cr = makeCreaseRight()
let el = makeEarLeft()
let er = makeEarRight()
let knot = makeKnot()

func fillAndStroke(_ ctx: CGContext, path: CGPath, fill: CGColor, stroke: CGColor, width: CGFloat) {
  ctx.addPath(path)
  ctx.setFillColor(fill)
  ctx.fillPath()
  ctx.addPath(path)
  ctx.setStrokeColor(stroke)
  ctx.setLineWidth(width)
  ctx.strokePath()
}

// 1. Dark バリアント：透過背景（OS がダークプレートやダークガラスを敷く）＋
//    視認性の高いグリーンのアウトラインと落ち着いたライトグリーンの袋。
let darkURL = appIconDir.appendingPathComponent("Icon-App-Dark-1024x1024@1x.png")
try renderIcon(to: darkURL) { ctx in
  let bagFill = rgba(232, 245, 237)
  let bagStroke = rgba(47, 122, 79)
  fillAndStroke(ctx, path: bag, fill: bagFill, stroke: bagStroke, width: 2.8)

  ctx.addPath(c1)
  ctx.setFillColor(rgba(143, 189, 162, 0.85))
  ctx.fillPath()

  ctx.addPath(c2)
  ctx.setFillColor(rgba(143, 189, 162, 0.85))
  ctx.fillPath()

  ctx.addPath(cl)
  ctx.setFillColor(rgba(122, 168, 141, 0.7))
  ctx.fillPath()

  ctx.addPath(cr)
  ctx.setFillColor(rgba(122, 168, 141, 0.7))
  ctx.fillPath()

  fillAndStroke(ctx, path: el, fill: bagFill, stroke: bagStroke, width: 2.4)
  fillAndStroke(ctx, path: er, fill: bagFill, stroke: bagStroke, width: 2.4)
  fillAndStroke(ctx, path: knot, fill: bagFill, stroke: bagStroke, width: 2.4)
}

// 2. Tinted / Clear（Liquid Glass）バリアント：透過背景＋グレースケール濃淡マスク。
//    結び目やシワの境界をアウトラインの減算（destinationOut）で抜くことで、
//    単色ティントやガラス屈折でもゴミ袋のディテールが潰れずに立体的に出る。
let tintedURL = appIconDir.appendingPathComponent("Icon-App-Tinted-1024x1024@1x.png")
try renderIcon(to: tintedURL) { ctx in
  let white = rgba(255, 255, 255, 0.96)

  ctx.addPath(bag)
  ctx.setFillColor(white)
  ctx.fillPath()

  // シワ部分を少し抜いてガラスの陰影差を作る
  ctx.saveGState()
  ctx.setBlendMode(.destinationOut)
  for (path, alpha) in [(c1, 0.30), (c2, 0.30), (cl, 0.25), (cr, 0.25)] {
    ctx.addPath(path)
    ctx.setFillColor(rgba(0, 0, 0, alpha))
    ctx.fillPath()
  }
  ctx.restoreGState()

  // 結び目の耳と中央の結び目をクリアな隙間付きで重ねる
  for path in [el, er, knot] {
    ctx.saveGState()
    ctx.setBlendMode(.destinationOut)
    ctx.addPath(path)
    ctx.setStrokeColor(rgba(0, 0, 0, 1.0))
    ctx.setLineWidth(3.0)
    ctx.strokePath()
    ctx.restoreGState()

    ctx.addPath(path)
    ctx.setFillColor(rgba(255, 255, 255, 1.0))
    ctx.fillPath()
  }
}

print("Generated Dark and Tinted icons in \(appIconDir.path)")
