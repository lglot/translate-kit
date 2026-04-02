#!/usr/bin/env swift
import Cocoa
import CoreGraphics

func createIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // Background gradient (blue to indigo)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.20, green: 0.40, blue: 0.90, alpha: 1.0),   // Blue
            CGColor(red: 0.40, green: 0.20, blue: 0.85, alpha: 1.0),   // Indigo
        ] as CFArray,
        locations: [0.0, 1.0]
    )!

    // Rounded rect background
    let cornerRadius = s * 0.22
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                        cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                        transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient,
                          start: CGPoint(x: 0, y: s),
                          end: CGPoint(x: s, y: 0),
                          options: [])

    // Globe circle (background for symbol)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.15))
    let circleRect = CGRect(
        x: s * 0.5 - s * 0.30,
        y: s * 0.5 - s * 0.30,
        width: s * 0.60,
        height: s * 0.60
    )
    ctx.fillEllipse(in: circleRect)

    // Translate "A→文" symbol using text
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))

    // Draw "A→" part
    let arrowFont = NSFont.systemFont(ofSize: s * 0.32, weight: .bold)
    let arrowAttrs: [NSAttributedString.Key: Any] = [
        .font: arrowFont,
        .foregroundColor: NSColor.white
    ]

    // "A" on the left
    let aString = NSAttributedString(string: "A", attributes: arrowAttrs)
    let aSize = aString.size()
    aString.draw(at: CGPoint(x: s * 0.18, y: s * 0.50 - aSize.height / 2))

    // Arrow "→" in the center
    let arrowString = NSAttributedString(string: "→", attributes: [
        .font: NSFont.systemFont(ofSize: s * 0.28, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.9)
    ])
    let arrowSize = arrowString.size()
    arrowString.draw(at: CGPoint(x: s * 0.38, y: s * 0.50 - arrowSize.height / 2))

    // "文" (Chinese character for "text/language") on the right
    let zhFont = NSFont.systemFont(ofSize: s * 0.30, weight: .bold)
    let zhAttrs: [NSAttributedString.Key: Any] = [
        .font: zhFont,
        .foregroundColor: NSColor.white
    ]
    let zhString = NSAttributedString(string: "文", attributes: zhAttrs)
    let zhSize = zhString.size()
    zhString.draw(at: CGPoint(x: s * 0.62, y: s * 0.50 - zhSize.height / 2))

    image.unlockFocus()
    return image
}

func saveIcon(_ image: NSImage, to path: String, size: Int) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for \(path)")
        return
    }
    try? pngData.write(to: URL(fileURLWithPath: path))
    print("Saved \(path) (\(size)x\(size))")
}

// Generate all required icon sizes
let sizes = [
    (16, "icon_16x16"),
    (32, "icon_16x16@2x"),
    (32, "icon_32x32"),
    (64, "icon_32x32@2x"),
    (128, "icon_128x128"),
    (256, "icon_128x128@2x"),
    (256, "icon_256x256"),
    (512, "icon_256x256@2x"),
    (512, "icon_512x512"),
    (1024, "icon_512x512@2x"),
]

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let iconsetDir = "\(outputDir)/AppIcon.iconset"

try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for (size, name) in sizes {
    let img = createIcon(size: size)
    saveIcon(img, to: "\(iconsetDir)/\(name).png", size: size)
}

// Also save a 1024px master
let master = createIcon(size: 1024)
saveIcon(master, to: "\(outputDir)/icon.png", size: 1024)

print("\nDone! Use: iconutil -c icns \(iconsetDir)")
