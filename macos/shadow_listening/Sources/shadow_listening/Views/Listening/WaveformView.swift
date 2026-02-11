import SwiftUI

// MARK: - WaveformView

struct WaveformView: View {
    private let preset: WaveformPreset
    private let playback: WaveformPlayback
    private let theme: WaveformTheme
    private let size: WaveformSize

    @State private var startedAt = Date()

    init(style: WaveformStyle = .assistantPreview, size: WaveformSize = .medium) {
        self.preset = style.preset
        self.playback = style.playback
        self.theme = style.theme
        self.size = size
    }

    init(
        preset: WaveformPreset,
        playback: WaveformPlayback,
        theme: WaveformTheme,
        size: WaveformSize = .medium
    ) {
        self.preset = preset
        self.playback = playback
        self.theme = theme
        self.size = size
    }

    /// RMS 볼륨 레벨 기반 이니셜라이저 (0.0 ~ 1.0)
    init(rmsLevel: CGFloat, size: WaveformSize = .medium) {
        self.preset = WaveformPreset.lottieReference()
        self.playback = .rms(level: rmsLevel)
        self.theme = .assistantOrange
        self.size = size
    }

    var body: some View {
        let target = size.resolved
        let scaleX = target.width / preset.compositionSize.width
        let scaleY = target.height / preset.compositionSize.height

        TimelineView(.animation(minimumInterval: 1.0 / preset.renderFPS)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
            let playbackState = playback.state(
                elapsed: elapsed,
                sourceFPS: preset.sourceFPS,
                loopFrames: preset.loopFrames
            )

            ZStack {
                ForEach(preset.bars) { bar in
                    let animatedScaleY = WaveformInterpolator.value(
                        at: playbackState.frame,
                        in: bar.keyframes
                    )
                    let finalScaleY = WaveformInterpolator.lerp(
                        animatedScaleY,
                        playbackState.restingScaleY,
                        t: playbackState.settleProgress
                    )
                    let width = preset.baseBarSize.width * preset.barScaleX
                    let height = max(
                        1,
                        preset.baseBarSize.height * (bar.layerScaleY / 100.0) * (finalScaleY / 100.0)
                    )

                    RoundedRectangle(cornerRadius: width / 2, style: .continuous)
                        .fill(theme.barColor)
                        .frame(width: width, height: height)
                        .position(
                            x: bar.layerPosition.x + preset.barOffset.x,
                            y: bar.layerPosition.y + preset.barOffset.y
                        )
                }
            }
            .frame(width: preset.compositionSize.width, height: preset.compositionSize.height)
            .scaleEffect(x: scaleX, y: scaleY, anchor: .center)
        }
        .frame(width: target.width, height: target.height)
        .onAppear {
            startedAt = Date()
        }
    }
}

// MARK: - WaveformStyle

struct WaveformStyle {
    let preset: WaveformPreset
    let playback: WaveformPlayback
    let theme: WaveformTheme

    static let assistantPreview = WaveformStyle(
        preset: .lottieReference(),
        playback: .preview(seconds: 5),
        theme: .assistantOrange
    )

    static let assistantLoop = WaveformStyle(
        preset: .lottieReference(),
        playback: .loop,
        theme: .assistantOrange
    )
}

// MARK: - WaveformSize

struct WaveformSize {
    let width: CGFloat
    let height: CGFloat

    var resolved: CGSize { CGSize(width: width, height: height) }

    static let xSmall = WaveformSize.square(18)
    static let small = WaveformSize.square(24)
    static let medium = WaveformSize.square(36)
    static let large = WaveformSize.square(52)

    static func square(_ side: CGFloat) -> WaveformSize {
        WaveformSize(width: side, height: side)
    }

    static func custom(width: CGFloat, height: CGFloat) -> WaveformSize {
        WaveformSize(width: width, height: height)
    }
}

// MARK: - WaveformTheme

struct WaveformTheme {
    let barColor: Color

    static let assistantOrange = WaveformTheme(
        barColor: Color.brandSecondary
    )
}

// MARK: - WaveformPlayback

