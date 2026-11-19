#!/usr/bin/env swift
// Generates the app icon of myTracks Loader (change rename-and-icon, design D4): the vertical gradient of
// myTracks Neo with a white satellite in line art. One geometry feeds the PNGs (CoreGraphics) and the SVG layer
// of the Icon Composer file, so previews and app icon match.
//
// Usage:
//   swift Scripts/make-app-icon.swift preview [--variant <n>] <directory>   1024 px previews (full-bleed and macOS shape)
//   swift Scripts/make-app-icon.swift generate --variant <n>                writes App/AppIcon.icon
//
// Chosen by the developer on 2026-11-19: variant 3 (`generate --variant 3`).
//
// Output is deterministic: the same variant always gives the same bytes.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Colors and geometry

/// Gradient of the myTracks Neo icon, read from its 1024 px PNG: top #1A46DE, bottom #9F199C.
let gradientTop = (r: 0x1A, g: 0x46, b: 0xDE)
let gradientBottom = (r: 0x9F, g: 0x19, b: 0x9C)
/// Line width of the globe in the myTracks Neo icon, in px of a 1024 px canvas.
let lineWidth: CGFloat = 26

/// A stroked primitive in a 1024 × 1024 canvas, y pointing down (as in SVG).
enum Shape {
    case line(CGPoint, CGPoint)
    case roundedRect(CGRect, radius: CGFloat)
    /// Arc around `center` from `start` to `end` degrees (0° = right, clockwise as in SVG).
    case arc(center: CGPoint, radius: CGFloat, start: CGFloat, end: CGFloat)
    case circle(center: CGPoint, radius: CGFloat)
}

/// A satellite: body, two solar wings with grid, a dish with antenna and radio waves. Built along the x axis around
/// the origin, then rotated and scaled into the canvas.
struct Satellite {
    var rotation: CGFloat        // degrees, counter-clockwise on screen
    var scale: CGFloat
    var center: CGPoint
    var wingCells: Int           // cells along each wing
    var waves: Int               // radio waves at the dish
    var orbit: Bool              // an orbit ellipse behind the satellite

    func shapes() -> [Shape] {
        var local: [Shape] = []
        // Body and struts
        local.append(.roundedRect(CGRect(x: -62, y: -92, width: 124, height: 184), radius: 24))
        local.append(.line(CGPoint(x: -62, y: 0), CGPoint(x: -104, y: 0)))
        local.append(.line(CGPoint(x: 62, y: 0), CGPoint(x: 104, y: 0)))
        // Wings with a grid
        for side in [-1.0, 1.0] as [CGFloat] {
            let inner: CGFloat = 104, outer: CGFloat = 104 + 90 * CGFloat(wingCells)
            let x0 = side < 0 ? -outer : inner
            local.append(.roundedRect(CGRect(x: x0, y: -96, width: outer - inner, height: 192), radius: 10))
            for cell in 1..<wingCells {
                let x = side * (inner + 90 * CGFloat(cell))
                local.append(.line(CGPoint(x: x, y: -96), CGPoint(x: x, y: 96)))
            }
            local.append(.line(CGPoint(x: side * inner, y: 0), CGPoint(x: side * outer, y: 0)))
        }
        // Dish on top of the body (negative y is up): stem, cup, feed
        local.append(.line(CGPoint(x: 0, y: -92), CGPoint(x: 0, y: -128)))
        local.append(.arc(center: CGPoint(x: 0, y: -196), radius: 70, start: 25, end: 155))
        local.append(.line(CGPoint(x: 0, y: -158), CGPoint(x: 0, y: -214)))
        // Radio waves above the dish
        for index in 0..<waves {
            local.append(.arc(center: CGPoint(x: 0, y: -222), radius: 70 + 56 * CGFloat(index), start: 235, end: 305))
        }
        var result = local.map(transform)
        if orbit {
            result.insert(.arc(center: center, radius: 400 * scale, start: 200, end: 250), at: 0)
            result.insert(.arc(center: center, radius: 400 * scale, start: 20, end: 70), at: 0)
        }
        return result
    }

    private func transform(_ point: CGPoint) -> CGPoint {
        let a = -rotation * .pi / 180
        let x = point.x * cos(a) - point.y * sin(a), y = point.x * sin(a) + point.y * cos(a)
        return CGPoint(x: center.x + x * scale, y: center.y + y * scale)
    }

