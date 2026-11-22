#!/usr/bin/env swift
import AppKit
import Foundation

// QuickCopy 应用图标生成器。
//
// 设计：深蓝到紫的圆角方形背景，中央是一枚大号、两页重叠的
// “复制”图形，直接铺在蓝色底上，不使用胶囊容器。全部用
// CoreGraphics 绘制，方便以后微调颜色、比例，不依赖外部设计文件。
//
// 用法：swift tools/make_icon.swift
// 产物：QuickCopy/Resources/AppIcon.icns（以及 .iconset 中间文件）

let canvas: CGFloat = 1024
let inset: CGFloat = 100
let squircleRect = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
let squircleRadius: CGFloat = 185

let outputRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = outputRoot.appendingPathComponent("QuickCopy/Resources")
let iconset = outputRoot.appendingPathComponent("build/AppIcon.iconset")
let pngURL = outputRoot.appendingPathComponent("build/AppIcon-1024.png")

try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255
    let g = CGFloat((hex >> 8) & 0xFF) / 255
    let b = CGFloat(hex & 0xFF) / 255
    return CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
}

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas),
    pixelsHigh: Int(canvas),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
bitmap.size = NSSize(width: canvas, height: canvas)

NSGraphicsContext.saveGraphicsState()
let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.current = graphicsContext
let ctx = graphicsContext.cgContext

// 统一使用“左上角为原点、y 向下”的坐标系，方便按视觉顺序绘制。
ctx.translateBy(x: 0, y: canvas)
ctx.scaleBy(x: 1, y: -1)
ctx.setAllowsAntialiasing(true)
ctx.interpolationQuality = .high

let squircle = CGPath(
    roundedRect: squircleRect,
    cornerWidth: squircleRadius,
    cornerHeight: squircleRadius,
    transform: nil
)

// MARK: - 背景

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()

let background = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        color(0x8FB6FF),
        color(0x5578F2),
        color(0x6A4FE0),
        color(0x4B35B8)
    ] as CFArray,
    locations: [0.0, 0.42, 0.78, 1.0]
)!
ctx.drawLinearGradient(
    background,
    start: CGPoint(x: 160, y: 90),
    end: CGPoint(x: 900, y: 960),
    options: []
)

// 左上柔光
let glow = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0xFFFFFF, 0.42), color(0xFFFFFF, 0.0)] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: 300, y: 180),
    startRadius: 0,
    endCenter: CGPoint(x: 300, y: 180),
    endRadius: 520,
    options: []
)

// 斜向高光带，模拟玻璃表面的一道反光
let sheen = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        color(0xFFFFFF, 0.0),
        color(0xFFFFFF, 0.10),
        color(0xFFFFFF, 0.18),
        color(0xFFFFFF, 0.03),
        color(0xFFFFFF, 0.0)
    ] as CFArray,
    locations: [0.0, 0.30, 0.46, 0.62, 0.82]
)!
ctx.drawLinearGradient(
    sheen,
    start: CGPoint(x: 150, y: 880),
    end: CGPoint(x: 880, y: 100),
    options: []
)

// 底部轻微压暗，增加体积感
let vignette = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0x1B1450, 0.0), color(0x160F42, 0.34)] as CFArray,
    locations: [0.45, 1.0]
)!
ctx.drawRadialGradient(
    vignette,
    startCenter: CGPoint(x: 512, y: 470),
    startRadius: 230,
    endCenter: CGPoint(x: 512, y: 540),
    endRadius: 620,
    options: []
)
ctx.restoreGState()

// 细边框，让图标在浅色背景上也有边界
ctx.saveGState()
ctx.addPath(squircle)
ctx.setStrokeColor(color(0xFFFFFF, 0.20))
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

// 内侧高光圈：顶部更亮，底部几乎消失
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let rimRect = squircleRect.insetBy(dx: 9, dy: 9)
ctx.addPath(CGPath(roundedRect: rimRect, cornerWidth: 176, cornerHeight: 176, transform: nil))
ctx.setStrokeColor(color(0xFFFFFF, 0.16))
ctx.setLineWidth(2)
ctx.strokePath()
ctx.restoreGState()

