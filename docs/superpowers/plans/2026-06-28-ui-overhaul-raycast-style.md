# CrazyWork UI Overhaul (Raycast-style) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-skin the entire app to the `DESIGN.md` system — dark near-black canvas, hairline cards, surface-ladder elevation, white/inverting CTA pills, red+aqua accents, Inter/ss03 type — via a shared token+component foundation consumed by every screen.

**Architecture:** A new `Sources/Theme/` foundation (Palette, Typography, Spacing, Radii, Components) provides adaptive tokens; every screen is restyled to consume them. System `List`/`Form` are replaced with `ScrollView`+`Card`. The appearance toggle is kept; tokens resolve per trait collection.

**Tech Stack:** Swift 6, SwiftUI, UIKit (UIFont feature settings, tab/nav bar appearance), Charts, XcodeGen, XCTest.

## Global Constraints

- iOS 18.0, `SWIFT_VERSION` 6.0, strict concurrency. XcodeGen: edit `CrazyWork/project.yml`, regenerate with `cd CrazyWork && xcodegen generate`.
- No screen hardcodes a hex or system font after this work — everything routes through `Palette` / `Typography` / `Spacing` / `Radii`.
- Appearance toggle stays; every `Palette` token is an adaptive `Color` (dark = DESIGN.md verbatim, light = derived mirror per spec table). Accents and gradient stops are identical in both modes.
- ss03 enabled site-wide; display tier adds ss02/ss08 and disables `liga`.
- No drop shadows anywhere; elevation is the surface-color ladder only.
- Build/test: `cd CrazyWork && xcodegen generate && xcodebuild -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' build` (swap `build`→`test` to run tests).
- Reference spec: `docs/superpowers/specs/2026-06-28-ui-overhaul-raycast-style-design.md`.

---

## File Structure

- `CrazyWork/Sources/Resources/Fonts/Inter-Regular.ttf`, `Inter-Medium.ttf`, `Inter-SemiBold.ttf` — bundled fonts (create).
- `CrazyWork/Sources/Theme/Spacing.swift`, `Radii.swift` — scales (create).
- `CrazyWork/Sources/Theme/Palette.swift` — adaptive color tokens (create).
- `CrazyWork/Sources/Theme/Typography.swift` — Inter+ss03 font tokens + `Text` style helper (create).
- `CrazyWork/Sources/Theme/ThemeAppearance.swift` — tab/nav bar UIKit appearance (create).
- `CrazyWork/Sources/Theme/Components/{Card,Buttons,Badge,Keycap,PillTab,Bands,ExerciseTile}.swift` — reusable components (create).
- `CrazyWork/project.yml` — `UIAppFonts` registration (modify).
- All 11 view files under `CrazyWork/Sources/Views/` — restyle (modify).
- `CrazyWork/Tests/ThemeTests.swift` — token sanity tests (create).

---

### Task 1: Spacing, Radii, and bundled Inter fonts

**Files:**
- Create: `CrazyWork/Sources/Theme/Spacing.swift`, `CrazyWork/Sources/Theme/Radii.swift`
- Create: `CrazyWork/Sources/Resources/Fonts/Inter-Regular.ttf`, `Inter-Medium.ttf`, `Inter-SemiBold.ttf`
- Modify: `CrazyWork/project.yml`
- Test: `CrazyWork/Tests/ThemeTests.swift`

**Interfaces:**
- Produces: `enum Spacing { static let xxs/xs/sm/md/lg/xl/xxl/section: CGFloat }`; `enum Radii { static let none/xs/sm/md/lg/xl/full: CGFloat }`; three registered font files.

- [ ] **Step 1: Download the Inter static TTFs**

```bash
cd /tmp && curl -fsSL -o inter.zip https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip && unzip -o inter.zip -d inter_extract >/dev/null && find inter_extract -name "*.ttf" | grep -iE "Regular|Medium|SemiBold" | grep -i "18pt" | head
```

Copy the three 18pt weights into the project, renamed to stable names:

```bash
DEST="/Users/dwightbritton/Desktop/CrazyWork/CrazyWork/Sources/Resources/Fonts"
mkdir -p "$DEST"
cp /tmp/inter_extract/**/Inter_18pt-Regular.ttf  "$DEST/Inter-Regular.ttf"
cp /tmp/inter_extract/**/Inter_18pt-Medium.ttf   "$DEST/Inter-Medium.ttf"
cp /tmp/inter_extract/**/Inter_18pt-SemiBold.ttf "$DEST/Inter-SemiBold.ttf"
```

(If the v4 layout differs, locate the Regular/Medium/SemiBold static TTFs and copy them to those three destination names. The destination filenames are what we register.)

- [ ] **Step 2: Register the fonts in project.yml**

In `CrazyWork/project.yml`, under the `CrazyWork` target `info.properties`, add:

