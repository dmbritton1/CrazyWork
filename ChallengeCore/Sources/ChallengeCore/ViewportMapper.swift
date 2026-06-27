/// Maps a normalized pose point onto on-screen coordinates, matching how the
/// camera preview is displayed.
///
/// Input is in Vision's convention: normalized `0...1`, origin **bottom-left**
/// (y up). Output is in screen convention: origin **top-left** (y down). The
/// transform mirrors `.resizeAspectFill` — the image is scaled to cover the view
/// and the overflowing axis is cropped equally on both sides — so the skeleton
/// lines up with the body in the preview instead of drifting.
public enum ViewportMapper {
    public static func aspectFill(nx: Double, ny: Double,
                                  imageW: Double, imageH: Double,
                                  viewW: Double, viewH: Double) -> (x: Double, y: Double) {
        guard imageW > 0, imageH > 0 else { return (nx * viewW, (1 - ny) * viewH) }
        let scale = max(viewW / imageW, viewH / imageH)
        let displayW = imageW * scale
        let displayH = imageH * scale
        let offsetX = (viewW - displayW) / 2
        let offsetY = (viewH - displayH) / 2
        let x = offsetX + nx * displayW
        let y = offsetY + (1 - ny) * displayH   // flip y into top-left space
        return (x, y)
    }
}