// MARK: - 复制图形（两页重叠）

func roundedRectPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// 后面一页：略微旋转，半透明纸面，左侧露出几行淡淡的文字。
ctx.saveGState()
ctx.translateBy(x: 520, y: 512)
ctx.rotate(by: -9 * .pi / 180)

let backSheet = CGRect(x: -275, y: -190, width: 360, height: 430)
let backPath = roundedRectPath(backSheet, 62)

// 投影
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 5, height: 9), blur: 22, color: color(0x1A1140, 0.22))
ctx.addPath(backPath)
ctx.setFillColor(color(0xFFFFFF, 0.52))
ctx.fillPath()
ctx.restoreGState()

// 纸面渐变 + 内页文字线
ctx.saveGState()
ctx.addPath(backPath)
ctx.clip()

let backGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0xFFFFFF, 0.34), color(0xFFFFFF, 0.04)] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawLinearGradient(
    backGradient,
    start: CGPoint(x: backSheet.minX, y: backSheet.minY),
    end: CGPoint(x: backSheet.maxX, y: backSheet.maxY),
    options: []
)

let backLines: [(CGFloat, CGFloat)] = [
    (-102, 156),
    (-24, 124),
    (54, 92)
]
for (y, width) in backLines {
    let lineRect = CGRect(x: backSheet.minX + 54, y: y, width: width, height: 22)
    ctx.addPath(roundedRectPath(lineRect, 11))
    ctx.setFillColor(color(0x3F5CE0, 0.20))
    ctx.fillPath()
}
ctx.restoreGState()

// 边缘高光
ctx.addPath(backPath)
ctx.setStrokeColor(color(0xFFFFFF, 0.52))
ctx.setLineWidth(2)
ctx.strokePath()

ctx.restoreGState()

// 前面一页：右下角做折角处理，让纸张更有厚度和细节。
let frontSheet = CGRect(x: 380, y: 292, width: 380, height: 440)
let frontRadius: CGFloat = 62
let foldSize: CGFloat = 62

let frontPath = CGMutablePath()
frontPath.move(to: CGPoint(x: frontSheet.minX + frontRadius, y: frontSheet.minY))
frontPath.addLine(to: CGPoint(x: frontSheet.maxX - frontRadius, y: frontSheet.minY))
frontPath.addArc(
    tangent1End: CGPoint(x: frontSheet.maxX, y: frontSheet.minY),
    tangent2End: CGPoint(x: frontSheet.maxX, y: frontSheet.minY + frontRadius),
    radius: frontRadius
)
frontPath.addLine(to: CGPoint(x: frontSheet.maxX, y: frontSheet.maxY - foldSize))
frontPath.addLine(to: CGPoint(x: frontSheet.maxX - foldSize, y: frontSheet.maxY))
frontPath.addLine(to: CGPoint(x: frontSheet.minX + frontRadius, y: frontSheet.maxY))
frontPath.addArc(
    tangent1End: CGPoint(x: frontSheet.minX, y: frontSheet.maxY),
    tangent2End: CGPoint(x: frontSheet.minX, y: frontSheet.maxY - frontRadius),
    radius: frontRadius
)
frontPath.addLine(to: CGPoint(x: frontSheet.minX, y: frontSheet.minY + frontRadius))
frontPath.addArc(
    tangent1End: CGPoint(x: frontSheet.minX, y: frontSheet.minY),
    tangent2End: CGPoint(x: frontSheet.minX + frontRadius, y: frontSheet.minY),
    radius: frontRadius
)
frontPath.closeSubpath()

// 投影
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 26, color: color(0x1A1140, 0.28))
ctx.addPath(frontPath)
ctx.setFillColor(color(0xFFFFFF, 1.0))
ctx.fillPath()
ctx.restoreGState()

