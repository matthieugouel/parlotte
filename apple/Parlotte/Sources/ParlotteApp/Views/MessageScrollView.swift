import AppKit
import ParlotteLib
import SwiftUI

/// An NSScrollView-backed message list that supports:
/// - Scrolling to bottom on initial load / new messages
/// - Preserving scroll position when older messages are prepended
/// - Proper width constraint so content wraps to the scroll view width
struct MessageScrollView<Content: View>: NSViewRepresentable {
    let itemCount: Int
    let lastItemId: String?
    let isLoadingOlder: Bool
    let content: Content
    let onScrollToTop: (() -> Void)?

    init(
        itemCount: Int,
        lastItemId: String?,
        isLoadingOlder: Bool = false,
        onScrollToTop: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.itemCount = itemCount
        self.lastItemId = lastItemId
        self.isLoadingOlder = isLoadingOlder
        self.onScrollToTop = onScrollToTop
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let flippedDocumentView = FlippedView()
        flippedDocumentView.translatesAutoresizingMaskIntoConstraints = false
        flippedDocumentView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: flippedDocumentView.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: flippedDocumentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: flippedDocumentView.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: flippedDocumentView.bottomAnchor),
        ])

        scrollView.documentView = flippedDocumentView

        // Pin the hosting view width to the clip view so content wraps properly
        let widthConstraint = hostingView.widthAnchor.constraint(
            equalTo: scrollView.contentView.widthAnchor
        )
        widthConstraint.isActive = true
        context.coordinator.widthConstraint = widthConstraint

        // Continuously track scroll position for distance-from-bottom and scroll-to-top
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        context.coordinator.scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak scrollView] _ in
            guard let scrollView else { return }
            let coord = context.coordinator
            let offset = scrollView.contentView.bounds.origin.y
            let visibleHeight = scrollView.contentView.bounds.height
            let contentHeight = scrollView.documentView?.frame.height ?? 0

            // Don't update tracking while loading older messages or a preserve
            // action is pending — intermediate layout changes (Button → ProgressView)
            // would corrupt the saved distance.
            if coord.isFrozen {
                // frozen
            } else {
                // Clamp offset to [0, max] to ignore elastic overscroll
                let clampedOffset = max(0, min(offset, contentHeight - visibleHeight))
                coord.lastDistanceFromBottom = contentHeight - clampedOffset - visibleHeight
                coord.lastWasAtBottom = coord.lastDistanceFromBottom < 2
            }

            if offset <= 0 && !coord.isFrozen && coord.pendingAction == nil {
                coord.pendingScrollToTop = true
            }
        }

        context.coordinator.scrollView = scrollView
        context.coordinator.hostingView = hostingView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator

        let previousItemCount = coordinator.lastKnownItemCount
        let previousLastItemId = coordinator.lastKnownLastItemId
        let itemCountChanged = itemCount != previousItemCount
        let lastItemChanged = lastItemId != previousLastItemId

        // Reset when room changes (messages cleared then reloaded)
        if previousItemCount > 0 && itemCount == 0 {
            coordinator.hasScrolledToBottom = false
            coordinator.pendingAction = nil
            coordinator.isFrozen = false
            coordinator.debounceTimer?.invalidate()
        }

        // Freeze distance tracking as soon as loading starts,
        // before any layout changes (Button → ProgressView) can shift it.
        if isLoadingOlder && !coordinator.isFrozen {
            coordinator.isFrozen = true
            coordinator.pendingScrollToTop = false
        }

        // Decide the scroll action BEFORE updating content
        if !coordinator.hasScrolledToBottom {
            if itemCount > 0 {
                coordinator.hasScrolledToBottom = true
                coordinator.pendingAction = .scrollToBottom
            }
        } else if itemCountChanged && !lastItemChanged && itemCount > previousItemCount {
            // Items prepended: use the continuously-tracked distance from bottom
            coordinator.pendingAction = .preserveDistanceFromBottom(
                coordinator.lastDistanceFromBottom
            )
        } else if lastItemChanged && coordinator.lastWasAtBottom {
            coordinator.pendingAction = .scrollToBottom
        }

        coordinator.lastKnownItemCount = itemCount
        coordinator.lastKnownLastItemId = lastItemId

        // Update SwiftUI content — this triggers layout asynchronously
        coordinator.hostingView!.rootView = content

        // Install frame observer to apply the scroll action after layout settles
        if coordinator.pendingAction != nil {
            coordinator.installFrameObserver(scrollView: scrollView)
        }

        // Fire scroll-to-top callback
        if coordinator.pendingScrollToTop {
            coordinator.pendingScrollToTop = false
            onScrollToTop?()
        }
    }

    enum ScrollAction {
        case scrollToBottom
        case preserveDistanceFromBottom(CGFloat)
    }

    class Coordinator {
        weak var scrollView: NSScrollView?
        var hostingView: NSHostingView<Content>?
        var widthConstraint: NSLayoutConstraint?
        var scrollObserver: NSObjectProtocol?
        var frameObserver: NSObjectProtocol?
        var debounceTimer: Timer?
        var hasScrolledToBottom = false
        var lastKnownItemCount = 0
        var lastKnownLastItemId: String?
        var pendingScrollToTop = false
        var pendingAction: ScrollAction?

        // Continuously tracked by the bounds-change observer
        var lastDistanceFromBottom: CGFloat = 0
        var lastWasAtBottom = true
        var isFrozen = false

        func installFrameObserver(scrollView: NSScrollView) {
            if let obs = frameObserver {
                NotificationCenter.default.removeObserver(obs)
                frameObserver = nil
            }
            debounceTimer?.invalidate()

            guard let documentView = scrollView.documentView else { return }
            documentView.postsFrameChangedNotifications = true

            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: documentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView, self.pendingAction != nil else { return }

                // Debounce: wait for layout to settle (no frame changes for 50ms)
                self.debounceTimer?.invalidate()
                self.debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self, weak scrollView] _ in
                    guard let self, let scrollView, let action = self.pendingAction else { return }
                    self.pendingAction = nil

                    if let obs = self.frameObserver {
                        NotificationCenter.default.removeObserver(obs)
                        self.frameObserver = nil
                    }

                    self.applyAction(action, scrollView: scrollView)
                }
            }
        }

        private func applyAction(_ action: ScrollAction, scrollView: NSScrollView) {
            let contentHeight = scrollView.documentView?.frame.height ?? 0
            let visibleHeight = scrollView.contentView.bounds.height

            switch action {
            case .scrollToBottom:
                let maxOffset = max(contentHeight - visibleHeight, 0)
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxOffset))
                scrollView.reflectScrolledClipView(scrollView.contentView)

            case .preserveDistanceFromBottom(let distFromBottom):
                let newOffset = contentHeight - visibleHeight - distFromBottom
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(newOffset, 0)))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }

            // Unfreeze tracking now that the adjustment is complete
            isFrozen = false
        }

        deinit {
            debounceTimer?.invalidate()
            if let observer = scrollObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = frameObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

/// A flipped NSView so that content starts from the top (natural document flow).
private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
