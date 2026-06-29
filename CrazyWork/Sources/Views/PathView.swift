import SwiftUI
import SwiftData

/// The "Today" tab: a serpentine path of daily workouts. One prescribed
/// workout per day extends the streak; the next node unlocks the next day.
/// Progress is two @AppStorage scalars reduced through `PathProgress`.
struct PathView: View {
    @AppStorage("pathIndex") private var pathIndex = 0
    @AppStorage("pathLastCompletedDay") private var pathLastCompletedDay = Int.min
    @State private var scrollY: CGFloat = 0
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]

    private let rowHeight: CGFloat = 188   // generous vertical spread between nodes
    private let nodeSize: CGFloat = 64

    private var today: Int { PathProgram.epochDay(Date()) }
    private var progress: PathProgress {
        PathProgress(index: pathIndex, lastCompletedDay: pathLastCompletedDay)
    }
    private var streak: Int {
        ProgressStats(summaries: sessions.map(\.summary)).currentStreak
    }
    /// The node "today" refers to: the one to do if not yet done, else the one
    /// just completed today — so the focus card and supplementary reflect what
    /// was actually done, not the next locked node.
    private var todayDay: PathDay { PathProgram.day(at: doneToday ? pathIndex - 1 : pathIndex) }
    private var doneToday: Bool { progress.isCompletedToday(today: today) }

    /// Window of absolute node indices to render (not the whole infinite path).
    private var windowIndices: [Int] {
        let lo = max(0, pathIndex - 2)
        return Array(lo...(pathIndex + 6))
    }

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            GeometryReader { vp in
                redGlow
                    .position(x: vp.size.width / 2
                                + CGFloat(sin(Double(scrollY) / 150)) * vp.size.width * 0.34,
                              y: vp.size.height * 0.42
                                + CGFloat(sin(Double(scrollY) / 260)) * vp.size.height * 0.16)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    hero
                    focusCard
                    if doneToday { supplementarySection }
                    trail
                }
                .padding(.bottom, Spacing.section)
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                scrollY = y
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// A soft red gradient blur that rides along with the scroll and weaves
    /// side to side, drifting around the path behind the dots.
    private var redGlow: some View {
        RadialGradient(colors: [Palette.brandRed.opacity(0.5),
                                Palette.accentRedDeep.opacity(0.22), .clear],
                       center: .center, startRadius: 0, endRadius: 170)
            .frame(width: 340, height: 340)
            .blur(radius: 70)
    }

    private var hero: some View {
        HeroStripeBand {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "flame.fill").foregroundStyle(Palette.brandRed)
                    Text("\(streak) day\(streak == 1 ? "" : "s")")
                        .typography(Typography.headingMd).foregroundStyle(Palette.ink)
                }
                Text("Today").typography(Typography.displayLg).foregroundStyle(Palette.ink)
                Text(doneToday ? "Done for today — next unlocks tomorrow"
                               : "Today's focus · \(todayDay.focus)")
                    .typography(Typography.bodyMd).foregroundStyle(Palette.mute)
            }
        }
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text(todayDay.title).typography(Typography.headingMd).foregroundStyle(Palette.ink)
                Spacer()
                Badge(text: todayDay.focus, style: .redSoft)
            }
            ForEach(todayDay.entries) { entry in
                Text("\(entry.sets)× \(entry.target) · \(entry.exerciseID.capitalized)")
                    .typography(Typography.bodySm).foregroundStyle(Palette.body)
            }
            if doneToday {
                Label("Completed today", systemImage: "checkmark.circle.fill")
                    .typography(Typography.bodyStrong).foregroundStyle(Palette.accentGreen)
            } else {
                NavigationLink {
                    LiveWorkoutView(plan: WorkoutPlan.expand(todayDay.entries),
                                    restSeconds: todayDay.restSeconds,
                                    onComplete: completeToday)
                } label: {
                    Text("Start today's workout").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .card()
        .padding(.horizontal, Spacing.lg)
    }

    private var supplementarySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("WANT MORE?").typography(Typography.bodySmStrong).foregroundStyle(Palette.mute)
            ForEach(todayDay.supplementary) { bonus in
                NavigationLink {
                    LiveWorkoutView(plan: WorkoutPlan.expand(bonus.entries),
                                    restSeconds: bonus.restSeconds) // no onComplete → no path advance
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(bonus.title).typography(Typography.bodyStrong).foregroundStyle(Palette.ink)
                            Text(bonus.focus).typography(Typography.captionMd).foregroundStyle(Palette.mute)
                        }
                        Spacer()
                        Image(systemName: "plus.circle").foregroundStyle(Palette.accentAqua)
                    }
                    .card()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.lg)
    }

    // MARK: Flowing trail

    private var trail: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let amp = min(cx - 24, 172)      // shared with the ribbon
            let maxOff = cx - 66             // keep dots + labels on screen
            let height = rowHeight * CGFloat(windowIndices.count)
            let points = windowIndices.indices.map { local -> CGPoint in
                let y = rowHeight / 2 + CGFloat(local) * rowHeight
                let x = cx + ribbonWave(y) * amp + insideOffset(y)  // tuck into the curve
                return CGPoint(x: min(cx + maxOff, max(cx - maxOff, x)), y: y)
            }
            ZStack(alignment: .topLeading) {
                flowLine(height: height, cx: cx, amp: amp)
                ForEach(Array(windowIndices.enumerated()), id: \.element) { local, nodeIndex in
                    nodeView(nodeIndex).position(points[local])
                }
            }
        }
        .frame(height: rowHeight * CGFloat(windowIndices.count))
        .padding(.top, Spacing.md)
    }

    /// An abstract red ribbon that meanders on its own — wider amplitude and a
    /// different rhythm than the dots, so it weaves around them rather than
    /// connecting them — with two fainter offset echoes for depth.
    private func flowLine(height: CGFloat, cx: CGFloat, amp: CGFloat) -> some View {
        // Several grey strands sharing the spine but each with its own phase and
        // high-frequency wiggle, so the band reads as a complex woven line.
        let main = ribbonPath(height: height, cx: cx, amp: amp, wiggleAmp: 0.06, wiggleFreq: 0.061)
        let a = ribbonPath(height: height, cx: cx, amp: amp, phase: 1.3, wiggleAmp: 0.11, wiggleFreq: 0.049)
        let b = ribbonPath(height: height, cx: cx, amp: amp, phase: 3.7, wiggleAmp: 0.15, wiggleFreq: 0.034)
        let stroke = { (w: CGFloat) in StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }
        return ZStack {
            main.stroke(Palette.hairlineStrong, style: stroke(1.4)).offset(x: 46).opacity(0.30)
            main.stroke(Palette.hairlineStrong, style: stroke(1.4)).offset(x: -50).opacity(0.26)
            a.stroke(Palette.hairlineStrong, style: stroke(1.3)).offset(x: 22).opacity(0.40)
            b.stroke(Palette.hairlineStrong, style: stroke(1.3)).offset(x: -24).opacity(0.40)
            main.stroke(Palette.mute.opacity(0.45), style: stroke(2))   // central strand, grey
        }
    }

    /// A free-flowing curve sampled down the full height from `ribbonWave`, with
    /// an optional phase-shifted high-frequency wiggle, extended past the
    /// top/bottom so each strand runs off both edges.
    private func ribbonPath(height: CGFloat, cx: CGFloat, amp: CGFloat,
                            phase: Double = 0, wiggleAmp: Double = 0,
                            wiggleFreq: Double = 0) -> Path {
        Path { p in
            var y: CGFloat = -rowHeight
            var first = true
            while y <= height + rowHeight {
                let extra = wiggleAmp == 0 ? 0 : wiggleAmp * sin(Double(y) * wiggleFreq + phase)
                let xv = Double(ribbonWave(y)) + extra
                let pt = CGPoint(x: cx + CGFloat(xv) * amp, y: y)
                if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                y += 12
            }
        }
    }

    /// The ribbon's own meander as a function of vertical position (not node
    /// index), so it is decoupled from where the dots sit.
    private func ribbonWave(_ y: CGFloat) -> CGFloat {
        let v = sin(Double(y) * 0.011 + 0.6) * 0.62 + sin(Double(y) * 0.027 + 2.3) * 0.52
        return CGFloat(max(-1.15, min(1.15, v)))
    }

    /// Signed horizontal nudge (points) pushing a node toward the concave —
    /// "inside" — side of the ribbon's curve at vertical position `y`, larger
    /// where the ribbon bends harder so dots nestle into each bow.
    private func insideOffset(_ y: CGFloat) -> CGFloat {
        let d = Double(y), a = 0.011, b = 0.027
        let curvature = -(a * a) * 0.62 * sin(a * d + 0.6)
                      - (b * b) * 0.52 * sin(b * d + 2.3)   // ribbonWave''(y)
        let sign: CGFloat = curvature >= 0 ? 1 : -1
        let strength = min(1, CGFloat(abs(curvature)) * 2200)
        return sign * (38 + 46 * strength)
    }

    @ViewBuilder
    private func nodeView(_ nodeIndex: Int) -> some View {
        let state = progress.state(of: nodeIndex, today: today)
        let day = PathProgram.day(at: nodeIndex)
        VStack(spacing: Spacing.xs) {
            nodeCircle(state: state, day: day)
            Text(day.title).typography(Typography.captionMd)
                .foregroundStyle(state == .locked || state == .lockedNext ? Palette.ash : Palette.body)
                .lineLimit(1)
        }
        .frame(width: 132)
    }

    @ViewBuilder
    private func nodeCircle(state: NodeState, day: PathDay) -> some View {
        switch state {
        case .done:
            circle(center: Palette.brandRed.opacity(0.5), edge: Palette.brandRed.opacity(0.05),
                   border: Palette.brandRed.opacity(0.30), borderWidth: 1,
                   symbol: "checkmark", symbolColor: Palette.brandRed.opacity(0.85))
        case .today:
            NavigationLink {
                LiveWorkoutView(plan: WorkoutPlan.expand(day.entries),
                                restSeconds: day.restSeconds, onComplete: completeToday)
            } label: {
                circle(center: Palette.brandRed.opacity(0.26), edge: .clear,
                       border: Palette.brandRed.opacity(0.45), borderWidth: 1.5,
                       symbol: ExerciseTile.symbol(for: day.entries.first?.exerciseID ?? ""),
                       symbolColor: Palette.accentRed)
                    .scaleEffect(1.1)   // today reads a touch larger, still soft
            }
            .buttonStyle(.plain)
        case .lockedNext, .locked:
            circle(center: Palette.surfaceCard.opacity(0.85), edge: .clear,
                   border: Palette.hairline.opacity(0.45), borderWidth: 1,
                   symbol: "lock.fill", symbolColor: Palette.mute.opacity(0.55))
        }
    }

    /// A soft orb whose fill fades from `center` to `edge` so nodes melt into
    /// the background rather than sitting as hard chips.
    private func circle(center: Color, edge: Color, border: Color, borderWidth: CGFloat,
                        symbol: String, symbolColor: Color) -> some View {
        Circle()
            .fill(RadialGradient(colors: [center, edge], center: .center,
                                 startRadius: 1, endRadius: nodeSize / 2))
            .frame(width: nodeSize, height: nodeSize)
            .overlay(Circle().stroke(border, lineWidth: borderWidth))
            .overlay(Image(systemName: symbol)
                .font(.system(size: nodeSize * 0.38, weight: .medium))
                .foregroundStyle(symbolColor))
    }

    private func completeToday() {
        let next = progress.completing(today: today)
        pathIndex = next.index
        pathLastCompletedDay = next.lastCompletedDay
    }
}
