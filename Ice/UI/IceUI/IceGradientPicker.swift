//
//  IceGradientPicker.swift
//  Ice
//

import Combine
import SwiftUI

struct IceGradientPicker: View {
    typealias Mode = NSColorPanel.Mode

    @Binding var gradient: CustomGradient
    @State private var selectedStop: ColorStop?
    @State private var zOrderedStops: [ColorStop]
    @State private var window: NSWindow?
    @State private var cancellables = Set<AnyCancellable>()

    let supportsOpacity: Bool
    let allowsEmptySelections: Bool
    let mode: Mode?

    /// Creates a new gradient picker.
    ///
    /// - Parameters:
    ///   - gradient: A binding to a gradient.
    ///   - supportsOpacity: A Boolean value indicating whether the
    ///     picker should support opacity.
    ///   - allowsEmptySelections: A Boolean value indicating whether
    ///     the picker should allow empty gradient selections.
    ///   - mode: The mode that the color panel should take on when
    ///     picking a color for the gradient.
    init(
        gradient: Binding<CustomGradient>,
        mode: Mode? = nil,
        allowsEmptySelections: Bool = false,
        supportsOpacity: Bool
    ) {
        self._gradient = gradient
        self.zOrderedStops = gradient.wrappedValue.stops
        self.supportsOpacity = supportsOpacity
        self.allowsEmptySelections = allowsEmptySelections
        self.mode = mode
    }

    var body: some View {
        gradientView
            .clipShape(borderShape)
            .overlay {
                borderView
            }
            .shadow(radius: 1)
            .frame(width: 200, height: 18)
            .overlay {
                GeometryReader { geometry in
                    selectionReader(geometry: geometry)
                    insertionReader(geometry: geometry)
                    handles(geometry: geometry)
                }
            }
            .foregroundStyle(Color(white: 0.9))
            .frame(height: 24)
            .onChange(of: gradient) { _, newValue in
                gradientChanged(to: newValue)
            }
            .onWindowChange(update: $window)
    }

    @ViewBuilder
    private var borderShape: some Shape {
        RoundedRectangle(cornerRadius: 4, style: .circular)
    }

    @ViewBuilder
    private var gradientView: some View {
        if gradient.stops.isEmpty {
            Rectangle()
                .fill(.white.gradient.opacity(0.1))
                .blendMode(.softLight)
        } else {
            gradient.swiftUIView
        }
    }

    @ViewBuilder
    private var borderView: some View {
        borderShape
            .stroke()
            .overlay {
                centerTickMark
            }
            .foregroundStyle(.secondary.opacity(0.75))
            .blendMode(.softLight)
    }

    @ViewBuilder
    private var centerTickMark: some View {
        Rectangle()
            .frame(width: 1, height: 6)
    }

    @ViewBuilder
    private func selectionReader(geometry: GeometryProxy) -> some View {
        Color.clear
            .localEventMonitor(mask: .leftMouseDown) { event in
                guard
                    let window = event.window,
                    self.window === window
                else {
                    return event
                }
                let locationInWindow = event.locationInWindow
                guard window.contentLayoutRect.contains(locationInWindow) else {
                    return event
                }
                let globalFrame = geometry.frame(in: .global)
                let flippedLocation = CGPoint(x: locationInWindow.x, y: window.frame.height - locationInWindow.y)
                if !globalFrame.contains(flippedLocation) {
                    selectedStop = nil
                }
                return event
            }
    }

    @ViewBuilder
    private func insertionReader(geometry: GeometryProxy) -> some View {
        Color.clear
            .contentShape(borderShape)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onEnded { value in
                        guard abs(value.translation.width) <= 2 else {
                            return
                        }
                        let frame = geometry.frame(in: .local)
                        guard frame.contains(value.location) else {
                            return
                        }
                        let x = value.location.x
                        let width = frame.width - 10
                        let location = (x / width) - (6 / width)
                        insertStop(at: location, select: true)
                    }
            )
    }

    @ViewBuilder
    private func handles(geometry: GeometryProxy) -> some View {
        ForEach(gradient.stops.indices, id: \.self) { index in
            CustomGradientPickerHandle(
                gradient: $gradient,
                selectedStop: $selectedStop,
                zOrderedStops: $zOrderedStops,
                cancellables: $cancellables,
                index: index,
                supportsOpacity: supportsOpacity,
                mode: mode,
                geometry: geometry
            )
        }
    }

    /// Inserts a new stop with the appropriate color at the given location
    /// in the gradient.
    private func insertStop(at location: CGFloat, select: Bool) {
        var location = location.clamped(to: 0...1)
        if (0.48...0.52).contains(location) {
            location = 0.5
        }
        let newStop: ColorStop = if
            !gradient.stops.isEmpty,
            let color = gradient.color(at: location)
        {
            ColorStop(color: color, location: location)
        } else {
            ColorStop(color: .black, location: location)
        }
        gradient.stops.append(newStop)
        if select {
            DispatchQueue.main.async {
                self.selectedStop = newStop
            }
        }
    }

    private func gradientChanged(to gradient: CustomGradient) {
        if allowsEmptySelections {
            return
        }
        if gradient.stops.isEmpty {
            self.gradient = .defaultMenuBarTint
        } else if gradient.stops.count == 1 {
            var gradient = gradient
            if gradient.stops[0].location >= 0.5 {
                gradient.stops[0].location = 1
                let stop = ColorStop(color: .white, location: 0)
                gradient.stops.append(stop)
            } else {
                gradient.stops[0].location = 0
                let stop = ColorStop(color: .black, location: 1)
                gradient.stops.append(stop)
            }
            self.gradient = gradient
        }
    }
}

