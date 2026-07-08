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
        Layer(count: 60, parallax: 0.10, size: 0.7...1.3, alpha: 0.22),   // far
        Layer(count: 36, parallax: 0.24, size: 0.9...1.8, alpha: 0.32),   // mid
        Layer(count: 24, parallax: 0.44, size: 1.3...2.4, alpha: 0.48),   // near
        // So close it's out of focus: big soft dots drifting fastest of
        // all — the "bokeh" plane in front of the stars.
        Layer(count: 10, parallax: 0.70, size: 8...16, alpha: 0.22, soft: true),
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
                                let wobble = paused ? 1 : 1 + 0.3 * sin(t * 0.25 + rand(li, i, 4) * 2 * .pi)
                                let alpha = Double(layer.alpha) * (0.7 + 0.6 * rand(li, i, 6)) * wobble
                                ctx.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2,
                                                                width: r, height: r)),
                                         with: .radialGradient(
                                            Gradient(colors: [color.opacity(alpha), color.opacity(0)]),
                                            center: CGPoint(x: x, y: y),
                                            startRadius: 0, endRadius: r / 2))
                                continue
                            }
                            // Twinkle: idle, ~half the stars pulse; energy
                            // recruits the rest and deepens the pulse.
                            let twinkles = rand(li, i, 3) < 0.45 + 0.45 * Double(energy)
                            let amp = twinkles && !paused ? 0.55 + 0.45 * Double(energy) : 0
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
                            let period = 8 + rand(9, slot, 0) * 8           // 8…16 s
                            guard let life = Self.meteorPhase(t: t, period: period, duration: 0.9)
                            else { continue }
                            let firing = Int((t / period).rounded(.down))   // reseed each firing
                            let sx = rand(9 + slot, firing, 0) * size.width
                            let sy = rand(9 + slot, firing, 1) * size.height * 0.66
                            let dirX = rand(9 + slot, firing, 2) < 0.5 ? -0.8 : 0.8
                            let mag = hypot(dirX, 0.55)
                            let ux = dirX / mag, uy = 0.55 / mag
                            let travel = 260 + rand(9 + slot, firing, 3) * 120  // 260…380 pt
                            let head = CGPoint(x: sx + ux * travel * life,
                                               y: sy + uy * travel * life)
                            let color: Color = rand(9 + slot, firing, 4) < 0.25
                                             ? Palette.accentRedBright : Palette.ink
                            // Fade in and out over the life; flings brighten.
                            let envelope = sin(.pi * life) * (0.85 + 0.5 * Double(energy))
                            for seg in 0..<14 {
                                let f = Double(seg) / 13
                                let p = CGPoint(x: head.x - ux * 90 * f, y: head.y - uy * 90 * f)
                                let r = 2.8 - 2.3 * f
                                let alpha = min(1, envelope * (1 - f * 0.9))
                                let rect = CGRect(x: p.x - r / 2, y: p.y - r / 2, width: r, height: r)
                                if seg == 0 {   // glowing head: two halo rings
                                    ctx.fill(Path(ellipseIn: rect.insetBy(dx: -r * 2.4, dy: -r * 2.4)),
                                             with: .color(color.opacity(alpha * 0.10)))
                                    ctx.fill(Path(ellipseIn: rect.insetBy(dx: -r, dy: -r)),
                                             with: .color(color.opacity(alpha * 0.25)))
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

    /// Two vast color washes at infinite distance — warm maroon high left,
    /// the page's single teal counterpoint low right. They breathe on
    /// offset cycles (scale ±8%, opacity ±12% over a vibrant floor), sway
    /// a few points, and
    /// drift with scroll slower than the farthest stars, so they read as
    /// alive but infinitely far. 8 fps is plenty for 10-second cycles.
    private var nebula: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 8, paused: paused)) { timeline in
            let t = paused ? 0 : timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(RadialGradient(
                            colors: [Palette.accentRedInk.opacity(
                                0.30 * nebulaDim * (1 + 0.12 * sin(t / 9 * 2 * .pi))), .clear],
                            center: .center, startRadius: 0, endRadius: 330))
                        .frame(width: 660, height: 660)
                        .scaleEffect(1 + 0.08 * sin(t / 12 * 2 * .pi))
                        .position(x: geo.size.width * 0.18, y: geo.size.height * 0.28)
                        .offset(x: 14 * sin(t / 26 * 2 * .pi), y: 10 * sin(t / 31 * 2 * .pi))
                    Circle()
                        .fill(RadialGradient(
                            colors: [Palette.accentTealInk.opacity(
                                0.25 * nebulaDim * (1 + 0.12 * sin(t / 9 * 2 * .pi + 2.1))), .clear],
                            center: .center, startRadius: 0, endRadius: 300))
                        .frame(width: 600, height: 600)
                        .scaleEffect(1 + 0.08 * sin(t / 12 * 2 * .pi + 3.7))
                        .position(x: geo.size.width * 0.88, y: geo.size.height * 0.78)
                        .offset(x: 14 * sin(t / 26 * 2 * .pi + 2.4), y: 10 * sin(t / 31 * 2 * .pi + 1.3))
                }
            }
        }
        .offset(y: -drift * 0.09)   // parallax: slower than the farthest stars
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