// 纸面渐变、底部淡紫阴影、顶部极轻的内高光
ctx.saveGState()
ctx.addPath(frontPath)
ctx.clip()

let frontGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0xFFFFFF, 1.0), color(0xF2F5FF, 1.0)] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawLinearGradient(
    frontGradient,
    start: CGPoint(x: frontSheet.minX, y: frontSheet.minY),
    end: CGPoint(x: frontSheet.maxX, y: frontSheet.maxY),
    options: []
)

let innerShade = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0xD5DFFF, 0.0), color(0xC9D6FF, 0.55)] as CFArray,
    locations: [0.55, 1.0]
)!
ctx.drawLinearGradient(
    innerShade,
    start: CGPoint(x: frontSheet.midX, y: frontSheet.minY + 210),
    end: CGPoint(x: frontSheet.midX, y: frontSheet.maxY),
    options: []
)

let topEdge = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0x1A1140, 0.10), color(0x1A1140, 0.0)] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawLinearGradient(
    topEdge,
    start: CGPoint(x: frontSheet.midX, y: frontSheet.minY),
    end: CGPoint(x: frontSheet.midX, y: frontSheet.minY + 26),
    options: []
)
ctx.restoreGState()

// 页面内几条渐变的“文字”线
let lines: [(CGFloat, CGFloat)] = [
    (195, 0.88),
    (155, 0.70),
    (115, 0.52)
]
for (index, line) in lines.enumerated() {
    let lineRect = CGRect(
        x: frontSheet.minX + 78,
        y: frontSheet.minY + 112 + CGFloat(index) * 78,
        width: line.0,
        height: 28
    )
    ctx.saveGState()
    ctx.addPath(roundedRectPath(lineRect, 14))
    ctx.clip()
    let lineGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0x4667E8, line.1), color(0x8AA0FF, line.1 * 0.68)] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(
        lineGradient,
        start: CGPoint(x: lineRect.minX, y: lineRect.midY),
        end: CGPoint(x: lineRect.maxX, y: lineRect.midY),
        options: []
    )
    ctx.restoreGState()
}

// 折角：外翻的浅紫灰色小三角 + 折线高光
let foldTip = CGPoint(x: frontSheet.maxX - foldSize, y: frontSheet.maxY - foldSize)
let foldPath = CGMutablePath()
foldPath.move(to: CGPoint(x: frontSheet.maxX - foldSize, y: frontSheet.maxY))
foldPath.addLine(to: CGPoint(x: frontSheet.maxX, y: frontSheet.maxY - foldSize))
foldPath.addLine(to: foldTip)
foldPath.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 3, height: 5), blur: 12, color: color(0x1A1140, 0.24))
ctx.addPath(foldPath)
ctx.setFillColor(color(0xDCE4FF, 1.0))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(foldPath)
ctx.clip()
let foldGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0xB9C9F8, 1.0), color(0xF7F9FF, 1.0)] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawLinearGradient(
    foldGradient,
    start: CGPoint(x: frontSheet.maxX - foldSize / 2, y: frontSheet.maxY - foldSize / 2),
    end: foldTip,
    options: []
)
ctx.restoreGState()

ctx.addPath(foldPath)
ctx.setStrokeColor(color(0xFFFFFF, 0.90))
ctx.setLineWidth(2)
ctx.strokePath()

// 整页的细边，勾出纸的轮廓
ctx.addPath(frontPath)
ctx.setStrokeColor(color(0xFFFFFF, 0.95))
ctx.setLineWidth(2)
ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()

// MARK: - 输出

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("PNG encoding failed")
}
try pngData.write(to: pngURL)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in sizes {
    let target = iconset.appendingPathComponent(name)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", "\(size)", "\(size)", pngURL.path, "--out", target.path]
    try process.run()
    process.waitUntilExit()
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()

print("Wrote \(resources.appendingPathComponent("AppIcon.icns").path)")
print("Preview \(pngURL.path)")
