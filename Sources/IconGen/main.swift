import SwiftUI
import AppKit
import PiBrand

@MainActor
func render(_ px: Int, to url: URL) {
    let r = ImageRenderer(content: AppIconArtwork().frame(width: 1024, height: 1024))
    r.scale = CGFloat(px) / 1024
    guard let cg = r.cgImage else { print("render failed"); return }
    let rep = NSBitmapImageRep(cgImage: cg)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

@MainActor
func main() {
    let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let sizes: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                                  ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
    for (name, px) in sizes { render(px, to: out.appendingPathComponent("icon_\(name).png")) }
    render(1024, to: out.deletingLastPathComponent().appendingPathComponent("logo-1024.png"))
}
MainActor.assumeIsolated { main() }
