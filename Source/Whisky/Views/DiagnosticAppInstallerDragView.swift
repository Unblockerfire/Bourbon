//
//  DiagnosticAppInstallerDragView.swift
//  Whisky
//

import AppKit
import SwiftUI

struct DiagnosticDragTarget: View {
    let onAccepted: () -> Void
    @State private var dragOffset = CGSize.zero
    @State private var isOverApplications = false

    private let sourcePoint = CGPoint(x: 115, y: 90)
    private let destinationPoint = CGPoint(x: 505, y: 90)

    var body: some View {
        ZStack {
            destinationIcon
                .position(destinationPoint)

            Image(systemName: "arrow.right")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
                .position(x: 310, y: 74)

            sourceIcon
                .position(sourcePoint)
                .offset(dragOffset)
                .gesture(dragGesture)
                .accessibilityAction(named: "Move to Applications") {
                    onAccepted()
                }
        }
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 24))
    }

    private var sourceIcon: some View {
        VStack(spacing: 10) {
            DiagnosticAppIcon(image: NSApp.applicationIconImage, size: 86)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
            Text("Bourbon Diagnostic.app")
                .font(.caption.weight(.medium))
        }
        .frame(width: 180)
        .contentShape(Rectangle())
    }

    private var destinationIcon: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.system(size: 82))
                .foregroundStyle(isOverApplications ? .orange : .blue)
                .scaleEffect(isOverApplications ? 1.08 : 1)
            Text("Applications")
                .font(.caption.weight(.medium))
        }
        .frame(width: 170)
        .animation(.easeOut(duration: 0.15), value: isOverApplications)
    }

    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .local)
            .onChanged { value in
                dragOffset = value.translation
                isOverApplications = distanceToDestination(value.translation) < 92
            }
            .onEnded { value in
                let accepted = distanceToDestination(value.translation) < 92
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    dragOffset = .zero
                    isOverApplications = false
                }
                if accepted { onAccepted() }
            }
    }

    private func distanceToDestination(_ translation: CGSize) -> CGFloat {
        let horizontal = sourcePoint.x + translation.width - destinationPoint.x
        let vertical = sourcePoint.y + translation.height - destinationPoint.y
        return hypot(horizontal, vertical)
    }
}

struct DiagnosticAppIcon: View {
    let image: NSImage
    let size: CGFloat

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}
