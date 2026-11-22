import SwiftUI

/// A small looping picture of a transition. The spaces are drawn as outlines, each with one, two or three
/// dots so you can tell them apart, and a blue frame is the display. The loop goes from space 1 to 2 to 3,
/// and back to 2 and 1.
///
/// Each picture uses the math of the real transition (`TransitionMath`), with the same spring and the same
/// values, so it shows what the transition really does.
///
/// - Default, Lightweight and Instant: the real display is fixed and the spaces move. Here the spaces are fixed and
///   the display moves, so a transition that makes the spaces smaller makes the frame larger.
/// - Hexagon: the display is fixed here too, as the spaces turn in front of it.
/// - Magnetic: the display is fixed, because each space has its own size that depends on where it is.
/// - Stack: the display is fixed on the pile, and a second pile beside it is the spaces that wait.
struct TransitionPreview: View {
    let style: TransitionStyle
    /// The speed setting. It changes the custom transitions only.
    let speed: Double
    /// The setting "Dock and menu bar move with the space". It changes the custom transitions only.
    var dockMovesWithSpace = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Every transition gets the same time slot for one move and its pause, so all previews start
    /// their moves together and the faster one visibly arrives first.
    private static let slot: Double = 1.9
    private static let stops: [Double] = [0, 1, 2, 1, 0]

    /// As wide as the widest drawing. Every drawing is in the middle of this area, so the previews are
    /// in line with each other: the middle space of each one is on the same vertical line.
    static let size = CGSize(width: 188, height: 56)

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let position = reduceMotion ? 0 : position(at: time)
                switch style {
                case .system, .lightweight, .instant: drawSlide(in: &context, size: size, position: position)
                case .hexagon: drawHexagon(in: &context, size: size, position: position)
                case .stack: drawStack(in: &context, size: size, position: position)
                case .magnetic: drawMagnetic(in: &context, size: size, position: position)
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }

    // MARK: - Timing

    /// The swipe that every preview replays. A real transition has no fixed timing: the first part is under
    /// the fingers. These numbers are a typical swipe from the app's log of real ones: the fingers move for
    /// 0.12 s at a constant speed and lift at 30% of the way.
    private static let dragDuration: Double = 0.12
    private static let releaseProgress: Double = 0.3

    /// The spring response of the macOS transition after the release. This one number is an estimate:
    /// the Dock does not publish it and it was not measured.
    private static let systemResponseEstimate: CGFloat = 0.45

    /// Where the display is at a time: 0 is space 1, 1 is space 2, 2 is space 3.
    private func position(at time: Double) -> Double {
        let legs = Self.stops.count - 1
        let cycle = time.truncatingRemainder(dividingBy: Self.slot * Double(legs))
        let leg = min(Int(cycle / Self.slot), legs - 1)
        let elapsed = cycle - Double(leg) * Self.slot
        let from = Self.stops[leg]
        let to = Self.stops[leg + 1]
        return from + (to - from) * travelled(after: elapsed)
    }

