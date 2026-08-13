import AppKit
import CoreGraphics
import Foundation

// Рисует иконку приложения: тёплый градиентный сквиркл со струнами и медиатором.
// Запуск: swift Tools/make-icon.swift <выходной .png>

let size = 1024
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

guard let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

let side = CGFloat(size)
// Поля как у системных иконок macOS.
let inset = side * 0.085
let rect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
let squircle = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225,
                      cornerHeight: rect.height * 0.225, transform: nil)

context.saveGState()
context.addPath(squircle)
context.clip()

let space = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.16, green: 0.11, blue: 0.13, alpha: 1),
    CGColor(red: 0.34, green: 0.16, blue: 0.10, alpha: 1),
    CGColor(red: 0.62, green: 0.30, blue: 0.11, alpha: 1),
] as CFArray, locations: [0.0, 0.55, 1.0])!
context.drawLinearGradient(gradient,
                           start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY),
                           options: [])

// Мягкий блик сверху — «стеклянность».
let sheen = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
] as CFArray, locations: [0.0, 1.0])!
context.drawRadialGradient(sheen,
                           startCenter: CGPoint(x: rect.midX, y: rect.maxY),
                           startRadius: 0,
                           endCenter: CGPoint(x: rect.midX, y: rect.maxY),
                           endRadius: rect.width * 0.85,
                           options: [])

// Шесть струн, уходящих в перспективу: толщина и яркость убывают.
let stringCount = 6
let top = rect.minY + rect.height * 0.20
let bottom = rect.maxY - rect.height * 0.20
for index in 0..<stringCount {
    let t = CGFloat(index) / CGFloat(stringCount - 1)
    let y = top + (bottom - top) * t
    let width = rect.width * (0.030 - 0.019 * t)
    context.setLineWidth(width)
    context.setStrokeColor(CGColor(red: 0.99, green: 0.86, blue: 0.70,
                                   alpha: 0.35 + 0.55 * (1 - t)))
    context.move(to: CGPoint(x: rect.minX + rect.width * 0.10, y: y))
    context.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.10, y: y))
    context.strokePath()
}

// Медиатор поверх струн.
let pickWidth = rect.width * 0.30
let pickHeight = pickWidth * 1.12
let pickRect = CGRect(x: rect.midX - pickWidth / 2,
                      y: rect.midY - pickHeight / 2,
                      width: pickWidth, height: pickHeight)
let pick = CGMutablePath()
pick.move(to: CGPoint(x: pickRect.midX, y: pickRect.minY))
pick.addCurve(to: CGPoint(x: pickRect.maxX, y: pickRect.maxY - pickHeight * 0.28),
              control1: CGPoint(x: pickRect.maxX - pickWidth * 0.10, y: pickRect.minY + pickHeight * 0.10),
              control2: CGPoint(x: pickRect.maxX, y: pickRect.maxY - pickHeight * 0.52))
pick.addCurve(to: CGPoint(x: pickRect.minX, y: pickRect.maxY - pickHeight * 0.28),
              control1: CGPoint(x: pickRect.maxX - pickWidth * 0.22, y: pickRect.maxY + pickHeight * 0.10),
              control2: CGPoint(x: pickRect.minX + pickWidth * 0.22, y: pickRect.maxY + pickHeight * 0.10))
pick.addCurve(to: CGPoint(x: pickRect.midX, y: pickRect.minY),
              control1: CGPoint(x: pickRect.minX, y: pickRect.maxY - pickHeight * 0.52),
              control2: CGPoint(x: pickRect.minX + pickWidth * 0.10, y: pickRect.minY + pickHeight * 0.10))
pick.closeSubpath()

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -side * 0.012),
                  blur: side * 0.03,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
context.addPath(pick)
context.setFillColor(CGColor(red: 0.99, green: 0.82, blue: 0.55, alpha: 1))
context.fillPath()
context.restoreGState()

context.addPath(pick)
context.clip()
let pickSheen = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.55),
    CGColor(red: 1, green: 0.72, blue: 0.30, alpha: 0.0),
] as CFArray, locations: [0.0, 1.0])!
context.drawLinearGradient(pickSheen,
                           start: CGPoint(x: pickRect.minX, y: pickRect.minY),
                           end: CGPoint(x: pickRect.maxX, y: pickRect.maxY),
                           options: [])

context.restoreGState()

guard let image = context.makeImage() else { exit(1) }
let bitmap = NSBitmapImageRep(cgImage: image)
guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: outputPath))
