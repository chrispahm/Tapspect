import SwiftUI
import UIKit

// MARK: - Scroll View Finder

/// Walks the UIKit view hierarchy to find UIScrollViews that SwiftUI created.
/// Attaches our drawer pan gesture and sets up failure requirements so that
/// the scroll views only scroll when we decide the drawer pan should not begin.
final class DrawerPanController {
    weak var panGesture: UIPanGestureRecognizer?
    private var wiredScrollViews = NSHashTable<UIScrollView>.weakObjects()

    func wireScrollViews(under rootView: UIView) {
        guard let pan = panGesture else { return }
        let scrollViews = Self.findVerticalScrollViews(in: rootView, exclude: pan)
        for sv in scrollViews {
            guard !wiredScrollViews.contains(sv) else { continue }
            sv.panGestureRecognizer.require(toFail: pan)
            wiredScrollViews.add(sv)
        }
    }

    /// Disable top-bounce on all wired scroll views so the rubber-band effect
    /// doesn't appear when the drawer gesture should take over.
    func updateBounce(allowBounce: Bool) {
        for sv in wiredScrollViews.allObjects {
            sv.bounces = allowBounce
        }
    }

    /// Tag used by SwiftUI vertical ScrollViews that should be coordinated.
    static let verticalScrollTag = "drawer-content-scroll"

    private static func findVerticalScrollViews(
        in view: UIView,
        exclude pan: UIPanGestureRecognizer
    ) -> [UIScrollView] {
        var result: [UIScrollView] = []
        for sub in view.subviews {
            if let sv = sub as? UIScrollView,
               sv.panGestureRecognizer !== pan {
                // Only wire scroll views explicitly tagged by our SwiftUI code
                if sv.accessibilityIdentifier == verticalScrollTag {
                    result.append(sv)
                }
            }
            result.append(contentsOf: findVerticalScrollViews(in: sub, exclude: pan))
        }
        return result
    }
}

// MARK: - Drawer Gesture Coordinator

/// A zero-size UIViewRepresentable that attaches a UIPanGestureRecognizer to
/// the drawer's nearest UIKit hosting ancestor. It uses `require(toFail:)` on
/// every content UIScrollView so that scroll views only scroll when our drawer
/// pan decides not to begin.
struct DrawerGestureCoordinator: UIViewRepresentable {
    let drawerAtFull: Bool
    let contentAtTop: Bool
    let onDragChanged: (_ translation: CGFloat, _ velocity: CGFloat) -> Void
    let onDragEnded: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false // don't intercept touches
        // We attach the gesture in updateUIView once the view is in the hierarchy
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coord = context.coordinator
        coord.drawerAtFull = drawerAtFull
        coord.contentAtTop = contentAtTop
        coord.onDragChanged = onDragChanged
        coord.onDragEnded = onDragEnded

        // Disable bounce when at full and content at top — this prevents
        // the rubber-band effect when the user drags down to move the drawer.
        coord.panController.updateBounce(allowBounce: !drawerAtFull || !contentAtTop)

        // Once in the hierarchy, attach the pan gesture to the hosting view
        DispatchQueue.main.async {
            coord.attachIfNeeded(markerView: uiView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var drawerAtFull: Bool
        var contentAtTop: Bool
        var onDragChanged: (_ translation: CGFloat, _ velocity: CGFloat) -> Void
        var onDragEnded: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

        private var panGesture: UIPanGestureRecognizer?
        private weak var hostView: UIView? // the view we attached the pan to
        let panController = DrawerPanController()
        private var isAttached = false

        init(parent: DrawerGestureCoordinator) {
            self.drawerAtFull = parent.drawerAtFull
            self.contentAtTop = parent.contentAtTop
            self.onDragChanged = parent.onDragChanged
            self.onDragEnded = parent.onDragEnded
        }

        /// Walk up from the marker view to find the hosting view of the drawer,
        /// attach our pan gesture there, and wire scroll views.
        func attachIfNeeded(markerView: UIView) {
            guard !isAttached else {
                // Re-wire scroll views in case new ones appeared (tab switch)
                if let host = hostView {
                    panController.wireScrollViews(under: host)
                }
                return
            }

            // Find the nearest hosting view ancestor that is large enough to be
            // the drawer container. Walk up until we find a UIKit hosting view
            // class (private, so match by name prefix).
            guard let host = findHostingView(from: markerView) else { return }

            let pan = UIPanGestureRecognizer(
                target: self,
                action: #selector(handlePan(_:))
            )
            pan.delegate = self
            host.addGestureRecognizer(pan)

            self.panGesture = pan
            self.hostView = host
            panController.panGesture = pan
            panController.wireScrollViews(under: host)
            isAttached = true
        }

        private func findHostingView(from view: UIView) -> UIView? {
            // Walk up to the top of the drawer's view hierarchy
            // We want a view large enough to be the drawer
            var best: UIView? = nil
            var current: UIView? = view.superview
            while let v = current {
                let name = String(describing: type(of: v))
                if name.contains("UIHostingView") || name.contains("HostingView") {
                    best = v
                }
                current = v.superview
            }
            return best ?? view.superview
        }

        // MARK: Gesture delegate

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let vel = pan.velocity(in: pan.view)

            // Horizontal → let tab bar handle it
            if abs(vel.x) > abs(vel.y) * 1.2 { return false }

            // Not at full → always move the drawer
            if !drawerAtFull { return true }

            // At full, content at top, dragging down → move drawer
            if contentAtTop && vel.y > 0 { return true }

            // Otherwise → fail so scroll view gets it (via require(toFail:))
            return false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            false
        }

        @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
            let translation = pan.translation(in: pan.view).y
            let velocity = pan.velocity(in: pan.view).y

            switch pan.state {
            case .changed:
                onDragChanged(translation, velocity)
            case .ended, .cancelled:
                onDragEnded(translation, velocity)
            default:
                break
            }
        }
    }
}