    /// The part of one move that is done, 0 to 1, a time after the fingers start.
    private func travelled(after elapsed: Double) -> Double {
        let fingerVelocity = Self.releaseProgress / Self.dragDuration
        if style == .instant {
            // The switch happens at the first movement that has a direction, and is whole at once.
            let firstMovement = Double(Config.directionSlop / Config.travelPerTrackpadWidth) / fingerVelocity
            return elapsed >= firstMovement ? 1 : 0
        }
        // The fingers always make the same movement, at a sensitivity of 1. The sensitivity setting is not
        // in the preview: it changes how far the fingers take the screen, not how the transition looks, and
        // only the speed setting may change the pace of the preview.
        let dragVelocity = fingerVelocity
        let released = Self.releaseProgress

        // Under the fingers: the screen follows them directly.
        guard elapsed > Self.dragDuration else {
            return min(dragVelocity * max(elapsed, 0), 1)
        }
        guard released < 1 else { return 1 }

        // After the release: the same spring as the real transition, with the same start values.
        // The spring works on the distance to the resting position.
        var distance = CGFloat(released - 1)
        var velocity = min(CGFloat(dragVelocity), TransitionMath.maxReleaseVelocity)
        let response: CGFloat
        let springSpeed: CGFloat
        switch style {
        case .system:
            response = Self.systemResponseEstimate
            springSpeed = 1
        case .lightweight, .magnetic, .hexagon, .stack, .instant:
            response = Config.springResponse
            springSpeed = CGFloat(speed)
        }
        TransitionMath.stepSpring(
            progress: &distance, velocity: &velocity, delta: CGFloat(elapsed - Self.dragDuration),
            response: response, speed: springSpeed
        )
        if TransitionMath.isSettled(progress: distance, velocity: velocity) {
            return 1
        }
        return Double(1 + distance)
    }

    // MARK: - Shared drawing

    // The spaces have the shape of the display, and the same size in every preview.
    private static let spaceWidth: CGFloat = 60
    private static let spaceHeight: CGFloat = 60 / 1.52
    /// The corner radius of the display frame and of every space. The spaces are round in all previews,
    /// also for a transition with square corners and when the "Rounded corners" setting is off: the
    /// previews are there to show the motion, and they read better as one set.
    /// Larger than life: at this size the real radius is about 1 point.
    private static let cornerRadius: CGFloat = 5

    private static let skeleton = Color.primary

    /// True when the Dock is drawn in each space and moves with it. False when it is drawn on the display:
    /// in the macOS transition the Dock stays there and only the desktops move below it.
    private var dockInSpace: Bool {
        style.isDrawn && dockMovesWithSpace
    }

    /// A bar at the bottom centre of a screen. Its size follows the screen, so it grows with the display.
    private static func dock(in screen: CGRect) -> Path {
        let width = screen.width * 0.4
        let height = screen.height * 0.1
        let rect = CGRect(
            x: screen.midX - width / 2, y: screen.maxY - height - screen.height * 0.075,
            width: width, height: height
        )
        return Path(roundedRect: rect, cornerRadius: height * 0.4, style: .continuous)
    }

    /// A small pill at the top centre of the display.
    private static func island(in screen: CGRect) -> Path {
        let width = screen.width * 0.15
        let height = screen.height * 0.085
        let rect = CGRect(
            x: screen.midX - width / 2, y: screen.minY + screen.height * 0.07,
            width: width, height: height
        )
        return Path(roundedRect: rect, cornerRadius: height / 2, style: .circular)
    }

    /// One dot for space 1, two for space 2, three for space 3, in the middle of the screen.
    private static func dots(for index: Int, in screen: CGRect) -> Path {
        let count = index + 1
        let radius = screen.width * 0.03
        let step = screen.width * 0.11
        var path = Path()
        for dot in 0..<count {
            let x = screen.midX + (CGFloat(dot) - CGFloat(count - 1) / 2) * step
            path.addEllipse(in: CGRect(x: x - radius, y: screen.midY - radius, width: radius * 2, height: radius * 2))
        }
        return path
    }

    /// The blue display frame with its island, and its Dock when the Dock does not move with the spaces.
    private func drawDisplay(in context: inout GraphicsContext, frame: CGRect, scale: CGFloat = 1) {
        let path = Path(roundedRect: frame.insetBy(dx: 0.75, dy: 0.75), cornerRadius: Self.cornerRadius * scale, style: .continuous)
        context.fill(path, with: .color(.accentColor.opacity(0.22)))
        context.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
        // The island is part of the display in every transition.
        context.fill(Self.island(in: frame), with: .color(.accentColor))
        if !dockInSpace {
            context.fill(Self.dock(in: frame), with: .color(.accentColor.opacity(0.85)))
        }
    }

    // MARK: - Default and Lightweight

