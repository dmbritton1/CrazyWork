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
    static let hairlineStrong  = dynA(dark: (1, 1, 1, 0.16), light: (0, 0, 0, 0.16))
    static let hairlineSoft    = dynA(dark: (1, 1, 1, 0.08), light: (0, 0, 0, 0.08))
    // Today-path woven strands. Light matches hairline/mute so that mode is
    // unchanged; dark goes near-white/bright-grey so the line actually reads.
    static let trailStrand     = dynA(dark: (0.85, 0.87, 0.92, 0.95), light: (0, 0, 0, 0.16))
    static let trailStrandMain = dyn(dark: 0xe4e5ea, light: 0x6a6b6c)
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

    static let accentAquaBright  = hex(0x7df0ea)
    static let accentAqua        = hex(0x34d6cd)
    static let accentAquaPressed = hex(0x28bdb4)
    static let accentTealDeep    = hex(0x0d8f88)
    static let accentTealInk     = hex(0x07514d)
    static let accentAquaSoft    = rgba(0x34d6cd, 0.15)

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
    private static func dynA(dark: (Double, Double, Double, Double),
                             light: (Double, Double, Double, Double)) -> Color {
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