```yaml
        UIAppFonts:
          - Inter-Regular.ttf
          - Inter-Medium.ttf
          - Inter-SemiBold.ttf
```

- [ ] **Step 3: Write Spacing and Radii**

`Spacing.swift`:

```swift
import CoreGraphics

/// 8px spacing scale (DESIGN.md). Tight inline steps at 2/4/12.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let section: CGFloat = 96
}
```

`Radii.swift`:

```swift
import CoreGraphics

/// Border-radius scale (DESIGN.md). Clusters 4–16px; `full` is a pill.
enum Radii {
    static let none: CGFloat = 0
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 16
    static let full: CGFloat = 9999
}
```

- [ ] **Step 4: Write the scale + font-registration test**

Create `CrazyWork/Tests/ThemeTests.swift`:

```swift
import XCTest
import UIKit
@testable import CrazyWork

final class ThemeTests: XCTestCase {
    func testSpacingScaleMonotonic() {
        let s = [Spacing.xxs, Spacing.xs, Spacing.sm, Spacing.md,
                 Spacing.lg, Spacing.xl, Spacing.xxl, Spacing.section]
        XCTAssertEqual(s, s.sorted())
        XCTAssertEqual(Spacing.section, 96)
    }

    func testRadiiScaleMonotonic() {
        XCTAssertLessThan(Radii.xs, Radii.md)
        XCTAssertLessThan(Radii.md, Radii.xl)
        XCTAssertEqual(Radii.none, 0)
    }

    func testInterRegistered() {
        // The app must register Inter; if missing, Typography silently falls back.
        XCTAssertNotNil(UIFont(name: "Inter-Regular", size: 16),
                        "Inter-Regular not registered — check UIAppFonts and PostScript name")
    }
}
```

- [ ] **Step 5: Verify PostScript names, regenerate, run tests**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "ThemeTests|Inter|\*\* (TEST|BUILD)" | tail -15
```

Expected: `testInterRegistered` PASS. If it fails, the registered PostScript name differs from the filename — print it with:

```bash
fc-scan --format "%{postscriptname}\n" "$DEST/Inter-Regular.ttf" 2>/dev/null || \
python3 -c "from fontTools.ttLib import TTFont; print(TTFont('$DEST/Inter-Regular.ttf')['name'].getName(6,3,1))"
```

…and use the actual PostScript names in `Typography.swift` (Task 3). Record the three names for Task 3.

- [ ] **Step 6: Commit**

```bash
git add CrazyWork/Sources/Theme/Spacing.swift CrazyWork/Sources/Theme/Radii.swift \
        CrazyWork/Sources/Resources/Fonts CrazyWork/project.yml CrazyWork/Tests/ThemeTests.swift
git commit -m "feat(theme): bundle Inter, add spacing/radii scales"
```

---

### Task 2: Palette (adaptive color tokens)

**Files:**
- Create: `CrazyWork/Sources/Theme/Palette.swift`
- Test: `CrazyWork/Tests/ThemeTests.swift` (extend)

**Interfaces:**
- Produces: `enum Palette` with `static let` adaptive `Color` tokens listed in the spec (surface ladder, primary trio, text ramp, red ramp, aqua family, blue/green/yellow semantics, gradient stops).

- [ ] **Step 1: Write the failing test**

Add to `ThemeTests.swift`:

```swift
func testCanvasResolvesDifferentlyPerMode() {
    let dark = UIColor(Palette.canvas).resolvedColor(with: .init(userInterfaceStyle: .dark))
    let light = UIColor(Palette.canvas).resolvedColor(with: .init(userInterfaceStyle: .light))
    XCTAssertNotEqual(dark, light, "canvas must mirror between modes")
}

func testAccentConstantAcrossModes() {
    let dark = UIColor(Palette.brandRed).resolvedColor(with: .init(userInterfaceStyle: .dark))
    let light = UIColor(Palette.brandRed).resolvedColor(with: .init(userInterfaceStyle: .light))
    XCTAssertEqual(dark, light, "accents are identical in both modes")
}
```

- [ ] **Step 2: Run to verify it fails**

Run the test command from Task 1 Step 5 filtering `Palette`. Expected: FAIL — `Palette` unresolved.

- [ ] **Step 3: Implement Palette**

```swift
import SwiftUI
import UIKit

