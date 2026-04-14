import CoreGraphics

/// Pure decision logic for keeping the message scroll view pinned to the bottom
/// when content height grows after the initial scroll has already settled.
///
/// **The bug this prevents.** When a room opens, `MessageScrollView` fires a
/// scroll-to-bottom once the SwiftUI content frame stabilizes. Image messages,
/// however, load asynchronously — `MediaImageView` shows a metadata-sized
/// placeholder first (or a 4:3 fallback when the homeserver didn't provide
/// `mediaWidth`/`mediaHeight`), then resizes once the bytes arrive and the
/// real aspect ratio is known. That growth happens *after* the scroll fires,
/// leaving the last message clipped below the viewport. A permanent frame
/// observer in `MessageScrollView` calls into this helper on every content
/// growth and re-scrolls if the user was sitting at the bottom.
///
/// The logic is intentionally a pure function over geometry so it can be
/// covered by unit tests without an `NSScrollView` in the loop.
public enum MessageScrollDecision {
    /// Returns the offset the scroll view should snap to in order to remain
    /// pinned to the bottom after content height grew. Returns `nil` when no
    /// adjustment is appropriate — either the content didn't grow, or the user
    /// had scrolled too far up to be considered "following the bottom".
    ///
    /// - Parameters:
    ///   - currentOffset: The clip view's current `bounds.origin.y`.
    ///   - visibleHeight: The clip view's `bounds.height` (visible viewport).
    ///   - previousContentHeight: Height of the document view *before* the
    ///     change being evaluated. Pass `0` for the very first measurement
    ///     after a room load — this naturally produces a negative
    ///     prev-distance-from-bottom and triggers an initial scroll-to-bottom.
    ///   - newContentHeight: Height of the document view *after* the change.
    ///   - stickThreshold: How close to the previous bottom the user must have
    ///     been (in points) for the auto-stick to apply. Default 20pt is a
    ///     safe middle ground — bigger than overscroll noise, smaller than a
    ///     deliberately-scrolled-up reader.
    public static func stickToBottomOffset(
        currentOffset: CGFloat,
        visibleHeight: CGFloat,
        previousContentHeight: CGFloat,
        newContentHeight: CGFloat,
        stickThreshold: CGFloat = 20
    ) -> CGFloat? {
        guard newContentHeight > previousContentHeight else { return nil }
        let previousDistanceFromBottom = previousContentHeight - currentOffset - visibleHeight
        guard previousDistanceFromBottom < stickThreshold else { return nil }
        return max(newContentHeight - visibleHeight, 0)
    }
}