enum WaveformPlayback {
    case loop
    case preview(seconds: Double, settleDuration: Double = 0.35, restingScaleY: CGFloat = 55)
    case rms(level: CGFloat)  // 0.0 (silence) ~ 1.0 (loud)

    fileprivate func state(elapsed: Double, sourceFPS: Double, loopFrames: Double) -> WaveformPlaybackState {
        switch self {
        case .loop:
            let frame = (elapsed * sourceFPS).truncatingRemainder(dividingBy: loopFrames)
            return WaveformPlaybackState(frame: frame, settleProgress: 0, restingScaleY: 100)
        case let .preview(seconds, settleDuration, restingScaleY):
            let stopFrame = (seconds * sourceFPS).truncatingRemainder(dividingBy: loopFrames)
            let frame = elapsed <= seconds
                ? (elapsed * sourceFPS).truncatingRemainder(dividingBy: loopFrames)
                : stopFrame
            let settleProgress = max(0, min(1, (elapsed - seconds) / settleDuration))
            return WaveformPlaybackState(
                frame: frame,
                settleProgress: CGFloat(settleProgress),
                restingScaleY: restingScaleY
            )
        case let .rms(level):
            // Loop animation continues running; level controls amplitude via settleProgress
            // settleProgress = 1 → fully resting (silent), settleProgress = 0 → full animation (loud)
            let clamped = max(0, min(1, level))
            let frame = (elapsed * sourceFPS).truncatingRemainder(dividingBy: loopFrames)
            let restingScaleY: CGFloat = 30  // minimum bar height when silent
            return WaveformPlaybackState(frame: frame, settleProgress: 1 - clamped, restingScaleY: restingScaleY)
        }
    }
}

// MARK: - WaveformPreset

struct WaveformPreset {
    let sourceFPS: Double
    let renderFPS: Double
    let loopFrames: Double
    let compositionSize: CGSize
    let baseBarSize: CGSize
    let barOffset: CGPoint
    let barScaleX: CGFloat
    fileprivate let bars: [WaveformBar]

    static func lottieReference(renderFPS: Double = 60) -> WaveformPreset {
        WaveformPreset(
            sourceFPS: 24,
            renderFPS: renderFPS,
            loopFrames: 40,
            compositionSize: CGSize(width: 28, height: 28),
            baseBarSize: CGSize(width: 2, height: 14.312),
            barOffset: CGPoint(x: -12.188, y: 0.531),
            barScaleX: 1.2,
            bars: LottieReferenceBars.bars
        )
    }
}

// MARK: - Internal Types

private struct WaveformPlaybackState {
    let frame: Double
    let settleProgress: CGFloat
    let restingScaleY: CGFloat
}

fileprivate struct WaveformBar: Identifiable {
    let id: Int
    let layerPosition: CGPoint
    let layerScaleY: CGFloat
    let keyframes: [WaveformKeyframe]
}

fileprivate struct WaveformKeyframe {
    let frame: Double
    let value: CGFloat
    let inTangent: CGPoint
    let outTangent: CGPoint
}

// MARK: - Interpolation Engine

