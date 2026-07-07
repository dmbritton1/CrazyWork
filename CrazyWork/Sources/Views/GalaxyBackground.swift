import SwiftUI

/// A deep-space field behind the trail: three star layers at different
/// parallax depths over two barely-there nebula washes. Stars twinkle gently
/// when idle; `energy` (scroll velocity) raises both the number of twinkling
/// stars and their luminosity, so flinging the page makes the sky flare.
/// No linework — the trail ribbon stays the only line on the canvas.
struct GalaxyBackground: View {
    var drift: CGFloat     // scroll offset, for parallax
    var energy: CGFloat    // 0…1 scroll excitement
    var paused: Bool       // Reduce Motion: static sky
    @Environment(\.colorScheme) private var scheme
    /// Ink-tone washes sit on white far louder than on near-black.
    private var nebulaDim: Double { scheme == .dark ? 1 : 0.35 }

    private struct Layer { let count: Int; let parallax: CGFloat
                           let size: ClosedRange<CGFloat>; let alpha: CGFloat
                           var soft = false }
    private let layers: [Layer] = [
        Layer(count: 48, parallax: 0.10, size: 0.7...1.3, alpha: 0.20),   // far
        Layer(count: 36, parallax: 0.24, size: 0.9...1.8, alpha: 0.32),   // mid
        Layer(count: 24, parallax: 0.44, size: 1.3...2.4, alpha: 0.48),   // near
        // So close it's out of focus: a handful of big soft dots drifting
        // fastest of all — the "bokeh" plane in front of the stars.
        Layer(count: 8, parallax: 0.62, size: 5...9, alpha: 0.13, soft: true),
    ]