/// DESIGN.md color tokens. Dark = doc values; light = derived mirror.
/// Accents and gradient stops are identical in both modes.
enum Palette {
    // Adaptive: distinct dark/light.
    static let canvas          = dyn(dark: 0x07080a, light: 0xf7f7f8)
    static let surface         = dyn(dark: 0x0d0d0d, light: 0xffffff)
    static let surfaceElevated = dyn(dark: 0x101111, light: 0xf0f0f2)
    static let surfaceCard     = dyn(dark: 0x121212, light: 0xeaeaec)
    static let hairline        = dyn(dark: 0x242728, light: 0xe0e0e3)
    static let hairlineStrong  = dynA(dark: (1,1,1,0.16), light: (0,0,0,0.16))
    static let hairlineSoft    = dynA(dark: (1,1,1,0.08), light: (0,0,0,0.08))
    static let ink             = dyn(dark: 0xf4f4f6, light: 0x101114)
    static let body            = dyn(dark: 0xcdcdcd, light: 0x3a3a3d)
    static let mute            = dyn(dark: 0x9c9c9d, light: 0x6a6b6c)
    static let ash             = dyn(dark: 0x6a6b6c, light: 0x9c9c9d)
    static let stone           = dyn(dark: 0x434345, light: 0xc0c0c4)
    static let onDark          = dyn(dark: 0xffffff, light: 0x101114)
    static let primary         = dyn(dark: 0xffffff, light: 0x101114)
    static let primaryPressed  = dyn(dark: 0xe8e8e8, light: 0x2a2a2e)
    static let onPrimary       = dyn(dark: 0x000000, light: 0xffffff)

    // Constant accents (same both modes).
    static let accentRedBright = hex(0xff8a8a)
    static let accentRed       = hex(0xff6161)
    static let brandRed        = hex(0xff3b3b)
    static let brandRedPressed = hex(0xe22d2d)
    static let accentRedDeep   = hex(0xc8202b)
    static let accentRedInk    = hex(0x7a0f15)
    static let accentRedSoft   = rgba(0xff6161, 0.15)
    static let brandRedSoft    = rgba(0xff3b3b, 0.15)

    static let accentAquaBright = hex(0x7df0ea)
    static let accentAqua       = hex(0x34d6cd)
    static let accentAquaPressed = hex(0x28bdb4)
    static let accentTealDeep   = hex(0x0d8f88)
    static let accentTealInk    = hex(0x07514d)
    static let accentAquaSoft   = rgba(0x34d6cd, 0.15)

    static let accentBlue   = hex(0x57c1ff); static let accentBlueSoft   = rgba(0x57c1ff, 0.15)
    static let accentGreen  = hex(0x59d499); static let accentGreenSoft  = rgba(0x59d499, 0.15)
    static let accentYellow = hex(0xffc533); static let accentYellowSoft = rgba(0xffc533, 0.15)

    // Gradient stops (constant).
    static let heroStripeStart = hex(0xff5757)
    static let heroStripeMid   = hex(0xc8202b)
    static let heroStripeEnd   = hex(0x7a0f15)
    static let aquaGlowStart   = hex(0x34d6cd)
    static let aquaGlowEnd     = hex(0x07514d)
    static let keyBgStart      = hex(0x121212)
    static let keyBgEnd        = hex(0x0d0d0d)

    // MARK: builders
    private static func hex(_ v: Int) -> Color { Color(uiColor: ui(v, 1)) }
    private static func rgba(_ v: Int, _ a: Double) -> Color { Color(uiColor: ui(v, a)) }
    private static func dyn(dark: Int, light: Int) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark, 1) : ui(light, 1) })
    }
    private static func dynA(dark: (Double,Double,Double,Double),
                             light: (Double,Double,Double,Double)) -> Color {
        Color(uiColor: UIColor { tc in
            let c = tc.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)
        })
    }
    private static func ui(_ v: Int, _ a: Double) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                blue: CGFloat(v & 0xff) / 255, alpha: a)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run the test command filtering `testCanvasResolves|testAccentConstant`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add CrazyWork/Sources/Theme/Palette.swift CrazyWork/Tests/ThemeTests.swift
git commit -m "feat(theme): adaptive Palette tokens"
```

---

### Task 3: Typography (Inter + ss03)

**Files:**
- Create: `CrazyWork/Sources/Theme/Typography.swift`
- Test: `CrazyWork/Tests/ThemeTests.swift` (extend)

**Interfaces:**
- Produces: `enum Typography` with `Font` tokens (`displayXl … buttonMd`) and `func style(_ token:) -> some ViewModifier` applying font + lineSpacing + tracking. `View.typography(_:)` convenience.

- [ ] **Step 1: Write the failing test**

Add to `ThemeTests.swift`:

```swift
func testInterDescriptorCarriesSS03() {
    let f = Typography.uiFont(size: 16, weight: .regular, tier: .body)
    let feats = f.fontDescriptor.fontAttributes[.featureSettings] as? [[UIFontDescriptor.FeatureKey: Int]]
    XCTAssertNotNil(feats)
    XCTAssertTrue(feats!.contains { $0[.type] == kStylisticAlternativesType && $0[.selector] == 6 },
                  "ss03 (type 35 / selector 6) must be enabled")
}
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `Typography` unresolved.

- [ ] **Step 3: Implement Typography**

Use the verified PostScript names from Task 1 Step 5 (shown here as `Inter-Regular/Medium/SemiBold`):