private enum WaveformInterpolator {
    static func value(at frame: Double, in keyframes: [WaveformKeyframe]) -> CGFloat {
        guard keyframes.count > 1 else { return keyframes.first?.value ?? 100 }

        for index in 0..<(keyframes.count - 1) {
            let current = keyframes[index]
            let next = keyframes[index + 1]

            guard frame >= current.frame, frame <= next.frame else { continue }

            let span = next.frame - current.frame
            guard span > 0.0001 else { return current.value }

            let rawProgress = (frame - current.frame) / span
            let easedProgress = cubicBezierY(
                x: rawProgress,
                c1: current.outTangent,
                c2: next.inTangent
            )

            return lerp(current.value, next.value, t: CGFloat(easedProgress))
        }

        return keyframes.last?.value ?? 100
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private static func cubicBezierY(x: Double, c1: CGPoint, c2: CGPoint) -> Double {
        let clampedX = min(max(x, 0), 1)
        let solvedT = solveBezierParameter(
            x: clampedX,
            c1x: Double(c1.x),
            c2x: Double(c2.x)
        )
        return sampleBezier(solvedT, p1: Double(c1.y), p2: Double(c2.y))
    }

    private static func solveBezierParameter(x: Double, c1x: Double, c2x: Double) -> Double {
        var t = x

        for _ in 0..<6 {
            let xEstimate = sampleBezier(t, p1: c1x, p2: c2x) - x
            let derivative = sampleBezierDerivative(t, p1: c1x, p2: c2x)

            if abs(xEstimate) < 0.000001 {
                return t
            }

            if abs(derivative) < 0.000001 {
                break
            }

            t -= xEstimate / derivative
        }

        var lower = 0.0
        var upper = 1.0
        t = x

        for _ in 0..<14 {
            let estimate = sampleBezier(t, p1: c1x, p2: c2x)

            if abs(estimate - x) < 0.000001 {
                return t
            }

            if estimate < x {
                lower = t
            } else {
                upper = t
            }

            t = (lower + upper) * 0.5
        }

        return t
    }

    private static func sampleBezier(_ t: Double, p1: Double, p2: Double) -> Double {
        let u = 1.0 - t
        return (3.0 * u * u * t * p1) + (3.0 * u * t * t * p2) + (t * t * t)
    }

    private static func sampleBezierDerivative(_ t: Double, p1: Double, p2: Double) -> Double {
        let u = 1.0 - t
        return (3.0 * u * u * p1) + (6.0 * u * t * (p2 - p1)) + (3.0 * t * t * (1.0 - p2))
    }
}

// MARK: - Keyframe Data (Lottie Reference)

private enum LottieReferenceBars {
    static func k(_ frame: Double, _ value: CGFloat, inY: CGFloat = 1, outY: CGFloat = 0) -> WaveformKeyframe {
        WaveformKeyframe(
            frame: frame,
            value: value,
            inTangent: CGPoint(x: 0.667, y: inY),
            outTangent: CGPoint(x: 0.333, y: outY)
        )
    }

    static let bars: [WaveformBar] = [
        WaveformBar(
            id: 1,
            layerPosition: CGPoint(x: 15.125, y: 13.625),
            layerScaleY: 66.981,
            keyframes: [
                k(0, 100),
                k(5, 70),
                k(10, 50),
                k(15, 80),
                k(20, 160, inY: 0.954, outY: 0),
                k(25, 80, inY: -0.718, outY: -0.37),
                k(30, 90, inY: 1, outY: -0.859),
                k(35, 70),
                k(40, 90)
            ]
        ),
        WaveformBar(
            id: 2,
            layerPosition: CGPoint(x: 22.562, y: 12.938),
            layerScaleY: 183.019,
            keyframes: [
                k(0, 100),
                k(5, 50),
                k(10, 80),
                k(15, 70),
                k(20, 40, inY: 0.877, outY: 0),
                k(25, 70, inY: 0.718, outY: 0.37),
                k(30, 80, inY: 1, outY: 0.282),
                k(35, 90),
                k(40, 100)
            ]
        ),
        WaveformBar(
            id: 3,
            layerPosition: CGPoint(x: 30.188, y: 13.375),
            layerScaleY: 100.943,
            keyframes: [
                k(0, 100),
                k(5, 50),
                k(10, 60),
                k(15, 60),
                k(20, 50, inY: 1.37, outY: 0),
                k(25, 60, inY: -0.718, outY: -0.37),
                k(30, 70, inY: 1, outY: 0.215),
                k(35, 150),
                k(40, 90)
            ]
        ),
        WaveformBar(
            id: 4,
            layerPosition: CGPoint(x: 37.312, y: 13.312),
            layerScaleY: 132.075,
            keyframes: [
                k(0, 100),
                k(5, 80),
                k(10, 70),
                k(15, 60),
                k(20, 70, inY: 0.926, outY: 0),
                k(25, 120, inY: 1.056, outY: -0.074),
                k(30, 70, inY: 1, outY: 0.282),
                k(35, 80),
                k(40, 90)
            ]
        )
    ]
}