    var body: some View {
        ZStack {
            nebula
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    let period = size.height + 120   // wrap zone kept offscreen
                    for (li, layer) in layers.enumerated() {
                        for i in 0..<layer.count {
                            let x = rand(li, i, 0) * size.width
                            var y = (rand(li, i, 1) * period - drift * layer.parallax)
                                .truncatingRemainder(dividingBy: period)
                            if y < 0 { y += period }
                            y -= 60
                            let r = layer.size.lowerBound
                                  + (layer.size.upperBound - layer.size.lowerBound) * rand(li, i, 2)
                            if layer.soft {
                                // Out-of-focus dot: a radial gradient fakes the
                                // blur (no Canvas filter), and a slow wobble
                                // replaces the twinkle.
                                let tint = rand(li, i, 7)
                                let color: Color = tint < 0.05 ? Palette.accentRedBright
                                                 : tint < 0.10 ? Palette.accentAquaBright
                                                 : Palette.ink
                                let wobble = paused ? 1 : 1 + 0.2 * sin(t * 0.25 + rand(li, i, 4) * 2 * .pi)
                                let alpha = Double(layer.alpha) * (0.7 + 0.6 * rand(li, i, 6)) * wobble
                                ctx.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2,
                                                                width: r, height: r)),
                                         with: .radialGradient(
                                            Gradient(colors: [color.opacity(alpha), color.opacity(0)]),
                                            center: CGPoint(x: x, y: y),
                                            startRadius: 0, endRadius: r / 2))
                                continue
                            }
                            // Twinkle: idle, ~1/4 of stars pulse softly; energy
                            // recruits more of them and deepens the pulse.
                            let twinkles = rand(li, i, 3) < 0.25 + 0.55 * Double(energy)
                            let amp = twinkles && !paused ? 0.35 + 0.5 * Double(energy) : 0
                            let pulse = 1 + amp * sin(t * (0.8 + 1.6 * rand(li, i, 4))
                                                      + rand(li, i, 5) * 2 * .pi)
                            let alpha = min(1, Double(layer.alpha)
                                               * (0.7 + 0.6 * rand(li, i, 6))
                                               * pulse * (1 + 0.35 * Double(energy)))
                            let tint = rand(li, i, 7)
                            let color: Color = tint < 0.05 ? Palette.accentRedBright
                                             : tint < 0.10 ? Palette.accentAquaBright
                                             : Palette.ink
                            let rect = CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)
                            if r > 2 {   // biggest stars get a faint halo
                                ctx.fill(Path(ellipseIn: rect.insetBy(dx: -r, dy: -r)),
                                         with: .color(color.opacity(alpha * 0.15)))
                            }
                            ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha)))
                        }
                    }
                    // Shooting stars: five hash-scheduled slots. Three are
                    // always eligible; two more unlock while a fling keeps
                    // `energy` high, so hard scrolls can spark extras. A
                    // meteor is a chain of dots (never a stroked line), and
                    // everything derives from (slot, firing) hashes — no state.
                    if !paused {
                        for slot in 0..<5 {
                            guard slot < 3 || energy > 0.3 else { continue }
                            let period = 14 + rand(9, slot, 0) * 12         // 14…26 s
                            guard let life = Self.meteorPhase(t: t, period: period, duration: 0.6)
                            else { continue }
                            let firing = Int((t / period).rounded(.down))   // reseed each firing
                            let sx = rand(9 + slot, firing, 0) * size.width
                            let sy = rand(9 + slot, firing, 1) * size.height * 0.66
                            let dirX = rand(9 + slot, firing, 2) < 0.5 ? -0.8 : 0.8
                            let mag = hypot(dirX, 0.55)
                            let ux = dirX / mag, uy = 0.55 / mag
                            let travel = 180 + rand(9 + slot, firing, 3) * 80   // 180…260 pt
                            let head = CGPoint(x: sx + ux * travel * life,
                                               y: sy + uy * travel * life)
                            let color: Color = rand(9 + slot, firing, 4) < 0.2
                                             ? Palette.accentRedBright : Palette.ink
                            // Fade in and out over the life; flings brighten.
                            let envelope = sin(.pi * life) * (0.7 + 0.6 * Double(energy))
                            for seg in 0..<8 {
                                let f = Double(seg) / 7
                                let p = CGPoint(x: head.x - ux * 30 * f, y: head.y - uy * 30 * f)
                                let r = 2.2 - 1.8 * f
                                let alpha = envelope * (1 - f * 0.85)
                                let rect = CGRect(x: p.x - r / 2, y: p.y - r / 2, width: r, height: r)
                                if seg == 0 {   // halo on the head, like the biggest stars
                                    ctx.fill(Path(ellipseIn: rect.insetBy(dx: -r, dy: -r)),
                                             with: .color(color.opacity(alpha * 0.15)))
                                }
                                ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha)))
                            }
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Two vast, near-invisible color washes at infinite distance — warm
    /// maroon high left, the page's single teal counterpoint low right.
    private var nebula: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Palette.accentRedInk.opacity(0.18 * nebulaDim), .clear],
                                         center: .center, startRadius: 0, endRadius: 330))
                    .frame(width: 660, height: 660)
                    .position(x: geo.size.width * 0.18, y: geo.size.height * 0.28)
                Circle()
                    .fill(RadialGradient(colors: [Palette.accentTealInk.opacity(0.14 * nebulaDim), .clear],
                                         center: .center, startRadius: 0, endRadius: 300))
                    .frame(width: 600, height: 600)
                    .position(x: geo.size.width * 0.88, y: geo.size.height * 0.78)
            }
        }
    }

    /// Deterministic pseudo-random in [0, 1) seeded by (layer, star, channel),
    /// so the sky is stable frame to frame with no stored state.
    private func rand(_ layer: Int, _ star: Int, _ channel: Int) -> Double {
        let n = sin(Double(layer * 7919 + star * 104729 + channel * 1301) * 12.9898) * 43758.5453
        return n - n.rounded(.down)
    }

    /// Meteor slot scheduling: each slot fires for `duration` seconds at the
    /// start of every `period`. Returns the life phase 0…1 while firing,
    /// nil while dormant — pure, so the Canvas stays stateless.
    nonisolated static func meteorPhase(t: TimeInterval, period: Double, duration: Double) -> Double? {
        let phase = t.truncatingRemainder(dividingBy: period) / duration
        return phase < 1 ? phase : nil
    }
}