    private func transform(_ shape: Shape) -> Shape {
        switch shape {
        case let .line(a, b): return .line(transform(a), transform(b))
        case let .circle(c, r): return .circle(center: transform(c), radius: r * scale)
        case let .arc(c, r, s, e): return .arc(center: transform(c), radius: r * scale, start: s - rotation, end: e - rotation)
        case .roundedRect:
            // Stays in local coordinates; `path(for:)` rotates it.
            return shape
        }
    }

    /// Rectangles are rotated here, because a rotated rectangle is no longer a CGRect.
    func path(for shape: Shape) -> CGPath {
        guard case let .roundedRect(rect, radius) = shape else { return Self.plainPath(for: shape) }
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: -rotation * .pi / 180).scaledBy(x: scale, y: scale)
        let path = CGMutablePath()
        path.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil), transform: transform)
        return path
    }

    static func plainPath(for shape: Shape) -> CGPath {
        let path = CGMutablePath()
        switch shape {
        case let .line(a, b): path.move(to: a); path.addLine(to: b)
        case let .circle(c, r): path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        case let .arc(c, r, s, e):
            path.addArc(center: c, radius: r, startAngle: s * .pi / 180, endAngle: e * .pi / 180, clockwise: false)
        case let .roundedRect(rect, radius): path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        }
        return path
    }
}

/// The variants shown to the developer (task 3.1).
let variants: [Int: (title: String, satellite: Satellite)] = [
    1: ("Satellite diagonal, two radio waves",
        Satellite(rotation: 45, scale: 0.92, center: CGPoint(x: 512, y: 540), wingCells: 3, waves: 2, orbit: false)),
    2: ("Satellite with orbit, one radio wave",
        Satellite(rotation: 45, scale: 0.78, center: CGPoint(x: 512, y: 530), wingCells: 3, waves: 1, orbit: true)),
    3: ("Satellite horizontal, three radio waves",
        Satellite(rotation: 0, scale: 0.98, center: CGPoint(x: 512, y: 620), wingCells: 3, waves: 3, orbit: false)),
]

// MARK: - Rendering

enum Shape2 { case fullBleed, macOS }

func render(_ satellite: Satellite, size: Int, shape: Shape2, background: Bool = true, glyph: Bool = true) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let k = CGFloat(size) / 1024
    // Flip to y down, scale to 1024 units.
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: k, y: -k)
    context.interpolationQuality = .high

    // macOS shape (Big Sur grid): 824 × 824 rounded square inside the 1024 canvas, radius 185, soft shadow.
    let tile = shape == .macOS ? CGRect(x: 100, y: 100, width: 824, height: 824) : CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: shape == .macOS ? 185 : 0, cornerHeight: shape == .macOS ? 185 : 0,
                          transform: nil)
    if background {
        if shape == .macOS {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: CGColor(gray: 0, alpha: 0.30))
            context.addPath(tilePath); context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fillPath()
            context.restoreGState()
        }
        context.saveGState()
        context.addPath(tilePath); context.clip()
        func color(_ c: (r: Int, g: Int, b: Int)) -> CGColor {
            CGColor(colorSpace: space, components: [CGFloat(c.r) / 255, CGFloat(c.g) / 255, CGFloat(c.b) / 255, 1])!
        }
        let gradient = CGGradient(colorsSpace: space, colors: [color(gradientTop), color(gradientBottom)] as CFArray,
                                  locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: tile.minY), end: CGPoint(x: 512, y: tile.maxY), options: [])
        context.restoreGState()
    }
    if glyph {
        context.saveGState()
        if shape == .macOS {
            // The artwork shrinks with the tile so it keeps its margins.
            context.translateBy(x: 512, y: 512); context.scaleBy(x: 824 / 1024, y: 824 / 1024); context.translateBy(x: -512, y: -512)
        }
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for item in satellite.shapes() {
            context.addPath(satellite.path(for: item))
            context.strokePath()
        }
        context.restoreGState()
    }
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "make-app-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot write \(url.path)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "make-app-icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot write \(url.path)"])
    }
}

// MARK: - Icon Composer and asset catalog