private struct CustomGradientPickerHandle: View {
    @Binding var gradient: CustomGradient
    @Binding var selectedStop: ColorStop?
    @Binding var zOrderedStops: [ColorStop]
    @Binding var cancellables: Set<AnyCancellable>
    @State private var canActivate = true

    let index: Int
    let supportsOpacity: Bool
    let mode: NSColorPanel.Mode?
    let geometry: GeometryProxy
    let width: CGFloat = 8
    let height: CGFloat = 22

    private var stop: ColorStop? {
        get {
            guard gradient.stops.indices.contains(index) else {
                return nil
            }
            return gradient.stops[index]
        }
        nonmutating set {
            guard gradient.stops.indices.contains(index) else {
                return
            }
            if let newValue {
                gradient.stops[index] = newValue
            } else {
                gradient.stops.remove(at: index)
            }
        }
    }

    private var borderShape: some InsettableShape {
        Capsule(style: .circular)
    }

    var body: some View {
        if let stop {
            handleView(cgColor: stop.color)
                .contentShape([.interaction, .focusEffect], borderShape)
                .frame(width: width, height: height)
                .overlay {
                    selectionIndicator(isSelected: selectedStop == stop)
                }
                .offset(
                    x: (geometry.size.width - width) * stop.location,
                    y: (geometry.size.height - height) / 2
                )
                .shadow(radius: 1)
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            update(with: value.location.x, shouldSnap: abs(value.velocity.width) <= 75)
                        }
                        .onEnded { value in
                            update(with: value.location.x, shouldSnap: true)
                        }
                )
                .onTapGesture(count: 2) {
                    if gradient.stops.count == 1 {
                        gradient.stops[0].location = 0.5
                    } else {
                        let last = CGFloat(gradient.stops.count - 1)
                        gradient.stops = gradient.stops.lazy
                            .sorted { $0.location < $1.location }
                            .enumerated()
                            .map { n, stop in
                                ColorStop(color: stop.color, location: CGFloat(n) / last)
                            }
                    }
                }
                .onTapGesture {
                    selectedStop = stop
                }
                .zIndex(Double(zOrderedStops.firstIndex(of: stop) ?? 0))
                .onChange(of: selectedStop == stop) {
                    deactivate()
                    DispatchQueue.main.async {
                        if self.selectedStop == stop {
                            activate()
                        }
                    }
                }
                .onKeyDown(key: .escape) {
                    selectedStop = nil
                }
                .onKeyDown(key: .delete) {
                    deleteSelectedStop()
                }
                .onKeyPress(.space) {
                    selectedStop = stop
                    return .handled
                }
        }
    }

    @ViewBuilder
    private func handleView(cgColor: CGColor) -> some View {
        borderShape
            .fill(Color(cgColor: cgColor))
            .strokeBorder(.secondary.opacity(0.75))
    }

    @ViewBuilder
    private func selectionIndicator(isSelected: Bool) -> some View {
        if isSelected {
            borderShape
                .inset(by: -1.5)
                .stroke(.primary, lineWidth: 1.5)
        }
    }

    private func update(with location: CGFloat, shouldSnap: Bool) {
        guard var stop else {
            return
        }
        let newLocation = (location - (width / 2)) / (geometry.size.width - width)
        if let index = zOrderedStops.firstIndex(of: stop) {
            zOrderedStops.remove(at: index)
        }
        let isSelected = selectedStop == stop
        if
            shouldSnap,
            (0.48...0.52).contains(newLocation)
        {
            stop.location = 0.5
        } else {
            stop.location = min(1, max(0, newLocation))
        }
        self.stop = stop
        if isSelected {
            selectedStop = stop
        }
        zOrderedStops.append(stop)
    }

    private func activate() {
        guard canActivate else {
            return
        }

        deactivate()

        NSColorPanel.shared.showsAlpha = supportsOpacity
        if let mode {
            NSColorPanel.shared.mode = mode
        }
        if let color = stop.flatMap({ NSColor(cgColor: $0.color) }) {
            NSColorPanel.shared.color = color
        }
        NSColorPanel.shared.orderFrontRegardless()

        if let index = stop.flatMap(zOrderedStops.firstIndex) {
            zOrderedStops.append(zOrderedStops.remove(at: index))
        }

        var c = Set<AnyCancellable>()

        NSColorPanel.shared.publisher(for: \.color)
            .receive(on: DispatchQueue.main)
            .dropFirst()
            .sink { color in
                canActivate = false
                defer {
                    canActivate = true
                }
                if stop?.color != color.cgColor {
                    stop?.color = color.cgColor
                    selectedStop = stop
                }
            }
            .store(in: &c)

        NSColorPanel.shared.publisher(for: \.isVisible)
            .sink { isVisible in
                if isVisible {
                    if NSColorPanel.shared.frame.origin == .zero {
                        NSColorPanel.shared.center()
                    }
                } else {
                    selectedStop = nil
                }
            }
            .store(in: &c)

        cancellables = c
    }

    private func deactivate() {
        for cancellable in cancellables {
            cancellable.cancel()
        }
        cancellables.removeAll()
        NSColorPanel.shared.close()
    }

    private func deleteSelectedStop() {
        deactivate()
        guard
            let stop = selectedStop.take(),
            let index = gradient.stops.firstIndex(of: stop)
        else {
            return
        }
        gradient.stops.remove(at: index)
    }
}