```swift
import SwiftUI
import UIKit

enum InterTier { case body, display }

enum Typography {
    struct Token { let size: CGFloat; let weight: UIFont.Weight; let leading: CGFloat; let tracking: CGFloat; let tier: InterTier }

    static let displayXl = Token(size: 64, weight: .semibold, leading: 1.1,  tracking: 0,   tier: .display)
    static let displayLg = Token(size: 56, weight: .medium,   leading: 1.17, tracking: 0.2, tier: .display)
    static let headingXl = Token(size: 24, weight: .medium,   leading: 1.6,  tracking: 0.2, tier: .body)
    static let headingLg = Token(size: 22, weight: .medium,   leading: 1.15, tracking: 0,   tier: .body)
    static let headingMd = Token(size: 20, weight: .medium,   leading: 1.4,  tracking: 0.2, tier: .body)
    static let headingSm = Token(size: 18, weight: .medium,   leading: 1.4,  tracking: 0.2, tier: .body)
    static let bodyLg    = Token(size: 18, weight: .regular,  leading: 1.6,  tracking: 0,   tier: .body)
    static let bodyMd    = Token(size: 16, weight: .regular,  leading: 1.6,  tracking: 0,   tier: .body)
    static let bodyStrong = Token(size: 16, weight: .medium,  leading: 1.4,  tracking: 0.2, tier: .body)
    static let bodySm    = Token(size: 14, weight: .regular,  leading: 1.6,  tracking: 0,   tier: .body)
    static let bodySmStrong = Token(size: 14, weight: .medium, leading: 1.6, tracking: 0.2, tier: .body)
    static let captionMd = Token(size: 13, weight: .regular,  leading: 1.4,  tracking: 0.1, tier: .body)
    static let captionSm = Token(size: 12, weight: .regular,  leading: 1.5,  tracking: 0.4, tier: .body)
    static let linkMd    = Token(size: 16, weight: .medium,   leading: 1.4,  tracking: 0.3, tier: .body)
    static let buttonMd  = Token(size: 14, weight: .medium,   leading: 1.6,  tracking: 0.2, tier: .body)

    static func uiFont(size: CGFloat, weight: UIFont.Weight, tier: InterTier) -> UIFont {
        let name: String
        switch weight {
        case .semibold, .bold: name = "Inter-SemiBold"
        case .medium:          name = "Inter-Medium"
        default:               name = "Inter-Regular"
        }
        let base = UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
        var feats: [[UIFontDescriptor.FeatureKey: Int]] = [
            [.type: kStylisticAlternativesType, .selector: 6] // ss03
        ]
        if tier == .display {
            feats.append([.type: kStylisticAlternativesType, .selector: 4])  // ss02
            feats.append([.type: kStylisticAlternativesType, .selector: 16]) // ss08
            feats.append([.type: kLigaturesType, .selector: kCommonLigaturesOffSelector])
        }
        let desc = base.fontDescriptor.addingAttributes([.featureSettings: feats])
        return UIFont(descriptor: desc, size: size)
    }

    static func font(_ t: Token) -> Font { Font(uiFont(size: t.size, weight: t.weight, tier: t.tier)) }
}

struct TypographyStyle: ViewModifier {
    let t: Typography.Token
    func body(content: Content) -> some View {
        content
            .font(Typography.font(t))
            .tracking(t.tracking)
            .lineSpacing(t.size * (t.leading - 1))
    }
}

extension View {
    func typography(_ t: Typography.Token) -> some View { modifier(TypographyStyle(t: t)) }
}
```

- [ ] **Step 4: Run to verify it passes**

Expected: `testInterDescriptorCarriesSS03` PASS.

- [ ] **Step 5: Commit**

```bash
git add CrazyWork/Sources/Theme/Typography.swift CrazyWork/Tests/ThemeTests.swift
git commit -m "feat(theme): Inter typography tokens with ss03"
```

---

### Task 4: Components

**Files:**
- Create: `CrazyWork/Sources/Theme/Components/Card.swift`, `Buttons.swift`, `Badge.swift`, `Keycap.swift`, `PillTab.swift`, `Bands.swift`, `ExerciseTile.swift`

**Interfaces:**
- Consumes: `Palette`, `Typography`, `Spacing`, `Radii`.
- Produces:
  - `View.card(surface:radius:padding:)`
  - `PrimaryButtonStyle`, `SecondaryButtonStyle`, `TertiaryButtonStyle`, `SecondaryRedButtonStyle`, `SecondaryAquaButtonStyle`
  - `Badge(text:_, style: .pro/.redSoft/.aquaSoft/.infoSoft)`
  - `Keycap(_ text:)`
  - `PillTab(title:isActive:action:)`
  - `HeroStripeBand { content }`, `AquaGlowBand { content }`
  - `ExerciseTile(exerciseID:size:)` with `static func symbol(for:) -> String`

