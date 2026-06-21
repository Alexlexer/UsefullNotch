import AppKit
import SwiftUI

enum SiriNotchState: Equatable {
    case hidden
    case activating
    case listening
    case transitioningToSearch
    case searching(String)
    case dismissing
}

struct SiriNotchMetrics {
    let compactWidth: CGFloat
    let compactHeight: CGFloat
    let blobWidth: CGFloat
    let blobHeight: CGFloat
    let capsuleWidth: CGFloat
    let capsuleHeight: CGFloat
    let maximumCanvasWidth: CGFloat
    let maximumCanvasHeight: CGFloat

    static func defaultMetrics() -> SiriNotchMetrics {
        let compactWidth: CGFloat = 212
        let compactHeight: CGFloat = 34
        let blobWidth = compactWidth * 1.38
        let blobHeight = compactHeight * 2.45
        let capsuleWidth: CGFloat = 390
        let capsuleHeight: CGFloat = 66

        return SiriNotchMetrics(
            compactWidth: compactWidth,
            compactHeight: compactHeight,
            blobWidth: blobWidth,
            blobHeight: blobHeight,
            capsuleWidth: capsuleWidth,
            capsuleHeight: capsuleHeight,
            maximumCanvasWidth: 560,
            maximumCanvasHeight: 220
        )
    }
}

struct SiriWaveParameters {
    var phase: CGFloat
    var amplitude: CGFloat
    var horizontalOffset: CGFloat
    var colourPhase: CGFloat
}

struct SiriColourAnimationState {
    var gradientOffset: CGFloat
    var cyanPosition: CGFloat
    var magentaPosition: CGFloat
    var warmPosition: CGFloat
    var brightnessPulse: CGFloat
}

enum SiriPalette {
    static let siriBlack = Color(red: 0.02, green: 0.02, blue: 0.03)
    static let siriBlackRaised = Color(red: 0.045, green: 0.045, blue: 0.06)
    static let siriEdgeHighlight = Color.white.opacity(0.05)
    static let siriReflection = Color(red: 0.082, green: 0.082, blue: 0.102)

    static let siriCyan = Color(red: 0.10, green: 0.90, blue: 1.00)
    static let siriBlue = Color(red: 0.08, green: 0.42, blue: 1.00)
    static let siriViolet = Color(red: 0.42, green: 0.18, blue: 1.00)
    static let siriMagenta = Color(red: 1.00, green: 0.10, blue: 0.65)
    static let siriRed = Color(red: 1.00, green: 0.16, blue: 0.18)
    static let siriOrange = Color(red: 1.00, green: 0.48, blue: 0.08)
    static let siriYellow = Color(red: 1.00, green: 0.90, blue: 0.30)
    static let siriWhiteHot = Color(red: 0.92, green: 0.98, blue: 1.00)

    static let loaderBright = Color(red: 0.92, green: 0.97, blue: 1.00)
    static let loaderDim = Color(red: 0.48, green: 0.58, blue: 0.70)
}

final class SiriNotchController: ObservableObject {
    @Published private(set) var state: SiriNotchState = .hidden
    @Published var statusText = "Searching"

    private var transitionWorkItem: DispatchWorkItem?
    private var transitionGeneration = 0

    func activate() {
        cancelPendingTransition()
        state = .activating

        schedule(after: 0.56) { [weak self] in
            self?.beginListening()
        }
    }

    func beginListening() {
        cancelPendingTransition()
        state = .listening
    }

    func beginSearching(text: String = "Searching") {
        cancelPendingTransition()
        statusText = text
        state = .transitioningToSearch

        schedule(after: 0.43) { [weak self] in
            self?.state = .searching(text)
        }
    }

    func updateStatus(_ text: String) {
        statusText = text
        if case .searching = state {
            state = .searching(text)
        }
    }

    func dismiss() {
        cancelPendingTransition()
        guard state != .hidden else {
            return
        }

        state = .dismissing
        schedule(after: 0.43) { [weak self] in
            self?.state = .hidden
        }
    }

