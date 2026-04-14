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

        // Permanent stick-to-bottom observer. Async-loading content (images
        // resolving to their real aspect ratio, formatted text reflowing) can
        // grow the document height *after* a one-shot scroll-to-bottom has
        // already fired. This observer runs on every frame change and snaps
        // back to the bottom whenever the user was sitting there.
        flippedDocumentView.postsFrameChangedNotifications = true
        context.coordinator.contentFrameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: flippedDocumentView,
            queue: .main
        ) { [weak scrollView] _ in
            guard let scrollView else { return }
            let coord = context.coordinator
            let newHeight = scrollView.documentView?.frame.height ?? 0
            let prevHeight = coord.lastContentHeight
            coord.lastContentHeight = newHeight

            // Skip while loading older messages — preserveDistanceFromBottom
            // owns the scroll position during that window.
            if coord.isFrozen { return }
            // Skip until the initial scroll-to-bottom has fired, so we don't
            // race the one-shot setup logic in updateNSView.
            if !coord.hasScrolledToBottom { return }

            let currentOffset = scrollView.contentView.bounds.origin.y
            let visibleHeight = scrollView.contentView.bounds.height
            if let target = MessageScrollDecision.stickToBottomOffset(
                currentOffset: currentOffset,
                visibleHeight: visibleHeight,
                previousContentHeight: prevHeight,
                newContentHeight: newHeight
            ) {
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: target))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

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
                coord.lastWasAtBottom = coord.lastDistanceFromBottom < 20
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

        // Compute current distance from bottom for scroll decisions
        let currentOffset = scrollView.contentView.bounds.origin.y
        let currentVisibleHeight = scrollView.contentView.bounds.height
        let currentContentHeight = scrollView.documentView?.frame.height ?? 0
        let currentDistFromBottom = currentContentHeight - currentOffset - currentVisibleHeight

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
        } else if lastItemChanged {
            // New message at the end — scroll to bottom if we're near it.
            // Use the live measurement, not the cached lastWasAtBottom, because
            // external layout changes (typing indicator, window resize) can
            // invalidate the cached value.
            if currentDistFromBottom < 80 {
                coordinator.pendingAction = .scrollToBottom
            }
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
        var contentFrameObserver: NSObjectProtocol?
        var debounceTimer: Timer?
        var fallbackTimer: Timer?
        var hasScrolledToBottom = false
        var lastKnownItemCount = 0
        var lastKnownLastItemId: String?
        var pendingScrollToTop = false
        var pendingAction: ScrollAction?
        var lastContentHeight: CGFloat = 0

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
            fallbackTimer?.invalidate()

            guard let documentView = scrollView.documentView else { return }
            documentView.postsFrameChangedNotifications = true

            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: documentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView, self.pendingAction != nil else { return }

                // Frame changed — cancel the fallback, debounce for layout to settle
                self.fallbackTimer?.invalidate()
                self.debounceTimer?.invalidate()
                self.debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self, weak scrollView] _ in
                    self?.consumeAction(scrollView: scrollView)
                }
            }

            // Fallback: if no frame change happens (e.g., content replaced
            // in-place with no size change), apply the action after 150ms.
            fallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self, weak scrollView] _ in
                self?.consumeAction(scrollView: scrollView)
            }
        }

        private func consumeAction(scrollView: NSScrollView?) {
            guard let scrollView, let action = pendingAction else { return }
            pendingAction = nil
            fallbackTimer?.invalidate()
            debounceTimer?.invalidate()

            if let obs = frameObserver {
                NotificationCenter.default.removeObserver(obs)
                frameObserver = nil
            }

            applyAction(action, scrollView: scrollView)
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
            fallbackTimer?.invalidate()
            if let observer = scrollObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = frameObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = contentFrameObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

/// A flipped NSView so that content starts from the top (natural document flow).
private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
