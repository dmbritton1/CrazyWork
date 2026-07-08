import SwiftUI
import SwiftData

/// The "Today" tab: a serpentine path of daily workouts. One prescribed
/// workout per day extends the streak; the next node unlocks the next day.
/// Progress is two @AppStorage scalars reduced through `PathProgress`.
struct PathView: View {
    @AppStorage("pathIndex") private var pathIndex = 0
    @AppStorage("pathLastCompletedDay") private var pathLastCompletedDay = Int.min
    @State private var scrollY: CGFloat = 0
    @State private var stretch: CGFloat = 0        // scroll-velocity lag on the ribbon, springs back to 0
    @State private var stretchReset: Task<Void, Never>?
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
    /// The central strand's flutter on top of the spine — low frequency, so
    /// the line bends at the workouts, not between them. Shared by the
    /// drawing, the perch math, and the detours so figures always sit on the
    /// drawn line.
    private static let wiggleAmp = 0.035
    private static let wiggleFreq = 0.028

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
            GalaxyBackground(drift: reduceMotion ? 0 : scrollY,
                             energy: min(1, abs(stretch) * 1.5),
                             paused: reduceMotion)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    hero
                    if doneToday { supplementarySection }
                    trail
                }
                .padding(.bottom, Spacing.section)
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { old, y in
                scrollY = y
                guard !reduceMotion else { return }
                // Ribbon inertia: follow scroll velocity while moving, then
                // spring back once events stop for a beat.
                let target = max(-1, min(1, (y - old) / 60))
                stretch = stretch * 0.6 + target * 0.4
                stretchReset?.cancel()
                stretchReset = Task {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { stretch = 0 }
                }
            }
            streakPill
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var hero: some View {
        // Eases down slightly as it scrolls away, handing off to the pill.
        let p = reduceMotion ? 0 : min(1, max(0, (scrollY - 20) / 130))
        return HeroStripeBand {
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
        .scaleEffect(1 - 0.05 * p, anchor: .top)
    }

    /// Compact sticky stand-in for the hero once it scrolls off: flame, streak,
    /// and today's state in one capsule.
    private var streakPill: some View {
        VStack {
            if scrollY > 130 {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13)).foregroundStyle(Palette.brandRed)
                    Text("\(streak) day\(streak == 1 ? "" : "s")")
                        .typography(Typography.bodySmStrong).foregroundStyle(Palette.ink)
                    Text("·").foregroundStyle(Palette.stone)
                    Text(doneToday ? "Done today" : todayDay.focus)
                        .typography(Typography.captionMd).foregroundStyle(Palette.mute)
                }
                .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.xs)
                .background(Capsule().fill(Palette.surfaceElevated.opacity(0.94)))
                .overlay(Capsule().stroke(Palette.hairline, lineWidth: 1))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Spacer()
        }
        .padding(.top, Spacing.xs)
        .animation(Motion.resolved(Motion.state, reduceMotion: reduceMotion), value: scrollY > 130)
        .allowsHitTesting(false)
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
            let amp = min(cx - 24, 172)      // wiggle/detour scale
            let maxOff = cx - 66             // keep dots + labels on screen
            let height = rowHeight * CGFloat(windowIndices.count) + topExtra
            // Nodes first, ribbon second: each workout picks its own spot —
            // alternating sides with a hashed reach and vertical jitter — and
            // the strand is drawn THROUGH those spots, so the line visibly
            // exists to connect the workouts. Hashes key off the absolute
            // index, so a node keeps its spot as the window advances.
            let anchors = windowIndices.indices.map { local -> CGPoint in
                let i = windowIndices[local]
                let side: CGFloat = i.isMultiple(of: 2) ? -1 : 1
                let x = cx + side * maxOff * (0.6 + 0.4 * Self.nodeRand(i, 0))
                let y = topExtra + rowHeight / 2 + CGFloat(local) * rowHeight
                      + (Self.nodeRand(i, 1) - 0.5) * rowHeight * 0.42
                return CGPoint(x: x, y: y)
            }
            let spine = TrailSpine(anchors: anchors, cx: cx, overrun: rowHeight)
            let points = anchors.indices.map { local -> CGPoint in
                // Snap to a perch on the UPPER side of the strand, 11pt out —
                // that puts the glyph's internal ground line (≈0.8 of the
                // icon) right on the strand, so the figure sits on it.
                let f = strandFrame(near: anchors[local], spine: spine, amp: amp)
                let up = f.o.dy <= 0 ? f.o : CGVector(dx: -f.o.dx, dy: -f.o.dy)
                let snapped = CGPoint(x: f.best.x + up.dx * 11, y: f.best.y + up.dy * 11)
                return CGPoint(x: min(cx + maxOff, max(cx - maxOff, snapped.x)), y: snapped.y)
            }
            // Trail-local y of the viewport's vertical center, for the ink edge.
            let viewportH = geo.bounds(of: .scrollView)?.height ?? 0
            let inkY = viewportH / 2 - geo.frame(in: .scrollView).minY
            // For each figure: where along the strand it perches, how far the
            // enclosing strand must bow out perpendicular to the line, and
            // which side of the line the figure stands on. The detour arcs
            // over the figure; the core line stays tight under its feet.
            let detours = windowIndices.indices.map { local -> (y: CGFloat, bulge: CGFloat, side: CGFloat) in
                let f = strandFrame(near: points[local], spine: spine, amp: amp)
                let isToday = progress.state(of: windowIndices[local], today: today) == .today
                // Figure side: sign of the perch normal against the line's
                // continuous left normal (-u.dy, u.dx).
                let side: CGFloat = (f.o.dx * -f.u.dy + f.o.dy * f.u.dx) >= 0 ? 1 : -1
                // Tight berth: just clear of the glyph (half ≈ 18–22pt above
                // the perch), so the line visibly hugs the figure.
                return (y: f.best.y, bulge: isToday ? 38 : 34, side: side)
            }
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    flowLine(height: height, spine: spine, amp: amp,
                             drift: reduceMotion ? 0 : scrollY,
                             inkY: reduceMotion ? 0 : inkY,
                             detours: detours)
                }
                // Gravitational aura: a Metal lens bends the strands around
                // each figure — pure light distortion, no material, no rim.
                // Applied in trail coordinates (before the stretch transforms)
                // so each lens stays pinned to its perch.
                .distortionEffect(
                    ShaderLibrary.trailLens(
                        .floatArray(points.flatMap { [Float($0.x), Float($0.y)] }),
                        .float(Float(nodeSize) * 1.5),
                        .float(0.9),
                        .float(0.8)),
                    maxSampleOffset: CGSize(width: 26, height: 26))
                // Inertia from scroll velocity: the ribbon lags a touch and
                // its amplitude tenses, then springs back. Nodes stay put.
                .offset(y: stretch * -14)
                .scaleEffect(x: 1 - abs(stretch) * 0.04)
                ForEach(Array(windowIndices.enumerated()), id: \.element) { local, nodeIndex in
                    // Figure sits on the line: tilt it to the strand's slope
                    // under the perch. The tangent always points down-page,
                    // so fold its angle into (-90°, 90°] — the figure leans
                    // with the line but is never upside down.
                    let f = strandFrame(near: points[local], spine: spine, amp: amp)
                    let slope = atan2(Double(f.u.dy), Double(f.u.dx))
                    nodeView(nodeIndex,
                             groundAngle: .radians(slope > .pi / 2 ? slope - .pi : slope))
                        // Gentle magnify: every node stays crisp and opaque;
                        // the one nearest the viewport center grows ~9%.
                        .visualEffect { [reduceMotion] content, proxy in
                            let t = Self.focusT(
                                midY: proxy.frame(in: .scrollView).midY,
                                viewportHeight: proxy.bounds(of: .scrollView)?.height ?? 0)
                            let f = reduceMotion ? 0 : (1 - t) * (1 - t) * (1 - t)
                            return content.scaleEffect(1 + 0.09 * f)
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

    /// The ribbon threads THROUGH the workouts: its spine is a spline over the
    /// node anchors, dressed with two fainter offset echoes for depth.
    private func flowLine(height: CGFloat, spine: TrailSpine, amp: CGFloat,
                          drift: CGFloat, inkY: CGFloat,
                          detours: [(y: CGFloat, bulge: CGFloat, side: CGFloat)]) -> some View {
        // Several grey strands sharing the spine, each with its own phase and
        // a slow flutter — languid enough that the band bends back and forth
        // without micro-squiggle between the workouts.
        // The central strand is GAPPED across each figure's pocket: the
        // detour arc (which leaves and rejoins it tangentially) becomes the
        // line's route around the body, so nothing crosses a glyph.
        let gaps = detours.map { ($0.y - $0.bulge * 2.8)...($0.y + $0.bulge * 2.8) }
        let main = ribbonPath(height: height, spine: spine, amp: amp,
                              wiggleAmp: Self.wiggleAmp, wiggleFreq: Self.wiggleFreq,
                              gaps: gaps)
        // The offset echo reuses the central strand's shape but NOT its gaps —
        // its gaps would float 46pt beside the figures as stray line ends.
        let mainEcho = ribbonPath(height: height, spine: spine, amp: amp,
                                  wiggleAmp: Self.wiggleAmp, wiggleFreq: Self.wiggleFreq)
        let a = ribbonPath(height: height, spine: spine, amp: amp, phase: 1.3, wiggleAmp: 0.07, wiggleFreq: 0.020)
        let b = ribbonPath(height: height, spine: spine, amp: amp, phase: 3.7, wiggleAmp: 0.09, wiggleFreq: 0.014)
        // One detour per figure: peels off the central strand upstream, bows
        // out perpendicular to the line over the figure's side, and converges
        // back downstream — the core line stays tight under the feet, so the
        // two close the pocket. All detours share one path, one stroke.
        var arc = Path()
        for d in detours { arc.addPath(detourPath(nodeY: d.y, bulge: d.bulge, side: d.side, spine: spine, amp: amp)) }
        var traveled = main
        traveled.addPath(arc)
        let stroke = { (w: CGFloat) in StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }
        // Parallax: each echo drifts vertically at its own small rate as you
        // scroll, so the woven band separates into near/far layers. The
        // central strand stays locked to the nodes. Strands overrun both
        // edges by rowHeight in ribbonPath, which covers the largest drift.
        return ZStack {
            // Grey echoes run free: the trailLens shader sweeps them around
            // each figure, so proximity to a node reads as bent light, not
            // clutter — no masking needed.
            mainEcho.stroke(Palette.trailStrand, style: stroke(1.4))
                .offset(x: 46, y: drift * 0.06).opacity(0.42)
            a.stroke(Palette.trailStrand, style: stroke(1.3))
                .offset(x: 22, y: drift * 0.03).opacity(0.55)
            b.stroke(Palette.trailStrand, style: stroke(1.3))
                .offset(x: -24, y: drift * -0.04).opacity(0.55)
            // Enclosure arc: shares the spine, so between figures it lies on
            // the central strand as one line and only peels off around figures.
            arc.stroke(Palette.trailStrandMain.opacity(0.65), style: stroke(1.8))
            main.stroke(Palette.trailStrandMain.opacity(0.6), style: stroke(2))   // central strand
            // Trail ink: the stretch above the viewport center reads as
            // already traveled — the central strand tints brand red behind
            // you, dissolving back to grey over ~180pt around the center.
            // The ink covers the detour arcs too, so the traveled line flows
            // around each figure instead of dying at the gap.
            ZStack {
                traveled.stroke(Palette.brandRed.opacity(0.22), style: stroke(7)).blur(radius: 5)
                traveled.stroke(Palette.brandRed.opacity(0.75), style: stroke(2.4))
            }
            .mask(inkMask(inkY: inkY, height: height))
        }
    }

    /// Mask that is solid from the trail's top down to just above `inkY`, then
    /// fades out — so the red ink trails off around the viewport center.
    private func inkMask(inkY: CGFloat, height: CGFloat) -> some View {
        let s0 = min(1, max(0, (inkY - 90) / height))
        let s1 = min(1, max(s0 + 0.0001, (inkY + 90) / height))
        return Rectangle().fill(LinearGradient(
            stops: [.init(color: .black, location: 0),
                    .init(color: .black, location: s0),
                    .init(color: .clear, location: s1)],
            startPoint: .top, endPoint: .bottom))
    }

    /// The spine curve sampled down the full height, with an optional
    /// phase-shifted high-frequency wiggle, extended past the top/bottom so
    /// each strand runs off both edges.
    private func ribbonPath(height: CGFloat, spine: TrailSpine, amp: CGFloat,
                            phase: Double = 0, wiggleAmp: Double = 0,
                            wiggleFreq: Double = 0,
                            gaps: [ClosedRange<CGFloat>] = []) -> Path {
        Path { p in
            var y: CGFloat = -rowHeight
            var first = true
            while y <= height + rowHeight {
                if gaps.contains(where: { $0.contains(y) }) {
                    first = true            // lift the pen across a gap
                    y += 6
                    continue
                }
                let extra = wiggleAmp == 0 ? 0 : wiggleAmp * sin(Double(y) * wiggleFreq + phase)
                let x = spine.x(y) + CGFloat(extra) * amp
                let pt = CGPoint(x: x, y: y)
                if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                y += 6
            }
        }
    }

    /// The strand's detour around one figure: a two-segment Bézier swerve
    /// that leaves the central strand tangentially upstream of the perch,
    /// passes the figure at `bulge` points of perpendicular clearance moving
    /// parallel to the ground under it, and rejoins the strand tangentially
    /// downstream. Built from anchors + tangents (not by offsetting the
    /// curve), so it can never cusp where the strand bends tighter than the
    /// clearance.
    private func detourPath(nodeY: CGFloat, bulge: CGFloat, side: CGFloat,
                            spine: TrailSpine, amp: CGFloat) -> Path {
        func sx(_ y: CGFloat) -> CGFloat {   // central strand incl. its wiggle
            spine.x(y) + CGFloat(Self.wiggleAmp * sin(Double(y) * Self.wiggleFreq)) * amp
        }
        func tangent(_ y: CGFloat) -> CGVector {
            let dx = sx(y + 3) - sx(y - 3)
            let l = hypot(dx, 6)
            return CGVector(dx: dx / l, dy: 6 / l)
        }
        // Long reach: the clearance ramps up over ~2.8× the bulge, so the
        // detour's normal offset never fights the fast-turning strand at an
        // apex (short ramps read as an S-wobble on the inside of a bend).
        let reach = bulge * 2.8
        // Anchors riding the strand, each pushed out along the LOCAL normal
        // by a cosine falloff (full clearance at the figure, zero at the
        // ends) — so the detour bends everywhere the core line bends instead
        // of chording across it. Still anchors + tangents, never a raw curve
        // offset, so it can't cusp at a tight apex.
        let raw = stride(from: -1.0, through: 1.0, by: 1.0 / 3).map { s -> CGPoint in
            let y = nodeY + CGFloat(s) * reach
            let u = tangent(y)
            let w = CGFloat(0.5 * (1 + cos(s * .pi)))
            let n = CGVector(dx: -u.dy * side, dy: u.dx * side)   // toward the figure
            return CGPoint(x: sx(y) + n.dx * bulge * w, y: y + n.dy * bulge * w)
        }
        // One 1-2-1 low-pass over the interior: where the strand turns fast,
        // adjacent normals disagree and the raw anchors zigzag a touch — the
        // blur trades a hair of clearance for a jog-free line.
        let stops = raw.indices.map { i -> CGPoint in
            guard i > 0, i < raw.count - 1 else { return raw[i] }
            return CGPoint(x: (raw[i - 1].x + 2 * raw[i].x + raw[i + 1].x) / 4,
                           y: (raw[i - 1].y + 2 * raw[i].y + raw[i + 1].y) / 4)
        }
        // Tangents come from the detour's own shape (Catmull-Rom), not the
        // strand's — where the clearance ramps, the two differ and strand
        // tangents kink the joins. The ends keep the strand tangent so the
        // detour still leaves and rejoins the line seamlessly.
        let tangents = stops.indices.map { i -> CGVector in
            if i == 0 { return tangent(nodeY - reach) }
            if i == stops.count - 1 { return tangent(nodeY + reach) }
            let d = CGVector(dx: stops[i + 1].x - stops[i - 1].x,
                             dy: stops[i + 1].y - stops[i - 1].y)
            let l = max(1, hypot(d.dx, d.dy))
            return CGVector(dx: d.dx / l, dy: d.dy / l)
        }
        var p = Path()
        p.move(to: stops[0])
        for i in 0..<(stops.count - 1) {
            let a = stops[i], b = stops[i + 1]
            let k = hypot(b.x - a.x, b.y - a.y) / 3
            p.addCurve(to: b,
                       control1: CGPoint(x: a.x + tangents[i].dx * k, y: a.y + tangents[i].dy * k),
                       control2: CGPoint(x: b.x - tangents[i + 1].dx * k, y: b.y - tangents[i + 1].dy * k))
        }
        return p
    }

    /// Local frame of the central strand nearest a node: the closest strand
    /// point, the unit tangent `u` along the line, and the unit normal `o`
    /// toward the node.
    private func strandFrame(near node: CGPoint, spine: TrailSpine, amp: CGFloat)
        -> (best: CGPoint, u: CGVector, o: CGVector) {
        func strandX(_ y: CGFloat) -> CGFloat {
            spine.x(y) + CGFloat(Self.wiggleAmp * sin(Double(y) * Self.wiggleFreq)) * amp
        }
        var best = CGPoint(x: strandX(node.y - 140), y: node.y - 140)
        var bestD = CGFloat.greatestFiniteMagnitude
        var y = node.y - 140
        while y <= node.y + 140 {
            let pt = CGPoint(x: strandX(y), y: y)
            let dd = hypot(pt.x - node.x, pt.y - node.y)
            if dd < bestD { bestD = dd; best = pt }
            y += 6
        }
        let dxT = strandX(best.y + 6) - strandX(best.y - 6)
        let tl = hypot(dxT, 12)
        let u = CGVector(dx: dxT / tl, dy: 12 / tl)
        let o: CGVector = bestD < 8
            ? CGVector(dx: -u.dy, dy: u.dx)
            : CGVector(dx: (node.x - best.x) / bestD, dy: (node.y - best.y) / bestD)
        return (best, u, o)
    }

    /// Deterministic per-node hash in [0, 1): stable across scrolls and
    /// launches, so each workout keeps its spot on the trail.
    private static func nodeRand(_ node: Int, _ channel: Int) -> CGFloat {
        let n = sin(Double(node * 104729 + channel * 7919 + 17) * 12.9898) * 43758.5453
        return CGFloat(n - n.rounded(.down))
    }

    /// Depth-of-field falloff: 0 when a node's midY sits at the viewport
    /// center, rising to 1 at the top/bottom edge (clamped beyond).
    nonisolated static func focusT(midY: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        guard viewportHeight > 0 else { return 0 }
        let half = viewportHeight / 2
        return min(1, abs(midY - half) / half)
    }

    @ViewBuilder
    private func nodeView(_ nodeIndex: Int, groundAngle: Angle) -> some View {
        let state = progress.state(of: nodeIndex, today: today)
        let day = PathProgram.day(at: nodeIndex)
        Button {
            selectedNode = NodeSelection(id: nodeIndex, day: day, startable: state == .today)
        } label: {
            nodeCircle(state: state, day: day, groundAngle: groundAngle)
                // Label hangs below as an overlay so position() centers the
                // circle itself on the perch — a VStack would shift the
                // figure half the label's height off the line.
                .overlay(alignment: .bottom) {
                    Text(day.title).typography(Typography.captionMd)
                        .foregroundStyle(state == .locked || state == .lockedNext ? Palette.ash : Palette.body)
                        .lineLimit(1)
                        .padding(.horizontal, Spacing.xs).padding(.vertical, 2)
                        // keeps the title legible where strands cross beneath it
                        .background(Capsule().fill(Palette.canvas.opacity(0.72)))
                        .fixedSize()
                        .offset(y: 26)
                }
        }
        .buttonStyle(PressableButtonStyle())
        .popover(item: Binding(             // anchored to THIS circle only
            get: { selectedNode?.id == nodeIndex ? selectedNode : nil },
            set: { selectedNode = $0 }
        ), arrowEdge: .top) { sel in
            WorkoutBubble(day: sel.day, startable: sel.startable, onComplete: completeToday)
        }
    }

    /// Every node is a bare stick-figure pose glyph over a soft color wash —
    /// no ring, no enclosure: the figure just stands on the strand, grounded
    /// by the `perchMark` worn spot under its feet. State lives in a small
    /// corner badge (check / lock).
    private func nodeCircle(state: NodeState, day: PathDay, groundAngle: Angle) -> some View {
        let locked = state == .locked || state == .lockedNext
        let glyph: Color = locked ? Palette.ash : Palette.accentRed
        let fill: Color = state == .today ? Palette.brandRed.opacity(0.26)
                        : locked ? Palette.surfaceCard.opacity(0.85)
                        : Palette.brandRed.opacity(0.10)
        return ZStack {
            ZStack {
                orb(center: fill, edge: .clear)
                ExercisePoseIcon(exerciseID: day.entries.first?.exerciseID ?? "", color: glyph)
                    .frame(width: nodeSize * 0.56, height: nodeSize * 0.56)
            }
            // tilt to the strand's slope: the figure sits on the line at
            // whatever angle it runs under the perch
            .rotationEffect(groundAngle)
            if state == .done { badge("checkmark") }
            if locked { badge("lock.fill") }
        }
        .frame(width: nodeSize, height: nodeSize)
        .scaleEffect(state == .today ? 1.1 : 1)   // today reads a touch larger
    }

    private func badge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Palette.mute)
            .padding(4)
            .background(Circle().fill(Palette.surfaceElevated))
            .overlay(Circle().stroke(Palette.hairline, lineWidth: 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .offset(x: 4, y: -4)   // clear of the label below the circle
    }

    /// A soft orb whose fill fades from `center` to `edge` so nodes melt into
    /// the background rather than sitting as hard chips.
    private func orb(center: Color, edge: Color) -> some View {
        Circle()
            .fill(RadialGradient(colors: [center, edge], center: .center,
                                 startRadius: 1, endRadius: nodeSize / 2))
            .frame(width: nodeSize, height: nodeSize)
    }

    private func completeToday() {
        let next = progress.completing(today: today)
        pathIndex = next.index
        pathLastCompletedDay = next.lastCompletedDay
    }
}

/// The trail's central strand, derived FROM the node anchors: a C1 cubic
/// Hermite x(y) through them, so the line visibly exists to connect the
/// workouts. Finite-difference tangents mean that when anchors alternate
/// sides, the curve turns around AT each anchor — every figure perches at a
/// bend's apex on near-level ground, like a marker at a switchback.
struct TrailSpine {
    private let ys: [CGFloat], xs: [CGFloat], ms: [CGFloat]   // ms = dx/dy at each knot

    init(anchors: [CGPoint], cx: CGFloat, overrun: CGFloat) {
        // Phantom knots continue the serpentine past both ends (opposite
        // side, softened) so the strands run off screen instead of dying at
        // the first or last workout.
        var pts = anchors
        if let f = anchors.first, let l = anchors.last {
            pts.insert(CGPoint(x: cx - (f.x - cx) * 0.7, y: f.y - overrun * 1.2), at: 0)
            pts.append(CGPoint(x: cx - (l.x - cx) * 0.7, y: l.y + overrun * 1.2))
        }
        ys = pts.map(\.y)
        xs = pts.map(\.x)
        ms = pts.indices.map { i in
            let lo = max(0, i - 1), hi = min(pts.count - 1, i + 1)
            return (pts[hi].x - pts[lo].x) / max(1, pts[hi].y - pts[lo].y)
        }
    }

    /// Strand x at any y; linear along the end tangents beyond the knots.
    func x(_ y: CGFloat) -> CGFloat {
        guard let last = ys.indices.last else { return 0 }
        if y <= ys[0] { return xs[0] + ms[0] * (y - ys[0]) }
        if y >= ys[last] { return xs[last] + ms[last] * (y - ys[last]) }
        var i = 0
        while ys[i + 1] < y { i += 1 }
        let h = ys[i + 1] - ys[i], t = (y - ys[i]) / h
        let t2 = t * t, t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * xs[i] + (t3 - 2 * t2 + t) * h * ms[i]
             + (3 * t2 - 2 * t3) * xs[i + 1] + (t3 - t2) * h * ms[i + 1]
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
