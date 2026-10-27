import MemWholeKit
import SwiftUI

/// A trashed note's row being forgotten: it blurs and fades like a hazy memory, then crumbles into
/// dust that drifts up and away, left to right. Drawn over the list, where the row was.
struct ForgetEffect: View {
    let hit: Hit
    let size: CGSize

    /// Until the blur gives way to dust.
    static let blurTime = 0.25
    /// How long the crumbling takes to sweep from the left edge to the right.
    static let sweepTime = 0.3
    /// The longest a speck lives once it lifts off.
    static let maxLife = 0.65
    static let duration = Duration.seconds(blurTime + sweepTime + maxLife + 0.1)
    /// When the rows below start closing the gap.
    static let gapDelay = Duration.seconds(blurTime + 0.15)

    /// Points per speck side.
    private static let cell: CGFloat = 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var start = Date()
    @State private var specks: [Speck] = []

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            ZStack(alignment: .topLeading) {
                ghost(at: t)
                if !reduceMotion {
                    Canvas { context, _ in draw(specks, at: t - Self.blurTime, in: &context) }
                        .frame(width: size.width, height: size.height)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            start = Date()
            if !reduceMotion { specks = makeSpecks() }
        }
    }

    private var row: some View {
        HitRow(hit: hit).frame(width: size.width, height: size.height, alignment: .leading)
    }

    /// The row itself, hazing over; it hands off to the specks as they appear.
    private func ghost(at t: Double) -> some View {
        let haze = min(t / Self.blurTime, 1)
        let handoff = reduceMotion ? haze : max(0, min((t - Self.blurTime) / 0.08, 1))
        return row
            .blur(radius: reduceMotion ? 0 : 2.5 * haze)
            .saturation(1 - haze)
            .opacity((1 - 0.35 * haze) * (1 - handoff))
    }

    private func draw(_ specks: [Speck], at t: Double, in context: inout GraphicsContext) {
        guard t >= 0 else { return }
        for speck in specks {
            let age = t - speck.delay
            var point = speck.origin
            var side = Self.cell
            var alpha = speck.alpha * 0.75
            if age > 0 {
                let progress = age / speck.life
                guard progress < 1 else { continue }
                let eased = progress * progress
                point.x += speck.velocity.dx * age + sin(age * 9 + speck.phase) * speck.wobble * progress
                point.y += speck.velocity.dy * age - 40 * eased
                side *= 1 - 0.6 * progress
                alpha *= 1 - eased
            }
            context.fill(Path(CGRect(x: point.x, y: point.y, width: side, height: side)),
                         with: .color(speck.color.opacity(alpha)))
        }
    }

    // MARK: - Specks

    private struct Speck {
        var origin: CGPoint
        var color: Color
        var alpha: Double
        var delay: Double
        var life: Double
        var velocity: CGVector
        var wobble: Double
        var phase: Double
    }

    /// One speck per inked cell of the row, colored like the pixels under it (grayed, as the ghost is).
    @MainActor
    private func makeSpecks() -> [Speck] {
        let renderer = ImageRenderer(content: row.environment(\.colorScheme, colorScheme))
        renderer.scale = displayScale
        guard let image = renderer.cgImage else { return [] }

        let columns = max(Int(size.width / Self.cell), 1)
        let rows = max(Int(size.height / Self.cell), 1)
        var pixels = [UInt8](repeating: 0, count: columns * rows * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: columns, height: rows, bitsPerComponent: 8,
                bytesPerRow: columns * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            return true
        }
        guard drawn else { return [] }

        var specks: [Speck] = []
        for y in 0..<rows {
            for x in 0..<columns {
                let i = (y * columns + x) * 4
                let alpha = Double(pixels[i + 3]) / 255
                guard alpha > 0.15 else { continue }
                // Premultiplied, so divide alpha back out before graying.
                let gray = (0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1]) + 0.114 * Double(pixels[i + 2]))
                    / 255 / alpha
                let across = Double(x) / Double(columns)
                specks.append(Speck(
                    origin: CGPoint(x: CGFloat(x) * Self.cell, y: CGFloat(y) * Self.cell),
                    color: Color(white: min(gray, 1)),
                    alpha: min(alpha * 1.4, 1),
                    delay: across * Self.sweepTime + .random(in: 0...0.08),
                    life: .random(in: 0.4...Self.maxLife),
                    velocity: CGVector(dx: .random(in: -8...36), dy: .random(in: -70 ... -20)),
                    wobble: .random(in: 2...8),
                    phase: .random(in: 0...(2 * .pi))))
            }
        }
        return specks
    }
}
