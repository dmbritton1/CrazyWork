import SwiftUI

/// Flowing red accent lines — the signature hero moment, in the same woven
/// curve style as the Path tab's trail (replaces the old blurred gradient).
struct HeroStripeBand<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Spacing.xxl).padding(.horizontal, Spacing.xl)
            .background { FlowingAccentLines().clipped() }
            .background(Palette.canvas)
    }
}

/// A set of red sine strands flowing across the band, each with its own height,
/// amplitude, frequency and phase so they weave — echoing the Path trail.
private struct FlowingAccentLines: View {
    private struct Strand { let yFrac: CGFloat; let amp: CGFloat; let freq: Double
        let phase: Double; let color: Color; let width: CGFloat }
    private let strands: [Strand] = [
        Strand(yFrac: 0.28, amp: 16, freq: 0.020, phase: 0.4, color: Palette.accentRed.opacity(0.30), width: 1.5),
        Strand(yFrac: 0.44, amp: 22, freq: 0.015, phase: 2.1, color: Palette.brandRed.opacity(0.42), width: 2.0),
        Strand(yFrac: 0.55, amp: 18, freq: 0.026, phase: 3.4, color: Palette.accentRed.opacity(0.28), width: 1.5),
        Strand(yFrac: 0.68, amp: 26, freq: 0.012, phase: 1.2, color: Palette.accentRedDeep.opacity(0.32), width: 1.5),
        Strand(yFrac: 0.80, amp: 14, freq: 0.030, phase: 5.0, color: Palette.accentRed.opacity(0.22), width: 1.2),
    ]
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<strands.count, id: \.self) { i in
                    let s = strands[i]
                    wave(width: geo.size.width, baseY: geo.size.height * s.yFrac, s: s)
                        .stroke(s.color, style: StrokeStyle(lineWidth: s.width, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
    private func wave(width: CGFloat, baseY: CGFloat, s: Strand) -> Path {
        Path { p in
            var x: CGFloat = -16
            var first = true
            while x <= width + 16 {
                let y = baseY + CGFloat(sin(Double(x) * s.freq + s.phase)) * s.amp
                let pt = CGPoint(x: x, y: y)
                if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                x += 6
            }
        }
    }
}

/// Single teal wash — the cool secondary moment (once per page).
struct AquaGlowBand<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Spacing.xxl).padding(.horizontal, Spacing.xl)
            .background(alignment: .top) {
                LinearGradient(colors: [Palette.aquaGlowStart.opacity(0.8), Palette.aquaGlowEnd],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 120).blur(radius: 32)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .background(Palette.canvas)
    }
}