    private func drawSlide(in context: inout GraphicsContext, size: CGSize, position: Double) {
        let isLightweight = style == .lightweight
        // Larger than life: at this size the real gap of Lightweight is under 1 point.
        let gap: CGFloat = isLightweight ? 4 : 3
        let spaceRadius = Self.cornerRadius

        let total = Self.spaceWidth * 3 + gap * 2
        let originX = (size.width - total) / 2
        let centreY = size.height / 2

        for index in 0..<3 {
            let rect = CGRect(
                x: originX + CGFloat(index) * (Self.spaceWidth + gap), y: centreY - Self.spaceHeight / 2,
                width: Self.spaceWidth, height: Self.spaceHeight
            )
            let path = Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: spaceRadius, style: .continuous)
            // Lightweight makes a screen darker the further it is from the middle of the display.
            // The macOS transition does not.
            let offCentre = abs(CGFloat(index) - CGFloat(position))
            let dim = isLightweight ? TransitionMath.dim(offCentre: offCentre) : 0
            context.fill(path, with: .color(Self.skeleton.opacity(0.2 * (1 - dim))))
            context.stroke(path, with: .color(Self.skeleton.opacity(0.3)), lineWidth: 1)
            context.fill(Self.dots(for: index, in: rect), with: .color(Self.skeleton.opacity(0.35)))
            if dockInSpace {
                context.fill(Self.dock(in: rect), with: .color(Self.skeleton.opacity(0.3)))
            }
        }