- [ ] **Step 1: Write Card**

`Card.swift`:

```swift
import SwiftUI

struct CardModifier: ViewModifier {
    var surface: Color = Palette.surface
    var radius: CGFloat = Radii.lg
    var padding: CGFloat = Spacing.xl
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface)
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Palette.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

extension View {
    func card(surface: Color = Palette.surface, radius: CGFloat = Radii.lg,
              padding: CGFloat = Spacing.xl) -> some View {
        modifier(CardModifier(surface: surface, radius: radius, padding: padding))
    }
}
```

- [ ] **Step 2: Write Buttons**

`Buttons.swift`:

```swift
import SwiftUI

private func pill<C: View>(_ c: C, bg: Color, fg: Color) -> some View {
    c.typography(Typography.buttonMd).foregroundStyle(fg)
        .padding(.vertical, Spacing.sm).padding(.horizontal, Spacing.lg)
        .frame(minHeight: 36).background(bg)
        .clipShape(RoundedRectangle(cornerRadius: Radii.md))
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        pill(c.label, bg: c.isPressed ? Palette.primaryPressed : Palette.primary, fg: Palette.onPrimary)
    }
}
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        pill(c.label, bg: .clear, fg: Palette.onDark).opacity(c.isPressed ? 0.6 : 1)
    }
}
struct TertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        pill(c.label, bg: Palette.surfaceElevated, fg: Palette.onDark).opacity(c.isPressed ? 0.85 : 1)
    }
}
struct SecondaryRedButtonStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        pill(c.label, bg: c.isPressed ? Palette.brandRed.opacity(0.22) : Palette.brandRedSoft,
             fg: c.isPressed ? Palette.onDark : Palette.accentRedBright)
    }
}
struct SecondaryAquaButtonStyle: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        pill(c.label, bg: c.isPressed ? Palette.accentAqua.opacity(0.22) : Palette.accentAquaSoft,
             fg: c.isPressed ? Palette.onDark : Palette.accentAquaBright)
    }
}
```

- [ ] **Step 3: Write Badge, Keycap, PillTab**

`Badge.swift`:

```swift
import SwiftUI

struct Badge: View {
    enum Style { case pro, redSoft, aquaSoft, infoSoft }
    let text: String; var style: Style = .pro
    private var colors: (Color, Color) {
        switch style {
        case .pro:      return (Palette.surfaceElevated, Palette.mute)
        case .redSoft:  return (Palette.brandRedSoft, Palette.accentRedBright)
        case .aquaSoft: return (Palette.accentAquaSoft, Palette.accentAquaBright)
        case .infoSoft: return (Palette.accentBlueSoft, Palette.accentBlue)
        }
    }
    var body: some View {
        Text(text).typography(Typography.captionSm).foregroundStyle(colors.1)
            .padding(.vertical, Spacing.xxs).padding(.horizontal, Spacing.sm)
            .background(colors.0).clipShape(RoundedRectangle(cornerRadius: Radii.xs))
    }
}
```

`Keycap.swift`:

```swift
import SwiftUI

struct Keycap: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).typography(Typography.captionMd).foregroundStyle(Palette.body)
            .padding(.vertical, 1).padding(.horizontal, Spacing.sm).frame(minHeight: 20)
            .background(LinearGradient(colors: [Palette.keyBgStart, Palette.keyBgEnd],
                                       startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: Radii.xs).stroke(Palette.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radii.xs))
    }
}
```

`PillTab.swift`:

```swift
import SwiftUI

struct PillTab: View {
    let title: String; let isActive: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).typography(Typography.bodySm)
                .foregroundStyle(isActive ? Palette.onDark : Palette.body)
                .padding(.vertical, Spacing.xs).padding(.horizontal, Spacing.md)
                .background(isActive ? Palette.surfaceElevated : .clear)
                .clipShape(Capsule())
        }.buttonStyle(.plain)
    }
}
```

- [ ] **Step 4: Write Bands**

`Bands.swift`:

```swift
import SwiftUI

/// Three diagonal red stripes — the signature hero moment (once per page).
struct HeroStripeBand<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Spacing.xxl).padding(.horizontal, Spacing.xl)
            .background(alignment: .top) {
                LinearGradient(colors: [Palette.heroStripeStart, Palette.heroStripeMid, Palette.heroStripeEnd],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(0.9).frame(height: 120).blur(radius: 28)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .background(Palette.canvas)
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
```

- [ ] **Step 5: Write ExerciseTile**

`ExerciseTile.swift`:

```swift
import SwiftUI

struct ExerciseTile: View {
    let exerciseID: String
    var size: CGFloat = 48
    var body: some View {
        RoundedRectangle(cornerRadius: Radii.md).fill(Palette.surfaceCard)
            .frame(width: size, height: size)
            .overlay(Image(systemName: Self.symbol(for: exerciseID))
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundStyle(Palette.body))
    }
    static func symbol(for id: String) -> String {
        switch id {
        case "pushup":      return "figure.strengthtraining.functional"
        case "squat":       return "figure.cross.training"
        case "lunge":       return "figure.step.training"
        case "plank":       return "figure.core.training"
        case "situp":       return "figure.core.training"
        case "glutebridge": return "figure.flexibility"
        default:            return "figure.strengthtraining.traditional"
        }
    }
}
```

- [ ] **Step 6: Build to verify components compile**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -8
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add CrazyWork/Sources/Theme/Components
git commit -m "feat(theme): Card, buttons, badge, keycap, pill-tab, bands, exercise tile"
```

---

### Task 5: RootView + tab/nav bar theming

**Files:**
- Create: `CrazyWork/Sources/Theme/ThemeAppearance.swift`
- Modify: `CrazyWork/Sources/Views/RootView.swift`

**Interfaces:**
- Consumes: `Palette`.
- Produces: `enum ThemeAppearance { static func configure() }`.

- [ ] **Step 1: Write ThemeAppearance**

```swift
import UIKit

enum ThemeAppearance {
    /// Themes UIKit-backed bars (tab + nav) to the canvas surface with hairline rules.
    static func configure() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Palette.canvas)
        tab.shadowColor = UIColor(Palette.hairline)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().tintColor = UIColor(Palette.onDark)
        UITabBar.appearance().unselectedItemTintColor = UIColor(Palette.mute)

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Palette.canvas)
        nav.shadowColor = UIColor(Palette.hairline)
        nav.titleTextAttributes = [.foregroundColor: UIColor(Palette.ink)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Palette.ink)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
}
```

- [ ] **Step 2: Call it from RootView**

In `RootView.swift`, add an `init()` that calls `ThemeAppearance.configure()`, and set the tab accent:

```swift
init() { ThemeAppearance.configure() }
```

Add `.tint(Palette.onDark)` to the `TabView` and keep `.preferredColorScheme(appearance.colorScheme)`.

- [ ] **Step 3: Build**

Run the build command. Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add CrazyWork/Sources/Theme/ThemeAppearance.swift CrazyWork/Sources/Views/RootView.swift
git commit -m "feat(theme): themed tab + nav bars"
```

---

### Task 6: BuildWorkoutView

**Files:**
- Modify: `CrazyWork/Sources/Views/BuildWorkoutView.swift`

**Interfaces:** Consumes all theme tokens + `Card`, `ExerciseTile`, `PrimaryButtonStyle`, `HeroStripeBand`.

Replace the `List`-based body with a canvas `ScrollView` of `Card`s. Structure:
- Root: `ZStack { Palette.canvas.ignoresSafeArea(); ScrollView { VStack(spacing: Spacing.lg) {...} } }` inside the existing `NavigationStack`.
- Header: `HeroStripeBand { VStack(alignment:.leading) { Text("Build Workout").typography(Typography.displayLg)... } }` — the page's single red moment (replaces `.navigationTitle`; use `.navigationBarTitleDisplayMode(.inline)` with empty title or `.toolbar(.hidden)`).
- "Add exercise": horizontal `ScrollView` of `ExerciseTile` buttons (tap appends an entry), each labeled with `Typography.bodySm`.
- "Your workout": each `entry` rendered in a `.card()` containing `ExerciseTile` + name (`headingSm`) + the existing steppers, restyled with `Palette.body`/`mute` text. Empty state: `Text("No exercises yet").typography(Typography.bodyMd).foregroundStyle(Palette.mute)`.
- Rest stepper: a `.card()` row.
- "Save workout": `Button` with `.buttonStyle(TertiaryButtonStyle())`.
- Bottom `safeAreaInset`: the Start button uses `.buttonStyle(PrimaryButtonStyle())` with `.frame(maxWidth: .infinity)`; keep the `NavigationLink`.
- Keep all logic (`defaultTarget`, `plannedSetCount`, save alert, `WorkoutPlan.expand`) unchanged.

- [ ] **Step 1: Restyle the view** per the structure above. Steppers keep their bindings; wrap each `EntryRow` body in tokens (`Text(name).typography(Typography.headingSm)`, vertical spacing `Spacing.sm`).
- [ ] **Step 2: Build.** Run the build command. Expected: BUILD SUCCEEDED.
- [ ] **Step 3: Screenshot dark + light** (sanity): boot sim, run app, capture Build screen in both modes. (Manual — verify canvas, hairline cards, white Start pill, red header band.)
- [ ] **Step 4: Commit**

```bash
git add CrazyWork/Sources/Views/BuildWorkoutView.swift
git commit -m "feat(ui): restyle Build Workout to theme"
```

---

### Task 7: PremadePlansView

**Files:**
- Modify: `CrazyWork/Sources/Views/PremadePlansView.swift`