/// The satellite as SVG (white strokes on transparent ground, 1024 × 1024), the foreground layer of `AppIcon.icon`.
func svg(_ satellite: Satellite) -> String {
    func f(_ v: CGFloat) -> String { String(format: "%.2f", Double(v)) }
    var elements: [String] = []
    for shape in satellite.shapes() {
        switch shape {
        case let .line(a, b):
            elements.append("<line x1=\"\(f(a.x))\" y1=\"\(f(a.y))\" x2=\"\(f(b.x))\" y2=\"\(f(b.y))\"/>")
        case let .circle(c, r):
            elements.append("<circle cx=\"\(f(c.x))\" cy=\"\(f(c.y))\" r=\"\(f(r))\"/>")
        case let .arc(c, r, start, end):
            let a0 = start * .pi / 180, a1 = end * .pi / 180
            let p0 = CGPoint(x: c.x + r * cos(a0), y: c.y + r * sin(a0)), p1 = CGPoint(x: c.x + r * cos(a1), y: c.y + r * sin(a1))
            let large = (end - start).truncatingRemainder(dividingBy: 360) > 180 ? 1 : 0
            elements.append("<path d=\"M \(f(p0.x)) \(f(p0.y)) A \(f(r)) \(f(r)) 0 \(large) 1 \(f(p1.x)) \(f(p1.y))\"/>")
        case let .roundedRect(rect, radius):
            let t = "translate(\(f(satellite.center.x)) \(f(satellite.center.y))) rotate(\(f(-satellite.rotation))) scale(\(f(satellite.scale)))"
            elements.append("<rect transform=\"\(t)\" x=\"\(f(rect.minX))\" y=\"\(f(rect.minY))\" width=\"\(f(rect.width))\" height=\"\(f(rect.height))\" rx=\"\(f(radius))\"/>")
        }
    }
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
    <g fill="none" stroke="#FFFFFF" stroke-width="\(f(lineWidth))" stroke-linecap="round" stroke-linejoin="round">
    \(elements.joined(separator: "\n"))
    </g>
    </svg>

    """
}

/// `icon.json` of `AppIcon.icon`: the gradient as fill, the satellite as the only layer; the system adds shape and glass.
func iconJSON() -> String {
    func srgb(_ c: (r: Int, g: Int, b: Int)) -> String {
        String(format: "srgb:%.5f,%.5f,%.5f,1.00000", Double(c.r) / 255, Double(c.g) / 255, Double(c.b) / 255)
    }
    return """
    {
      "fill" : {
        "linear-gradient" : [
          "\(srgb(gradientTop))",
          "\(srgb(gradientBottom))"
        ],
        "orientation" : {
          "start" : { "x" : 0.5, "y" : 0 },
          "stop" : { "x" : 0.5, "y" : 1 }
        }
      },
      "groups" : [
        {
          "layers" : [
            { "image-name" : "satellite.svg", "name" : "satellite" }
          ],
          "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
          "translucency" : { "enabled" : true, "value" : 0.5 }
        }
      ],
      "supported-platforms" : {
        "squares" : [ "macOS" ]
      }
    }

    """
}

/// Writes `App/AppIcon.icon`. Xcode renders all sizes for macOS 12–15 from it (Assets.car and AppIcon.icns), so there
/// is no separate `appiconset` (design D4, checked with actool of Xcode 27.1).
func generate(_ satellite: Satellite, root: URL) throws {
    let icon = root.appendingPathComponent("App/AppIcon.icon", isDirectory: true)
    try FileManager.default.createDirectory(at: icon.appendingPathComponent("Assets"), withIntermediateDirectories: true)
    try svg(satellite).write(to: icon.appendingPathComponent("Assets/satellite.svg"), atomically: true, encoding: .utf8)
    try iconJSON().write(to: icon.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
}

// MARK: - Command line

var arguments = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...index + 1)
    return value
}
let mode = arguments.first ?? ""
arguments = Array(arguments.dropFirst())
let chosen = option("--variant").flatMap(Int.init)

switch mode {
case "preview":
    guard let directory = arguments.first else { print("usage: preview [--variant <n>] <directory>"); exit(2) }
    let out = URL(fileURLWithPath: directory, isDirectory: true)
    for (number, variant) in variants.sorted(by: { $0.key < $1.key }) where chosen == nil || chosen == number {
        try writePNG(render(variant.satellite, size: 1024, shape: .fullBleed), to: out.appendingPathComponent("variant-\(number)-full.png"))
        try writePNG(render(variant.satellite, size: 1024, shape: .macOS), to: out.appendingPathComponent("variant-\(number)-macos.png"))
        print("variant \(number): \(variant.title)")
    }
case "generate":
    guard let number = chosen, let variant = variants[number] else { print("usage: generate --variant <n>"); exit(2) }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    try generate(variant.satellite, root: root)
    print("generated variant \(number) (\(variant.title)) into App/AppIcon.icon")
default:
    print("usage: make-app-icon.swift preview [--variant <n>] <directory> | generate --variant <n>")
    exit(2)
}
