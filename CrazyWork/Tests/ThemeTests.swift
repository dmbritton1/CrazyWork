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

    func testInterDescriptorCarriesSS03() {
        let f = Typography.uiFont(size: 16, weight: .regular, tier: .body)
        let feats = f.fontDescriptor.fontAttributes[.featureSettings] as? [[UIFontDescriptor.FeatureKey: Int]]
        XCTAssertNotNil(feats)
        XCTAssertTrue(feats!.contains { $0[.type] == kStylisticAlternativesType && $0[.selector] == 6 },
                      "ss03 (type 35 / selector 6) must be enabled")
    }
}