        // In Lightweight the screens get smaller by `TransitionMath.scale`. Seen from a screen,
        // the display gets larger by the same factor.
        let scale = isLightweight ? 1 / TransitionMath.scale(progress: CGFloat(position)) : 1
        let width = Self.spaceWidth * scale
        let height = Self.spaceHeight * scale
        let centreX = originX + Self.spaceWidth / 2 + CGFloat(position) * (Self.spaceWidth + gap)
        let display = CGRect(x: centreX - width / 2, y: centreY - height / 2, width: width, height: height)
        drawDisplay(in: &context, frame: display, scale: scale)
    }

    // MARK: - Hexagon

    private func drawHexagon(in context: inout GraphicsContext, size: CGSize, position: Double) {
        let width = Self.spaceWidth
        let halfHeight = Self.spaceHeight / width / 2
        let progress = CGFloat(position)

        let centre = CGPoint(x: size.width / 2, y: size.height / 2)

        /// A point of a side, on the canvas.
        func point(_ x: CGFloat, _ y: CGFloat, offset: CGFloat) -> CGPoint {
            let projected = TransitionMath.hexProject(x: x, y: y, offset: offset, progress: progress)
            return CGPoint(x: centre.x + projected.x * width, y: centre.y + projected.y * width)
        }

        /// A rectangle on a side, given from the centre of the side in screen widths.
        func quad(_ rect: CGRect, offset: CGFloat) -> Path {
            var path = Path()
            path.move(to: point(rect.minX, rect.minY, offset: offset))
            path.addLine(to: point(rect.maxX, rect.minY, offset: offset))
            path.addLine(to: point(rect.maxX, rect.maxY, offset: offset))
            path.addLine(to: point(rect.minX, rect.maxY, offset: offset))
            path.closeSubpath()
            return path
        }

        /// The same rectangle with round corners. A turned arc is not an arc, so each corner is a few short lines.
        func roundedQuad(_ rect: CGRect, radius: CGFloat, offset: CGFloat) -> Path {
            guard radius > 0 else { return quad(rect, offset: offset) }
            // The centre of each corner and the angle where its arc starts, clockwise from the top right.
            let corners: [(centre: CGPoint, start: CGFloat)] = [
                (CGPoint(x: rect.maxX - radius, y: rect.minY + radius), -.pi / 2),
                (CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), 0),
                (CGPoint(x: rect.minX + radius, y: rect.maxY - radius), .pi / 2),
                (CGPoint(x: rect.minX + radius, y: rect.minY + radius), .pi),
            ]
            let steps = 6
            var path = Path()
            for (index, corner) in corners.enumerated() {
                for step in 0...steps {
                    let angle = corner.start + .pi / 2 * CGFloat(step) / CGFloat(steps)
                    let place = point(
                        corner.centre.x + cos(angle) * radius, corner.centre.y + sin(angle) * radius,
                        offset: offset
                    )
                    if index == 0, step == 0 {
                        path.move(to: place)
                    } else {
                        path.addLine(to: place)
                    }
                }
            }
            path.closeSubpath()
            return path
        }

        // In screen widths, as the sides are.
        let faceRadius = Self.cornerRadius / width

        // The sides that face the eye, the furthest first.
        let sides: [(index: Int, offset: CGFloat)] = (0..<3)
            .map { (index: $0, offset: CGFloat($0) - progress) }
            .filter { abs($0.offset) * TransitionMath.hexFaceAngle < .pi / 2 }
            .sorted { abs($0.offset) > abs($1.offset) }

        for side in sides {
            let face = roundedQuad(
                CGRect(x: -0.5, y: -halfHeight, width: 1, height: halfHeight * 2), radius: faceRadius, offset: side.offset
            )
            let dim = TransitionMath.hexDim(offset: side.offset)
            context.fill(face, with: .color(Self.skeleton.opacity(0.2 * (1 - dim))))
            context.stroke(face, with: .color(Self.skeleton.opacity(0.3)), style: StrokeStyle(lineWidth: 1, lineJoin: .round))

            // The dots, each at its own place and size on the turned side.
            let count = side.index + 1
            var dots = Path()
            for dot in 0..<count {
                let x = (CGFloat(dot) - CGFloat(count - 1) / 2) * 0.11
                let projected = TransitionMath.hexProject(x: x, y: 0, offset: side.offset, progress: progress)
                let radius = 0.03 * width * projected.scale
                // A circle on a turned side is narrower.
                let squeeze = max(cos(side.offset * TransitionMath.hexFaceAngle), 0.2)
                dots.addEllipse(in: CGRect(
                    x: centre.x + projected.x * width - radius * squeeze, y: centre.y + projected.y * width - radius,
                    width: radius * 2 * squeeze, height: radius * 2
                ))
            }
            context.fill(dots, with: .color(Self.skeleton.opacity(0.35)))

            if dockInSpace {
                let dock = quad(
                    CGRect(x: -0.2, y: halfHeight - halfHeight * 2 * 0.175, width: 0.4, height: halfHeight * 2 * 0.1),
                    offset: side.offset
                )
                context.fill(dock, with: .color(Self.skeleton.opacity(0.3)))
            }
        }

        // The display does not move. A side fills it when it is at the front.
        let display = CGRect(
            x: centre.x - width / 2, y: centre.y - Self.spaceHeight / 2,
            width: width, height: Self.spaceHeight
        )
        drawDisplay(in: &context, frame: display)
    }

    // MARK: - Magnetic

    private func drawMagnetic(in context: inout GraphicsContext, size: CGSize, position: Double) {
        let width = Self.spaceWidth
        let radius = Self.cornerRadius
        // Larger than life, as in Lightweight: at this size the real gap is under 1 point.
        let gap: CGFloat = 4 / width
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)

        for index in 0..<3 {
            let offset = CGFloat(index) - CGFloat(position)
            // A space that is more than a step away is past the area of the picture. It fades in, so it
            // does not appear from nothing at the edge.
            let visibility = min(max((1.6 - abs(offset)) / 0.4, 0), 1)
            guard visibility > 0 else { continue }

            let scale = TransitionMath.magneticScale(offset: offset)
            let x = centre.x + TransitionMath.magneticPosition(offset: offset, gap: gap) * width
            let rect = CGRect(
                x: x - width * scale / 2, y: centre.y - Self.spaceHeight * scale / 2,
                width: width * scale, height: Self.spaceHeight * scale
            )
            let path = Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius * scale, style: .continuous)
            let dim = TransitionMath.dim(offCentre: abs(offset))
            context.fill(path, with: .color(Self.skeleton.opacity(0.2 * (1 - dim) * visibility)))
            context.stroke(path, with: .color(Self.skeleton.opacity(0.3 * visibility)), lineWidth: 1)
            context.fill(Self.dots(for: index, in: rect), with: .color(Self.skeleton.opacity(0.35 * visibility)))
            if dockInSpace {
                context.fill(Self.dock(in: rect), with: .color(Self.skeleton.opacity(0.3 * visibility)))
            }
        }

        // The display does not move. A space fills it when it is in the middle.
        let display = CGRect(
            x: centre.x - width / 2, y: centre.y - Self.spaceHeight / 2,
            width: width, height: Self.spaceHeight
        )
        drawDisplay(in: &context, frame: display)
    }

    // MARK: - Stack

    private func drawStack(in context: inout GraphicsContext, size: CGSize, position: Double) {
        let width = Self.spaceWidth
        let height = Self.spaceHeight
        let radius = Self.cornerRadius
        // Each lower card of a pile shows this much of itself, so the pile reads as a pile. In the real
        // transition the pile is on the display and its cards are exactly on top of each other.
        let fan: CGFloat = 5
        let gap: CGFloat = 8

        // Left: the pile on the display. Right: the pile of the spaces that wait, off the display.
        let total = fan * 2 + width + gap + width + fan
        let pileX = (size.width - total) / 2 + fan * 2
        let waitingX = pileX + width + gap
        let top = size.height / 2 - height / 2

        func drawCard(_ index: Int, offset: CGFloat) {
            let x: CGFloat
            if offset <= 0 {
                x = pileX - fan * min(-offset, 2)
            } else if offset <= 1 {
                x = pileX + offset * (waitingX - pileX)
            } else {
                x = waitingX + fan * (offset - 1)
            }
            let scale = TransitionMath.stackScale(offset: offset)
            let rect = CGRect(
                x: x + width * (1 - scale) / 2, y: top + height * (1 - scale) / 2,
                width: width * scale, height: height * scale
            )
            let path = Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius * scale, style: .continuous)
            // A card hides what is below it. The outlines are see-through, so first remove what is there.
            context.blendMode = .clear
            context.fill(Path(roundedRect: rect, cornerRadius: radius * scale, style: .continuous), with: .color(.black))
            context.blendMode = .normal

            let dim = TransitionMath.stackDim(offset: offset)
            context.fill(path, with: .color(Self.skeleton.opacity(0.2 * (1 - dim))))
            context.stroke(path, with: .color(Self.skeleton.opacity(0.3)), lineWidth: 1)
            context.fill(Self.dots(for: index, in: rect), with: .color(Self.skeleton.opacity(0.35)))
            if dockInSpace {
                context.fill(Self.dock(in: rect), with: .color(Self.skeleton.opacity(0.3)))
            }
        }

        let cards = (0..<3).map { (index: $0, offset: CGFloat($0) - CGFloat(position)) }
        // The waiting pile from its lowest card up, then the pile on the display from its lowest card up,
        // then the card that is on its way: it is above both.
        for card in cards.filter({ $0.offset > 1 }).reversed() { drawCard(card.index, offset: card.offset) }
        for card in cards.filter({ $0.offset <= 0 }) { drawCard(card.index, offset: card.offset) }
        for card in cards.filter({ $0.offset > 0 && $0.offset <= 1 }) { drawCard(card.index, offset: card.offset) }

        // The display does not move: it is where the pile is.
        drawDisplay(in: &context, frame: CGRect(x: pileX, y: top, width: width, height: height))
    }
}