**Interfaces:** Consumes `Card`, tokens; `ExerciseRegistry` (unchanged).

Replace `List` with `ScrollView`+`LazyVStack(spacing: Spacing.lg)` on `Palette.canvas`. Each plan/saved-workout `card(_:)` becomes a `.card()`:
- Name `Typography.headingSm` `Palette.ink`; trailing `~N min` as a `Keycap` or `Badge(.pro)`.
- Summary `Typography.bodySm` `Palette.mute`; exercise list `Typography.captionMd` `Palette.stone`.
- Section headers ("My Workouts", "Plans") as `Text(...).typography(Typography.bodySmStrong).foregroundStyle(Palette.mute)`.
- Saved cards: swipe-to-delete is gone with `List`; add a trailing `Button { modelContext.delete(workout) }` with `Image(systemName: "trash")` `.foregroundStyle(Palette.mute)`, shown on saved cards only.
- Keep `onChoose`, `asPlan`, `PremadePlanCatalog.all`.

- [ ] **Step 1: Restyle** per above. Wrap the choose action in `Button { onChoose(plan) } label: { card }.buttonStyle(.plain)`.
- [ ] **Step 2: Build.** Expected: BUILD SUCCEEDED.
- [ ] **Step 3: Commit**

```bash
git add CrazyWork/Sources/Views/PremadePlansView.swift
git commit -m "feat(ui): restyle Plans to theme cards"
```

---

### Task 8: StatsView, HistoryView, ConsistencyCalendarView

**Files:**
- Modify: `CrazyWork/Sources/Views/StatsView.swift`, `HistoryView.swift`, `ConsistencyCalendarView.swift`

**Interfaces:** Consumes `Card`, tokens; Charts.

- **StatsView:** canvas background; stat tiles as `.card(surface: Palette.surfaceElevated)`; Charts series → `.foregroundStyle(Palette.brandRed)` primary / `Palette.accentAqua` secondary; axis/grid `Palette.hairline`; titles `Typography.headingMd`, numbers `Typography.displayLg`/`headingXl`.
- **HistoryView:** `List` → `ScrollView`+`LazyVStack` of `.card()` rows; date `Typography.bodyStrong`, metrics `Typography.bodySm` `Palette.mute`.
- **ConsistencyCalendarView:** cells use the surface ladder for activity intensity (`surface` → `surfaceElevated` → `surfaceCard`), most-active day `Palette.brandRed`, today's ring `Palette.accentAqua`; labels `Typography.captionSm` `Palette.mute`.

- [ ] **Step 1: Read each file**, then restyle to tokens preserving all data/query logic.
- [ ] **Step 2: Build.** Expected: BUILD SUCCEEDED.
- [ ] **Step 3: Commit**

```bash
git add CrazyWork/Sources/Views/StatsView.swift CrazyWork/Sources/Views/HistoryView.swift CrazyWork/Sources/Views/ConsistencyCalendarView.swift
git commit -m "feat(ui): restyle Stats, History, Calendar to theme"
```

---

### Task 9: ProfileView

**Files:**
- Modify: `CrazyWork/Sources/Views/ProfileView.swift`

**Interfaces:** Consumes `Card`, tokens; keeps `@AppStorage` settings incl. `healthSyncEnabled` and the appearance picker (which drives the palette).

Replace `Form` with `ScrollView` of `.card()` sections on `Palette.canvas`:
- Name field + lifetime stats in a header card (stats via the existing `stat(_:_:)` helper, restyled to `Typography.displayLg`/`captionSm`).
- "Settings" card: sound toggle, appearance picker, voice picker, preview button (`TertiaryButtonStyle`).
- "Apple Health" card: keep the `HKHealthStore.isHealthDataAvailable()` gate and the toggle.
- "Pose overlay" card: presets as `PillTab`s; color/thickness pickers; joint/skeleton toggles.
- Toggles tinted `.tint(Palette.brandRed)`; section titles `Typography.bodySmStrong` `Palette.mute`.
- Keep `previewVoice()`, `apply(_:)`, `voices`, `SpeechSessionEnder` unchanged.

- [ ] **Step 1: Restyle** per above.
- [ ] **Step 2: Build.** Expected: BUILD SUCCEEDED.
- [ ] **Step 3: Commit**

```bash
git add CrazyWork/Sources/Views/ProfileView.swift
git commit -m "feat(ui): restyle Profile to theme"
```

---

### Task 10: LiveWorkoutView + RestCountdownView

**Files:**
- Modify: `CrazyWork/Sources/Views/LiveWorkoutView.swift`, `RestCountdownView.swift`

**Interfaces:** Consumes tokens, `Keycap`, `ExerciseTile`, `AquaGlowBand`.

