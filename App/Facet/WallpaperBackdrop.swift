import SwiftUI
import FacetCore

/// A wallpaper decoded once into a flat RGBA buffer so tapping to sample a
/// colour is an index lookup, not an image draw per touch. The whole point of
/// a Scene: the widget is designed against the surface it will live on, and its
/// fill can be *taken from* that surface.
struct SampledImage {
    let width: Int
    let height: Int
    private let pixels: [UInt8]

    /// Downscaled to a modest size — sampling wants a representative colour, not
    /// per-pixel fidelity, and a 400px buffer keeps the decode cheap.
    init?(_ image: UIImage, maxSize: Int = 400) {
        guard let cg = image.cgImage else { return nil }
        let scale = min(1, Double(maxSize) / Double(max(cg.width, cg.height)))
        let w = max(1, Int(Double(cg.width) * scale))
        let h = max(1, Int(Double(cg.height) * scale))
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // Flip so buffer row 0 is the image's top edge, matching the unit
        // coordinates a tap gives us (origin top-left).
        context.translateBy(x: 0, y: CGFloat(h))
        context.scaleBy(x: 1, y: -1)
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        self.width = w
        self.height = h
        self.pixels = buffer
    }

    /// The colour at a normalized 0...1 point (top-left origin).
    func color(atUnit point: CGPoint) -> ColorValue? {
        guard width > 0, height > 0 else { return nil }
        let x = min(max(Int(point.x * Double(width)), 0), width - 1)
        let y = min(max(Int(point.y * Double(height)), 0), height - 1)
        let index = (y * width + x) * 4
        return ColorValue(
            red: Double(pixels[index]) / 255,
            green: Double(pixels[index + 1]) / 255,
            blue: Double(pixels[index + 2]) / 255
        )
    }
}

/// The editor canvas backdrop: the wallpaper shown behind the widget (fit, so
/// the whole image is visible for designing against), with an eyedropper that
/// maps a tap to the underlying pixel. Falls back to the dot grid when no
/// wallpaper is set.
struct WallpaperBackdrop: View {
    let image: UIImage?
    let sampler: SampledImage?
    let sampling: Bool
    let onSample: (ColorValue) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .opacity(sampling ? 1 : 0.9)
                } else {
                    FacetUI.bg
                    DotGrid()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(sampling && image != nil ? sampleGesture(in: geo.size, image: image) : nil)
        }
    }

    /// Maps a tap in the view to the fitted image's own 0...1 space, ignoring
    /// the letterbox bars a fit leaves, then samples that pixel.
    private func sampleGesture(in size: CGSize, image: UIImage?) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            guard let image, let sampler else { return }
            let imageAspect = image.size.width / max(image.size.height, 1)
            let viewAspect = size.width / max(size.height, 1)
            var drawn = size
            if imageAspect > viewAspect {
                drawn.height = size.width / imageAspect      // letterboxed top/bottom
            } else {
                drawn.width = size.height * imageAspect       // pillarboxed left/right
            }
            let originX = (size.width - drawn.width) / 2
            let originY = (size.height - drawn.height) / 2
            let local = CGPoint(x: value.location.x - originX, y: value.location.y - originY)
            guard local.x >= 0, local.y >= 0, local.x <= drawn.width, local.y <= drawn.height else { return }
            let unit = CGPoint(x: local.x / drawn.width, y: local.y / drawn.height)
            if let color = sampler.color(atUnit: unit) {
                onSample(color)
            }
        }
    }
}
