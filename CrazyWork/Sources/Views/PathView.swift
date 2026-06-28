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
            let amp = min(cx - 78, 124)   // keep dots + labels clear of the edges
            let height = rowHeight * CGFloat(windowIndices.count)
            let points = windowIndices.indices.map { local in
                CGPoint(x: cx + wave(windowIndices[local]) * amp,
                        y: rowHeight / 2 + CGFloat(local) * rowHeight)
            }
            ZStack(alignment: .topLeading) {
                flowLine(height: height, cx: cx)
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
    private func flowLine(height: CGFloat, cx: CGFloat) -> some View {
        let amp = min(cx - 24, 172)   // swings wider than the dots
        let path = abstractPath(height: height, cx: cx, amp: amp)
        return ZStack {
            path.stroke(Palette.hairlineStrong,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)).offset(x: 32).opacity(0.5)
            path.stroke(Palette.hairlineStrong,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)).offset(x: -36).opacity(0.4)
            path.stroke(Palette.accentRedDeep.opacity(0.45),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }

    /// A free-flowing curve sampled down the full height from `ribbonWave`,
    /// extended past the top/bottom so the ribbon runs off both edges.
    private func abstractPath(height: CGFloat, cx: CGFloat, amp: CGFloat) -> Path {
        Path { p in
            var y: CGFloat = -rowHeight
            var first = true
            while y <= height + rowHeight {
                let pt = CGPoint(x: cx + ribbonWave(y) * amp, y: y)
                if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                y += 14
            }
        }
    }

    /// The ribbon's own meander as a function of vertical position (not node
    /// index), so it is decoupled from where the dots sit.
    private func ribbonWave(_ y: CGFloat) -> CGFloat {
        let v = sin(Double(y) * 0.011 + 0.6) * 0.62 + sin(Double(y) * 0.027 + 2.3) * 0.52
        return CGFloat(max(-1.15, min(1.15, v)))
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
