import Foundation

/// What one file becomes: its size, frame rate and bit rate. Every number here comes from
/// docs/encoding.md; change them there first.
public struct EncodePlan: Equatable, Sendable {
    /// Encoded size in pixels, as stored (before the track's rotation, if any).
    public var width: Int
    public var height: Int
    /// The source's nominal frame rate. Frames keep their own timestamps; this only tells the
    /// encoder what to expect.
    public var frameRate: Double
    /// VideoToolbox's average target, bits per second.
    public var averageBitRate: Int
    /// A hard ceiling over `peakWindow` seconds, bits per second, or none. The intermediate has
    /// none: ADR-0007 §8 measured it with an average alone.
    public var peakBitRate: Int?
    public var peakWindow: Double

    public static let audioBitRate = 256_000
    public static let audioSampleRate = 48_000.0
    public static let keyFrameInterval = 4.0
}

public enum Plan {
    /// The server's 4K box (video-pipeline's `BOXES["2160"]`). A source that fits keeps its
    /// size; a larger one is scaled into it. Portrait turns the box.
    public static let box = (width: 3840, height: 2160)

    /// The intermediate's rate up to 30 fps (ADR-0007 §8): the 4K rung made from it loses at most
    /// 1 VMAF point (`vmaf_4k_v0.6.1`) against the rung made from the ProRes. 50 Mbit/s lost 0.8
    /// on the alpaca clip; the first real export decides (bin/rungs.zsh). One rate for every
    /// size: VideoToolbox takes the same time at any rate.
    public static let standardBitRate = 50_000_000

    /// The rate above 30 fps. The intermediate is also the master Funkhaus sends to YouTube,
    /// which recommends 53 to 68 Mbit/s for SDR 2160p at 48 to 60 fps (35 to 45 up to 30 fps);
    /// 70 clears the top of that range.
    public static let highFrameRateBitRate = 70_000_000

    /// Above this the source counts as high frame rate: 48, 50, 59.94 and 60 fps are above it,
    /// 29.97 and 30 below, also when a track's nominal rate reads a little over 30.
    public static let highFrameRate = 30.5

    /// The average rate for a source of `frameRate` frames per second.
    public static func averageBitRate(frameRate: Double) -> Int {
        frameRate > highFrameRate ? highFrameRateBitRate : standardBitRate
    }

    /// The size the server would make its top rung: kept aspect, even sides, never upscaled.
    public static func fit(width: Int, height: Int) -> (width: Int, height: Int) {
        var bw = Double(box.width), bh = Double(box.height)
        if height > width { swap(&bw, &bh) }
        let w = Double(width), h = Double(height)
        let s = min(bw / w, bh / h, 1.0)
        // Python's round(), as the server computes it: halves go to the even neighbour, so
        // 4096x2160 becomes 3840x2024 on both sides.
        return (Int((w * s / 2).rounded(.toNearestOrEven)) * 2, Int((h * s / 2).rounded(.toNearestOrEven)) * 2)
    }

    public static func make(width: Int, height: Int, frameRate: Double) -> EncodePlan {
        let size = fit(width: width, height: height)
        let rate = frameRate > 0 ? frameRate : 25
        return EncodePlan(width: size.width, height: size.height, frameRate: rate,
                          averageBitRate: averageBitRate(frameRate: rate), peakBitRate: nil, peakWindow: 1)
    }
}
