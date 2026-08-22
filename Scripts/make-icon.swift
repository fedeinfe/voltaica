// Renders the app icon from the same SwiftUI vocabulary as the app itself, then writes the
// iconset PNGs. Run with: swift Scripts/make-icon.swift
import AppKit
import SwiftUI

let mint = Color(.sRGB, red: 0.482, green: 0.941, blue: 0.753, opacity: 1)
let cyan = Color(.sRGB, red: 0.208, green: 0.788, blue: 0.910, opacity: 1)

struct IconView: View {
    private let corner: CGFloat = 196

    var body: some View {
        ZStack {
            body_
        }
        .frame(width: 1024, height: 1024)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: corner, style: .continuous) }

    private var body_: some View {
        ZStack {
            background
            battery
                .frame(width: 1024, height: 1024)
        }
        // Everything is clipped to the body: a glow that escapes the icon shape reads as a bug.
        .frame(width: 856, height: 856)
        .clipShape(shape)
        .overlay {
            shape.fill(
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.22), location: 0),
                    .init(color: .white.opacity(0.04), location: 0.28),
                    .init(color: .clear, location: 0.55)
                ], startPoint: .top, endPoint: .bottom)
            )
        }
        .overlay {
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.06)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 4
            )
        }
        .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(.sRGB, red: 0.075, green: 0.128, blue: 0.152, opacity: 1),
                                    Color(.sRGB, red: 0.020, green: 0.031, blue: 0.043, opacity: 1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [cyan.opacity(0.55), .clear],
                           center: .init(x: 0.5, y: 0.95),
                           startRadius: 0, endRadius: 620)
            RadialGradient(colors: [mint.opacity(0.30), .clear],
                           center: .init(x: 0.10, y: 0.04),
                           startRadius: 0, endRadius: 480)
            // A sheen band across the glass, the way light falls on a polished surface.
            LinearGradient(stops: [
                .init(color: .clear, location: 0.30),
                .init(color: .white.opacity(0.10), location: 0.46),
                .init(color: .white.opacity(0.02), location: 0.52),
                .init(color: .clear, location: 0.62)
            ], startPoint: .topTrailing, endPoint: .bottomLeading)
        }
    }

    /// A battery standing on end, filled to the level a charge limit would hold it at.
    private var battery: some View {
        let width: CGFloat = 372
        let height: CGFloat = 534
        let level: CGFloat = 0.78
        let wall: CGFloat = 24

        return VStack(spacing: 0) {
            // Terminal
            Capsule(style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.62)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 148, height: 42)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                .padding(.bottom, 12)

            ZStack {
                RoundedRectangle(cornerRadius: 74, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.96), .white.opacity(0.55)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: wall
                    )

                GeometryReader { geometry in
                    let inner = geometry.size
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 74 - wall, style: .continuous)
                            .fill(Color.black.opacity(0.28))

                        // The liquid
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(LinearGradient(colors: [mint, cyan],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                // The meniscus: a bright surface line is what makes it read as liquid.
                                .overlay(alignment: .top) {
                                    ZStack(alignment: .top) {
                                        Rectangle()
                                            .fill(Color.white.opacity(0.92))
                                            .frame(height: 9)
                                            .blur(radius: 1)
                                        LinearGradient(colors: [.white.opacity(0.45), .clear],
                                                       startPoint: .top, endPoint: .bottom)
                                            .frame(height: 46)
                                    }
                                }
                                .overlay(alignment: .topLeading) {
                                    // Specular highlight down the left wall.
                                    Capsule()
                                        .fill(
                                            LinearGradient(colors: [.white.opacity(0.62), .white.opacity(0.05)],
                                                           startPoint: .top, endPoint: .bottom)
                                        )
                                        .frame(width: 26, height: inner.height * 0.46)
                                        .blur(radius: 5)
                                        .padding(.leading, 34)
                                        .padding(.top, 40)
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    RadialGradient(colors: [.white.opacity(0.22), .clear],
                                                   center: .bottomTrailing,
                                                   startRadius: 0, endRadius: 190)
                                }
                        }
                        .frame(height: inner.height * level)
                        .shadow(color: cyan.opacity(0.9), radius: 44)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 74 - wall, style: .continuous))
                }
                .padding(wall)
            }
            .frame(width: width, height: height)
        }
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: IconView())
    renderer.scale = 1
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("could not render icon\n".utf8))
        exit(1)
    }
    let url = URL(fileURLWithPath: "build/icon-1024.png")
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    try! png.write(to: url)
    print("wrote \(url.path)")
}