    func runDebugCycle() {
        cancelPendingTransition()
        state = .hidden

        let generation = transitionGeneration
        DispatchQueue.main.async { [weak self] in
            guard self?.transitionGeneration == generation else {
                return
            }
            self?.activate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { [weak self] in
            guard self?.transitionGeneration == generation else {
                return
            }
            self?.beginSearching(text: "Searching")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.45) { [weak self] in
            guard self?.transitionGeneration == generation else {
                return
            }
            self?.updateStatus("Looking into it")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.65) { [weak self] in
            guard self?.transitionGeneration == generation else {
                return
            }
            self?.dismiss()
        }
    }

    private func cancelPendingTransition() {
        transitionGeneration += 1
        transitionWorkItem?.cancel()
        transitionWorkItem = nil
    }

    private func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        let generation = transitionGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard self?.transitionGeneration == generation else {
                return
            }
            action()
        }
        transitionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}

struct SiriNotchAnimationView: View {
    @ObservedObject var controller: SiriNotchController
    let metrics: SiriNotchMetrics

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            let presentation = presentationValues(phase: phase)

            ZStack(alignment: .top) {
                if controller.state != .hidden {
                    SiriBlobShape(
                        expansion: presentation.expansion,
                        breathing: presentation.breathing,
                        asymmetry: presentation.asymmetry,
                        capsule: presentation.capsule,
                        metrics: metrics
                    )
                    .fill(
                        LinearGradient(
                            colors: [
                                SiriPalette.siriBlackRaised,
                                SiriPalette.siriBlack,
                                .black
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        LinearGradient(
                            colors: [
                                .clear,
                                SiriPalette.siriReflection.opacity(0.16),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .opacity(1 - presentation.capsule * 0.55)
                        .clipShape(
                            SiriBlobShape(
                                expansion: presentation.expansion,
                                breathing: presentation.breathing,
                                asymmetry: presentation.asymmetry,
                                capsule: presentation.capsule,
                                metrics: metrics
                            )
                        )
                    }
                    .overlay {
                        SiriLightWaveView(
                            metrics: metrics,
                            parameters: SiriWaveParameters(
                                phase: presentation.wavePhase,
                                amplitude: presentation.waveAmplitude,
                                horizontalOffset: presentation.waveOffset,
                                colourPhase: presentation.colourPhase
                            ),
                            intensity: presentation.waveIntensity
                        )
                        .opacity(presentation.waveOpacity)
                        .clipShape(
                            SiriBlobShape(
                                expansion: presentation.expansion,
                                breathing: presentation.breathing,
                                asymmetry: presentation.asymmetry,
                                capsule: presentation.capsule,
                                metrics: metrics
                            )
                        )
                    }
                    .overlay {
                        SiriBlobShape(
                            expansion: presentation.expansion,
                            breathing: presentation.breathing,
                            asymmetry: presentation.asymmetry,
                            capsule: presentation.capsule,
                            metrics: metrics
                        )
                        .stroke(SiriPalette.siriEdgeHighlight, lineWidth: 1)
                    }
                    .overlay(alignment: .top) {
                        SiriSearchCapsuleContent(
                            text: controller.statusText,
                            isVisible: presentation.contentOpacity > 0.01,
                            reduceMotion: reduceMotion
                        )
                        .frame(width: metrics.capsuleWidth, height: metrics.capsuleHeight)
                        .opacity(presentation.contentOpacity)
                        .offset(y: max(0, (metrics.capsuleHeight - 48) / 2))
                    }
                    .shadow(color: .black.opacity(0.30), radius: 18, y: 10)
                    .transition(.opacity)
                    .animation(animation(for: controller.state), value: controller.state)
                }
            }
            .frame(width: metrics.maximumCanvasWidth, height: metrics.maximumCanvasHeight, alignment: .top)
            .background(Color.clear)
        }
    }

    private func presentationValues(phase: TimeInterval) -> SiriPresentationValues {
        let state = controller.state
        let breathing = reduceMotion ? 0 : CGFloat(sin(phase * 3.2)) * 0.55
        let asymmetry = reduceMotion ? 0 : CGFloat(sin(phase * 2.1 + 0.7)) * 0.75
        let wavePhase = reduceMotion ? 0 : CGFloat(phase * 2.35)
        let colourPhase = reduceMotion ? 0 : CGFloat(phase * 1.1)

        switch state {
        case .hidden:
            return SiriPresentationValues.hidden
        case .activating:
            return SiriPresentationValues(
                expansion: 1,
                capsule: 0,
                breathing: 0,
                asymmetry: asymmetry * 0.45,
                waveOpacity: 1,
                waveIntensity: 1,
                contentOpacity: 0,
                wavePhase: wavePhase,
                waveAmplitude: 8,
                waveOffset: CGFloat(sin(phase * 2.0)) * 20,
                colourPhase: colourPhase
            )
        case .listening:
            return SiriPresentationValues(
                expansion: 1,
                capsule: 0,
                breathing: breathing,
                asymmetry: asymmetry,
                waveOpacity: 1,
                waveIntensity: 1,
                contentOpacity: 0,
                wavePhase: wavePhase,
                waveAmplitude: 10 + CGFloat(sin(phase * 2.7)) * 3,
                waveOffset: CGFloat(sin(phase * 1.7)) * 30,
                colourPhase: colourPhase
            )
        case .transitioningToSearch:
            return SiriPresentationValues(
                expansion: 1,
                capsule: 1,
                breathing: 0,
                asymmetry: 0,
                waveOpacity: 0.35,
                waveIntensity: 0.55,
                contentOpacity: 1,
                wavePhase: wavePhase,
                waveAmplitude: 4,
                waveOffset: 0,
                colourPhase: colourPhase
            )
        case .searching:
            return SiriPresentationValues(
                expansion: 1,
                capsule: 1,
                breathing: 0,
                asymmetry: 0,
                waveOpacity: 0.08,
                waveIntensity: 0.25,
                contentOpacity: 1,
                wavePhase: wavePhase,
                waveAmplitude: 2,
                waveOffset: 0,
                colourPhase: colourPhase
            )
        case .dismissing:
            return SiriPresentationValues.hidden
        }
    }

    private func animation(for state: SiriNotchState) -> Animation {
        if reduceMotion {
            return .easeInOut(duration: 0.18)
        }

        switch state {
        case .activating, .listening:
            return .interpolatingSpring(mass: 0.8, stiffness: 210, damping: 20, initialVelocity: 0)
        case .transitioningToSearch, .searching:
            return .easeInOut(duration: 0.44)
        case .dismissing, .hidden:
            return .easeInOut(duration: 0.38)
        }
    }
}

private struct SiriPresentationValues {
    var expansion: CGFloat
    var capsule: CGFloat
    var breathing: CGFloat
    var asymmetry: CGFloat
    var waveOpacity: CGFloat
    var waveIntensity: CGFloat
    var contentOpacity: CGFloat
    var wavePhase: CGFloat
    var waveAmplitude: CGFloat
    var waveOffset: CGFloat
    var colourPhase: CGFloat

    static let hidden = SiriPresentationValues(
        expansion: 0,
        capsule: 0,
        breathing: 0,
        asymmetry: 0,
        waveOpacity: 0,
        waveIntensity: 0,
        contentOpacity: 0,
        wavePhase: 0,
        waveAmplitude: 0,
        waveOffset: 0,
        colourPhase: 0
    )
}

struct SiriBlobShape: Shape {
    var expansion: CGFloat
    var breathing: CGFloat
    var asymmetry: CGFloat
    var capsule: CGFloat
    let metrics: SiriNotchMetrics

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get {
            AnimatablePair(expansion, AnimatablePair(breathing, AnimatablePair(asymmetry, capsule)))
        }
        set {
            expansion = newValue.first
            breathing = newValue.second.first
            asymmetry = newValue.second.second.first
            capsule = newValue.second.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let centerX = rect.midX
        let compactWidth = metrics.compactWidth
        let compactHeight = metrics.compactHeight

        let blobWidth = lerp(compactWidth, metrics.blobWidth + breathing * 5, expansion)
        let blobHeight = lerp(compactHeight, metrics.blobHeight + breathing * 5, expansion)
        let targetWidth = lerp(blobWidth, metrics.capsuleWidth, capsule)
        let targetHeight = lerp(blobHeight, metrics.capsuleHeight, capsule)

        let left = centerX - targetWidth / 2
        let right = centerX + targetWidth / 2
        let top: CGFloat = 0
        let bottom = targetHeight
        let topRadius = lerp(10, 18, capsule)
        let lowerRadius = lerp(targetWidth * 0.46, targetHeight / 2, capsule)
        let shoulderY = lerp(compactHeight * 0.72, targetHeight * 0.34, expansion)
        let lowerY = lerp(compactHeight, targetHeight * 0.74, expansion)
        let sideDrift = asymmetry * (1 - capsule) * 4

        var path = Path()
        path.move(to: CGPoint(x: left + topRadius, y: top))
        path.addLine(to: CGPoint(x: right - topRadius, y: top))
        path.addCurve(
            to: CGPoint(x: right, y: shoulderY),
            control1: CGPoint(x: right - topRadius * 0.20, y: top),
            control2: CGPoint(x: right + 2 + sideDrift, y: shoulderY * 0.35)
        )
        path.addCurve(
            to: CGPoint(x: centerX + lowerRadius * 0.72, y: bottom),
            control1: CGPoint(x: right + 8 + sideDrift, y: lowerY),
            control2: CGPoint(x: centerX + lowerRadius, y: bottom)
        )
        path.addCurve(
            to: CGPoint(x: centerX - lowerRadius * 0.72, y: bottom),
            control1: CGPoint(x: centerX + lowerRadius * 0.38, y: bottom + 2 * (1 - capsule)),
            control2: CGPoint(x: centerX - lowerRadius * 0.38, y: bottom + 2 * (1 - capsule))
        )
        path.addCurve(
            to: CGPoint(x: left, y: shoulderY),
            control1: CGPoint(x: centerX - lowerRadius, y: bottom),
            control2: CGPoint(x: left - 8 + sideDrift, y: lowerY)
        )
        path.addCurve(
            to: CGPoint(x: left + topRadius, y: top),
            control1: CGPoint(x: left - 2 + sideDrift, y: shoulderY * 0.35),
            control2: CGPoint(x: left + topRadius * 0.20, y: top)
        )
        path.closeSubpath()

        return path
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * min(max(t, 0), 1)
    }
}

struct SiriLightWaveView: View {
    let metrics: SiriNotchMetrics
    let parameters: SiriWaveParameters
    let intensity: CGFloat

    var body: some View {
        Canvas { context, size in
            let baseY = min(metrics.blobHeight * 0.63, size.height * 0.36)
            let centerX = size.width / 2 + parameters.horizontalOffset
            let waveWidth = metrics.blobWidth * 0.82
            let waveHeight = 18 + parameters.amplitude
            let colourState = colourState()
            let brightness = intensity * colourState.brightnessPulse
            let warmScale = min(1, max(0, (intensity - 0.28) / 0.72))

            context.addFilter(.blur(radius: 22))
            drawRibbon(
                context: context,
                center: CGPoint(x: centerX, y: baseY),
                width: waveWidth * 1.12,
                height: waveHeight * 2.1,
                phase: parameters.phase,
                stops: ambientStops(alpha: 0.38 * brightness, state: colourState, warmScale: warmScale)
            )

            context.addFilter(.blur(radius: 7))
            drawRibbon(
                context: context,
                center: CGPoint(x: centerX, y: baseY),
                width: waveWidth * 0.82,
                height: waveHeight * 0.72,
                phase: parameters.phase + parameters.colourPhase,
                stops: mainStops(alpha: 0.92 * brightness, state: colourState, warmScale: warmScale)
            )

            context.addFilter(.blur(radius: 3))
            drawCore(
                context: context,
                center: CGPoint(x: centerX + sin(parameters.phase * 0.9) * 18, y: baseY - waveHeight * 0.08),
                width: waveWidth * 0.38,
                height: max(3, waveHeight * 0.18),
                alpha: 0.76 * brightness
            )

            context.addFilter(.blur(radius: 12))
            drawBlob(context: context, center: CGPoint(x: centerX - 58 * sin(parameters.phase * 0.9), y: baseY + 10), color: SiriPalette.siriCyan.opacity(0.30 * brightness), radius: 26)
            drawBlob(context: context, center: CGPoint(x: centerX + 44 * cos(parameters.phase * 0.72), y: baseY - 6), color: SiriPalette.siriMagenta.opacity(0.22 * brightness * warmScale), radius: 30)
            drawBlob(context: context, center: CGPoint(x: centerX + 70 * sin(parameters.phase * 0.58 + 1.3), y: baseY + 5), color: SiriPalette.siriOrange.opacity(0.16 * brightness * warmScale), radius: 22)
            drawBlob(context: context, center: CGPoint(x: centerX + 8, y: baseY - waveHeight * 0.22), color: SiriPalette.siriWhiteHot.opacity(0.34 * brightness), radius: 9)
        }
        .drawingGroup()
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    private func colourState() -> SiriColourAnimationState {
        SiriColourAnimationState(
            gradientOffset: sin(parameters.colourPhase * 0.90) * 0.08,
            cyanPosition: 0.12 + sin(parameters.colourPhase * 1.18) * 0.05,
            magentaPosition: 0.58 + cos(parameters.colourPhase * 0.86) * 0.08,
            warmPosition: 0.84 + sin(parameters.colourPhase * 1.33 + 0.7) * 0.06,
            brightnessPulse: 0.98 + sin(parameters.phase * 1.7) * 0.08
        )
    }

    private func ambientStops(alpha: CGFloat, state: SiriColourAnimationState, warmScale: CGFloat) -> [Gradient.Stop] {
        [
            .init(color: SiriPalette.siriCyan.opacity(alpha * 0.55), location: clamped(0.00 + state.gradientOffset)),
            .init(color: SiriPalette.siriBlue.opacity(alpha * 0.70), location: clamped(0.24 + state.gradientOffset * 0.5)),
            .init(color: SiriPalette.siriViolet.opacity(alpha * 0.72), location: clamped(0.47 - state.gradientOffset)),
            .init(color: SiriPalette.siriMagenta.opacity(alpha * 0.58 * warmScale), location: clamped(0.70 + state.gradientOffset)),
            .init(color: SiriPalette.siriOrange.opacity(alpha * 0.36 * warmScale), location: 1.00)
        ]
    }

    private func mainStops(alpha: CGFloat, state: SiriColourAnimationState, warmScale: CGFloat) -> [Gradient.Stop] {
        [
            .init(color: SiriPalette.siriCyan.opacity(alpha), location: clamped(state.cyanPosition - 0.14)),
            .init(color: SiriPalette.siriWhiteHot.opacity(alpha * 0.90), location: clamped(state.cyanPosition)),
            .init(color: SiriPalette.siriBlue.opacity(alpha), location: clamped(0.28 - state.gradientOffset)),
            .init(color: SiriPalette.siriViolet.opacity(alpha * 0.95), location: clamped(0.44 + state.gradientOffset * 0.4)),
            .init(color: SiriPalette.siriMagenta.opacity(alpha * 0.88 * warmScale), location: clamped(state.magentaPosition)),
            .init(color: SiriPalette.siriRed.opacity(alpha * 0.68 * warmScale), location: clamped(0.76 + state.gradientOffset)),
            .init(color: SiriPalette.siriOrange.opacity(alpha * 0.55 * warmScale), location: clamped(state.warmPosition)),
            .init(color: SiriPalette.siriYellow.opacity(alpha * 0.42 * warmScale), location: 1.00)
        ]
    }

    private func drawRibbon(
        context: GraphicsContext,
        center: CGPoint,
        width: CGFloat,
        height: CGFloat,
        phase: CGFloat,
        stops: [Gradient.Stop]
    ) {
        var path = Path()
        let left = center.x - width / 2
        let right = center.x + width / 2
        let lift = sin(phase) * parameters.amplitude

        path.move(to: CGPoint(x: left, y: center.y))
        path.addCurve(
            to: CGPoint(x: center.x, y: center.y + lift),
            control1: CGPoint(x: left + width * 0.22, y: center.y - height),
            control2: CGPoint(x: center.x - width * 0.20, y: center.y + height)
        )
        path.addCurve(
            to: CGPoint(x: right, y: center.y),
            control1: CGPoint(x: center.x + width * 0.20, y: center.y - height),
            control2: CGPoint(x: right - width * 0.22, y: center.y + height)
        )

        context.stroke(
            path,
            with: .linearGradient(
                Gradient(stops: stops),
                startPoint: CGPoint(x: left, y: center.y),
                endPoint: CGPoint(x: right, y: center.y)
            ),
            style: StrokeStyle(lineWidth: height, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawCore(context: GraphicsContext, center: CGPoint, width: CGFloat, height: CGFloat, alpha: CGFloat) {
        var path = Path()
        path.move(to: CGPoint(x: center.x - width / 2, y: center.y))
        path.addCurve(
            to: CGPoint(x: center.x + width / 2, y: center.y),
            control1: CGPoint(x: center.x - width * 0.16, y: center.y - height * 1.2),
            control2: CGPoint(x: center.x + width * 0.18, y: center.y + height * 1.2)
        )
        context.stroke(
            path,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: SiriPalette.siriWhiteHot.opacity(alpha), location: 0.28),
                    .init(color: SiriPalette.siriCyan.opacity(alpha * 0.72), location: 0.50),
                    .init(color: SiriPalette.siriWhiteHot.opacity(alpha * 0.65), location: 0.70),
                    .init(color: .clear, location: 1.00)
                ]),
                startPoint: CGPoint(x: center.x - width / 2, y: center.y),
                endPoint: CGPoint(x: center.x + width / 2, y: center.y)
            ),
            style: StrokeStyle(lineWidth: height, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawBlob(context: GraphicsContext, center: CGPoint, color: Color, radius: CGFloat) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Ellipse().path(in: rect), with: .color(color))
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

struct SiriSearchCapsuleContent: View {
    let text: String
    let isVisible: Bool
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 14) {
            SiriDotLoader(reduceMotion: reduceMotion)
                .frame(width: 30, height: 30)

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))
                .frame(width: 250, alignment: .leading)
                .contentTransition(.opacity)
                .id(text)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 4)),
                    removal: .opacity.combined(with: .offset(y: -4))
                ))
        }
        .padding(.horizontal, 22)
        .opacity(isVisible ? 1 : 0)
    }
}

struct SiriDotLoader: View {
    let reduceMotion: Bool
    private let dotCount = 8

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 6.8

            ZStack {
                ForEach(0..<dotCount, id: \.self) { index in
                    let angle = (Double(index) / Double(dotCount)) * .pi * 2
                    let brightness = opacity(index: index, phase: phase)

                    Circle()
                        .fill(SiriPalette.loaderBright.opacity(brightness))
                        .frame(width: 5, height: 5)
                        .background(
                            Circle()
                                .fill(SiriPalette.loaderDim.opacity(max(0.18, brightness * 0.34)))
                                .frame(width: 5, height: 5)
                        )
                        .shadow(color: SiriPalette.loaderBright.opacity(brightness * 0.58), radius: 5)
                        .scaleEffect(0.72 + brightness * 0.45)
                        .offset(x: cos(angle) * 11, y: sin(angle) * 11)
                }
            }
        }
    }

    private func opacity(index: Int, phase: TimeInterval) -> Double {
        let position = (phase + Double(index)) .truncatingRemainder(dividingBy: Double(dotCount))
        let distance = min(position, Double(dotCount) - position)
        return max(0.22, 1.0 - distance * 0.38)
    }
}
