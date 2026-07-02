import SwiftUI
import SwiftData

/// The "Today" tab: a serpentine path of daily workouts. One prescribed
/// workout per day extends the streak; the next node unlocks the next day.
/// Progress is two @AppStorage scalars reduced through `PathProgress`.
struct PathView: View {
    @AppStorage("pathIndex") private var pathIndex = 0
    @AppStorage("pathLastCompletedDay") private var pathLastCompletedDay = Int.min
    @State private var scrollY: CGFloat = 0
    @State private var selectedNode: NodeSelection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]

    /// A tapped node: which day, and whether it's the current (startable) one.
    /// Carries the absolute index so repeated days on the path stay distinct.
    private struct NodeSelection: Identifiable {
        let id: Int
        let day: PathDay
        let startable: Bool
    }

    private let rowHeight: CGFloat = 188   // generous vertical spread between nodes
    private let nodeSize: CGFloat = 64
    private let topExtra: CGFloat = 150    // headroom for the ribbon to rise past the first node and fade out

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
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    hero
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
                .buttonStyle(PressableButtonStyle())
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
            let height = rowHeight * CGFloat(windowIndices.count) + topExtra
            let points = windowIndices.indices.map { local -> CGPoint in
                let y = topExtra + rowHeight / 2 + CGFloat(local) * rowHeight
                let x = cx + ribbonWave(y) * amp + insideOffset(y)  // tuck into the curve
                return CGPoint(x: min(cx + maxOff, max(cx - maxOff, x)), y: y)
            }
            ZStack(alignment: .topLeading) {
                flowLine(height: height, cx: cx, amp: amp,
                         drift: reduceMotion ? 0 : scrollY)
                ForEach(Array(windowIndices.enumerated()), id: \.element) { local, nodeIndex in
                    nodeView(nodeIndex)
                        // Depth-of-field: the node nearest the viewport center
                        // is crisp and full-size; nodes recede toward the edges.
                        .visualEffect { [reduceMotion] content, proxy in
                            let t = reduceMotion ? 0 : Self.focusT(
                                midY: proxy.frame(in: .scrollView).midY,
                                viewportHeight: proxy.bounds(of: .scrollView)?.height ?? 0)
                            return content
                                .scaleEffect(1 - 0.16 * t)
                                .opacity(1 - 0.5 * t)
                                .blur(radius: 2.5 * t)
                        }
                        .position(points[local])
                }
            }
        }
        .frame(height: rowHeight * CGFloat(windowIndices.count) + topExtra)
        // Ribbon rises through this headroom and dissolves instead of a hard
        // clip. The fade is clear exactly at the top edge, so there's no seam;
        // nodes sit below the faded zone, unaffected. Bottom stays contained.
        .mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: topExtra)
                Color.black
            }
        )
        .padding(.top, Spacing.md - topExtra)   // pull the headroom up over the hero gap; nodes stay put
    }

    /// An abstract red ribbon that meanders on its own — wider amplitude and a
    /// different rhythm than the dots, so it weaves around them rather than
    /// connecting them — with two fainter offset echoes for depth.
    private func flowLine(height: CGFloat, cx: CGFloat, amp: CGFloat, drift: CGFloat) -> some View {
        // Several grey strands sharing the spine but each with its own phase and
        // high-frequency wiggle, so the band reads as a complex woven line.
        let main = ribbonPath(height: height, cx: cx, amp: amp, wiggleAmp: 0.06, wiggleFreq: 0.061)
        let a = ribbonPath(height: height, cx: cx, amp: amp, phase: 1.3, wiggleAmp: 0.11, wiggleFreq: 0.049)
        let b = ribbonPath(height: height, cx: cx, amp: amp, phase: 3.7, wiggleAmp: 0.15, wiggleFreq: 0.034)
        let stroke = { (w: CGFloat) in StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }
        // Parallax: each echo drifts vertically at its own small rate as you
        // scroll, so the woven band separates into near/far layers. The
        // central strand stays locked to the nodes. Strands overrun both
        // edges by rowHeight in ribbonPath, which covers the largest drift.
        return ZStack {
            main.stroke(Palette.hairlineStrong, style: stroke(1.4))
                .offset(x: 46, y: drift * 0.06).opacity(0.30)
            main.stroke(Palette.hairlineStrong, style: stroke(1.4))
                .offset(x: -50, y: drift * -0.08).opacity(0.26)
            a.stroke(Palette.hairlineStrong, style: stroke(1.3))
                .offset(x: 22, y: drift * 0.03).opacity(0.40)
            b.stroke(Palette.hairlineStrong, style: stroke(1.3))
                .offset(x: -24, y: drift * -0.04).opacity(0.40)
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

    /// Depth-of-field falloff: 0 when a node's midY sits at the viewport
    /// center, rising to 1 at the top/bottom edge (clamped beyond).
    static func focusT(midY: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        guard viewportHeight > 0 else { return 0 }
        let half = viewportHeight / 2
        return min(1, abs(midY - half) / half)
    }

    @ViewBuilder
    private func nodeView(_ nodeIndex: Int) -> some View {
        let state = progress.state(of: nodeIndex, today: today)
        let day = PathProgram.day(at: nodeIndex)
        Button {
            selectedNode = NodeSelection(id: nodeIndex, day: day, startable: state == .today)
        } label: {
            VStack(spacing: Spacing.xs) {
                nodeCircle(state: state, day: day)
                Text(day.title).typography(Typography.captionMd)
                    .foregroundStyle(state == .locked || state == .lockedNext ? Palette.ash : Palette.body)
                    .lineLimit(1)
            }
            .frame(width: 132)
        }
        .buttonStyle(PressableButtonStyle())
        .popover(item: Binding(             // anchored to THIS circle only
            get: { selectedNode?.id == nodeIndex ? selectedNode : nil },
            set: { selectedNode = $0 }
        ), arrowEdge: .top) { sel in
            WorkoutBubble(day: sel.day, startable: sel.startable, onComplete: completeToday)
        }
    }

    @ViewBuilder
    private func nodeCircle(state: NodeState, day: PathDay) -> some View {
        switch state {
        case .done:
            circle(center: Palette.brandRed.opacity(0.5), edge: Palette.brandRed.opacity(0.05),
                   border: Palette.brandRed.opacity(0.30), borderWidth: 1,
                   symbol: "checkmark", symbolColor: Palette.brandRed.opacity(0.85))
        case .today:
            orb(center: Palette.brandRed.opacity(0.26), edge: .clear,
                border: Palette.brandRed.opacity(0.45), borderWidth: 1.5)
                .overlay(ExercisePoseIcon(exerciseID: day.entries.first?.exerciseID ?? "",
                                          color: Palette.accentRed)
                    .frame(width: nodeSize * 0.56, height: nodeSize * 0.56))
                .scaleEffect(1.1)   // today reads a touch larger, still soft
        case .lockedNext, .locked:
            circle(center: Palette.surfaceCard.opacity(0.85), edge: .clear,
                   border: Palette.hairline.opacity(0.45), borderWidth: 1,
                   symbol: "lock.fill", symbolColor: Palette.mute.opacity(0.55))
        }
    }

    /// A soft orb whose fill fades from `center` to `edge` so nodes melt into
    /// the background rather than sitting as hard chips.
    private func orb(center: Color, edge: Color, border: Color, borderWidth: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [center, edge], center: .center,
                                 startRadius: 1, endRadius: nodeSize / 2))
            .frame(width: nodeSize, height: nodeSize)
            .overlay(Circle().stroke(border, lineWidth: borderWidth))
    }

    private func circle(center: Color, edge: Color, border: Color, borderWidth: CGFloat,
                        symbol: String, symbolColor: Color) -> some View {
        orb(center: center, edge: edge, border: border, borderWidth: borderWidth)
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

/// Tapping a path node pops a speech bubble above the circle: the workout's
/// description (focus, the exercise breakdown, rest). The current day is
/// `startable`, so it also gets a "Start workout" action; other days are
/// description-only previews.
private struct WorkoutBubble: View {
    let day: PathDay
    let startable: Bool
    let onComplete: () -> Void
    @State private var starting = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Badge(text: day.focus, style: .redSoft)
                Text(day.title).typography(Typography.headingSm).foregroundStyle(Palette.ink)
                Text("\(day.entries.count) exercise\(day.entries.count == 1 ? "" : "s") · \(day.restSeconds)s rest")
                    .typography(Typography.captionMd).foregroundStyle(Palette.mute)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(day.entries) { entry in
                    HStack(spacing: Spacing.sm) {
                        ExerciseTile(exerciseID: entry.exerciseID, size: 36)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(entry.exerciseID.capitalized)
                                .typography(Typography.bodySmStrong).foregroundStyle(Palette.ink)
                            Text("\(entry.sets) sets × \(entry.target)")
                                .typography(Typography.captionMd).foregroundStyle(Palette.mute)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            if startable {
                Button { starting = true } label: {
                    Text("Start workout").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(Spacing.lg)
        .frame(width: 260)
        .presentationCompactAdaptation(.popover)   // stay a bubble on iPhone, not a sheet
        .fullScreenCover(isPresented: $starting) {
            LiveWorkoutView(plan: WorkoutPlan.expand(day.entries),
                            restSeconds: day.restSeconds, onComplete: onComplete)
        }
    }
}