- **LiveWorkoutView:** retint the HUD over the camera — progress/rep count `Typography.displayLg` `Palette.ink`; form-cue text `Palette.accentRedBright` when a fault is shown, hidden otherwise; any shortcut/among hints as `Keycap`. Keep camera, pipeline, coordinator, and `saveIfNeeded()` (incl. the Health write) untouched. `clock(_:)` stays.
- **RestCountdownView:** `Palette.canvas` background; countdown `Typography.displayXl` `Palette.ink`; next-exercise `ExerciseTile` + name; wrap the panel in `AquaGlowBand` as the calm secondary moment; "Skip"/"Begin" as `TertiaryButtonStyle`/`PrimaryButtonStyle`.

- [ ] **Step 1: Read both files**, restyle to tokens; do not touch capture/session logic.
- [ ] **Step 2: Build.** Expected: BUILD SUCCEEDED.
- [ ] **Step 3: Commit**

```bash
git add CrazyWork/Sources/Views/LiveWorkoutView.swift CrazyWork/Sources/Views/RestCountdownView.swift
git commit -m "feat(ui): restyle Live workout + Rest to theme"
```

---

### Task 11: SummaryView + WorkoutShareCard

**Files:**
- Modify: `CrazyWork/Sources/Views/SummaryView.swift`, `WorkoutShareCard.swift`

**Interfaces:** Consumes tokens, `Card`, `PrimaryButtonStyle`.

- **SummaryView:** `Palette.canvas` background; "Workout Complete" `Typography.displayLg` `Palette.ink`; chart bars `Palette.brandRed` (volume) and `Palette.accentAqua`/`accentGreen` (form), `.chartYScale` kept; per-set rows wrapped in `.card()`; Share as `PrimaryButtonStyle`; Done as `SecondaryButtonStyle`. Keep `rows`, totals, `shareImage()`.
- **WorkoutShareCard:** image renders mode-independent — use the **dark** look explicitly: background `Palette.surface` resolved dark, border `Palette.hairline`, "CrazyWork" `Typography.headingSm` `Palette.ink`, stat values `Palette.brandRed` `Typography.headingXl`, labels `Palette.mute`. (Use the dark constants directly so the shared image is always the branded dark card; wrap in `.environment(\.colorScheme, .dark)` on the rendered content.)

- [ ] **Step 1: Restyle both.** For the share card, set `.environment(\.colorScheme, .dark)` in `shareImage()`'s `ImageRenderer` content so tokens resolve dark regardless of app mode.
- [ ] **Step 2: Build.** Expected: BUILD SUCCEEDED.
- [ ] **Step 3: Run full test sweep**

```bash
cd /Users/dwightbritton/Desktop/CrazyWork/ChallengeCore && swift test 2>&1 | tail -3
cd /Users/dwightbritton/Desktop/CrazyWork/CrazyWork && xcodegen generate >/dev/null && \
xcodebuild -scheme CrazyWork -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "Executed|\*\* (TEST|BUILD)" | tail -5
```

Expected: ChallengeCore green; ThemeTests + CalorieEstimatorTests + existing tests pass; TEST SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add CrazyWork/Sources/Views/SummaryView.swift CrazyWork/Sources/Views/WorkoutShareCard.swift
git commit -m "feat(ui): restyle Summary + share card to theme"
```

---

## Self-Review

**Spec coverage:**
- Theme foundation (Palette/Typography/Spacing/Radii) → Tasks 1–3. ✓
- Inter+ss03 pipeline → Tasks 1 & 3. ✓
- Light-mode mirror → Task 2 (`dyn`/`dynA` + spec hex table). ✓
- Components (Card, buttons, badge, keycap, pill-tab, bands, exercise tile) → Task 4. ✓
- Tab/nav theming → Task 5. ✓
- All screens (Build/Plans/Stats/History/Calendar/Profile/Live/Rest/Summary/ShareCard) → Tasks 6–11. ✓
- List/Form → ScrollView+Card → Tasks 6,7,8,9. ✓
- Appearance toggle kept, drives palette → Task 2 + Task 9 (picker retained). ✓
- Tests → Tasks 1–3 (ThemeTests). ✓

**Placeholder scan:** screen tasks (6–11) intentionally specify token mappings + structure rather than full reproduced SwiftUI, since they are mechanical restyles over unchanged logic and each ends in a build gate. Foundation tasks (1–4) carry complete code. No "TBD"/"handle edge cases".

**Type consistency:** `Palette`, `Typography.font/uiFont/Token`, `Spacing`, `Radii`, `.card(...)`, the five `*ButtonStyle`s, `Badge`/`Keycap`/`PillTab`/`HeroStripeBand`/`AquaGlowBand`/`ExerciseTile`, `ThemeAppearance.configure()` — names are identical across producer (Tasks 1–5) and consumer (Tasks 6–11) references. `ss03` = type `kStylisticAlternativesType` / selector 6 consistent in spec, Task 3 code, and Task 3 test.
