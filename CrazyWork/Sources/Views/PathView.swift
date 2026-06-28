import SwiftUI
import SwiftData

/// The "Today" tab: a serpentine path of daily workouts. One prescribed
/// workout per day extends the streak; the next node unlocks the next day.
/// Progress is two @AppStorage scalars reduced through `PathProgress`.
struct PathView: View {
    @AppStorage("pathIndex") private var pathIndex = 0
    @AppStorage("pathLastCompletedDay") private var pathLastCompletedDay = Int.min
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]

    private let rowHeight: CGFloat = 152   // generous vertical spread between nodes
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
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    hero
                    focusCard
                    if doneToday { supplementarySection }
                    trail
                }
                .padding(.bottom, Spacing.section)
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
            let amp = min(cx - 78, 124)   // keep dots + labels clear of the edges
            let points = windowIndices.indices.map { local in
                CGPoint(x: cx + wave(windowIndices[local]) * amp,
                        y: rowHeight / 2 + CGFloat(local) * rowHeight)
            }
            ZStack(alignment: .topLeading) {
                flowLine(points)
                ForEach(Array(windowIndices.enumerated()), id: \.element) { local, nodeIndex in
                    nodeView(nodeIndex).position(points[local])
                }
            }
        }
        .frame(height: rowHeight * CGFloat(windowIndices.count))
        .padding(.top, Spacing.md)
    }

    /// A smooth abstract wave behind the dots: one soft red ribbon that loosely
    /// tracks the node positions, with two fainter offset echoes for depth.
    private func flowLine(_ points: [CGPoint]) -> some View {
        let path = smoothPath(points)
        return ZStack {
            path.stroke(Palette.hairlineStrong,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)).offset(x: 26).opacity(0.6)
            path.stroke(Palette.hairlineStrong,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)).offset(x: -26).opacity(0.6)
            path.stroke(Palette.accentRedDeep.opacity(0.5),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }

    /// Builds a smooth curve through the points (midpoint quadratic smoothing),
    /// extended past the first/last so the ribbon flows off the top and bottom.
    private func smoothPath(_ raw: [CGPoint]) -> Path {
        var pts = raw
        if pts.count >= 2 {
            let f = pts[0], f2 = pts[1]
            pts.insert(CGPoint(x: 2 * f.x - f2.x, y: f.y - rowHeight), at: 0)
            let l = pts[pts.count - 1], l2 = pts[pts.count - 2]
            pts.append(CGPoint(x: 2 * l.x - l2.x, y: l.y + rowHeight))
        }
        return Path { p in
            guard pts.count > 1 else { return }
            p.move(to: pts[0])
            for i in 1..<pts.count {
                let prev = pts[i - 1], cur = pts[i]
                let mid = CGPoint(x: (prev.x + cur.x) / 2, y: (prev.y + cur.y) / 2)
                p.addQuadCurve(to: mid, control: prev)
            }
            p.addLine(to: pts[pts.count - 1])
        }
    }

    /// Organic horizontal placement in [-1, 1] as a function of the absolute
    /// node index — two summed sines so the dots wander rather than zig-zag.
    private func wave(_ i: Int) -> CGFloat {
        let x = Double(i)
        let v = sin(x * 1.10 - 0.5) * 0.60 + sin(x * 0.47 + 0.3) * 0.40
        return CGFloat(max(-1, min(1, v)))
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
            circle(fill: Palette.brandRed, border: Palette.brandRed,
                   symbol: "checkmark", symbolColor: Palette.onPrimary)
        case .today:
            NavigationLink {
                LiveWorkoutView(plan: WorkoutPlan.expand(day.entries),
                                restSeconds: day.restSeconds, onComplete: completeToday)
            } label: {
                circle(fill: Palette.brandRedSoft, border: Palette.brandRed,
                       symbol: ExerciseTile.symbol(for: day.entries.first?.exerciseID ?? ""),
                       symbolColor: Palette.accentRedBright)
                    .scaleEffect(1.14)   // today reads larger, no looping animation
            }
            .buttonStyle(.plain)
        case .lockedNext, .locked:
            circle(fill: Palette.surfaceCard, border: Palette.hairline,
                   symbol: "lock.fill", symbolColor: Palette.ash)
        }
    }

    private func circle(fill: Color, border: Color, symbol: String, symbolColor: Color) -> some View {
        Circle().fill(fill)
            .frame(width: nodeSize, height: nodeSize)
            .overlay(Circle().stroke(border, lineWidth: 2))
            .overlay(Image(systemName: symbol)
                .font(.system(size: nodeSize * 0.4, weight: .semibold))
                .foregroundStyle(symbolColor))
    }

    private func completeToday() {
        let next = progress.completing(today: today)
        pathIndex = next.index
        pathLastCompletedDay = next.lastCompletedDay
    }
}
