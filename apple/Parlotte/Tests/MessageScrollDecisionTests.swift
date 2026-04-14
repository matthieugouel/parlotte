import Testing
import CoreGraphics
@testable import ParlotteLib

@Suite("MessageScrollDecision")
struct MessageScrollDecisionTests {

    // The bug: user opens "Alerts" room, scroll-to-bottom fires while images
    // still show their placeholder size, then images load and grow the content
    // by ~200pt, leaving the last message hidden below the viewport. With this
    // helper, every growth re-checks bottom-stickiness and snaps the scroll
    // back. This test pins down that exact scenario.
    @Test("Image loading grows content while user is at bottom — re-scrolls to new bottom")
    func growthWhileAtBottomReturnsNewBottomOffset() {
        // Was at bottom: 800 - 500 - 300 = 0 distance.
        // Image loads, content height jumps from 800 to 1000.
        let result = MessageScrollDecision.stickToBottomOffset(
            currentOffset: 500,
            visibleHeight: 300,
            previousContentHeight: 800,
            newContentHeight: 1000
        )
        // Want offset 700 so newOffset + visibleHeight == newContentHeight.
        #expect(result == 700)
    }

    @Test("User scrolled up to read scrollback — content growth does not jerk them down")
    func growthWhileScrolledUpReturnsNil() {
        // Was 400pt away from bottom — definitely reading older messages.
        let result = MessageScrollDecision.stickToBottomOffset(
            currentOffset: 100,
            visibleHeight: 300,
            previousContentHeight: 800,
            newContentHeight: 1000
        )
        #expect(result == nil)
    }

    @Test("Content shrunk — no scroll adjustment")
    func shrinkReturnsNil() {
        let result = MessageScrollDecision.stickToBottomOffset(
            currentOffset: 500,
            visibleHeight: 300,
            previousContentHeight: 1000,
            newContentHeight: 800
        )
        #expect(result == nil)
    }

    @Test("Content unchanged — no scroll adjustment")
    func noGrowthReturnsNil() {
        let result = MessageScrollDecision.stickToBottomOffset(
            currentOffset: 500,
            visibleHeight: 300,
            previousContentHeight: 800,
            newContentHeight: 800
        )
        #expect(result == nil)
    }

    @Test("Initial load from empty document — produces an initial scroll-to-bottom")
    func initialLoadFromZeroScrollsToBottom() {
        // First measurement: previousContentHeight = 0, so prev distance from
        // bottom is -visibleHeight (well under threshold) and we scroll.
        let result = MessageScrollDecision.stickToBottomOffset(
            currentOffset: 0,
            visibleHeight: 300,
            previousContentHeight: 0,
            newContentHeight: 1000
        )
        #expect(result == 700)
    }

    @Test("Content shorter than viewport — clamps offset to zero")
    func shortContentClampsToZero() {
        // Content is shorter than the viewport, so there's nothing to scroll
        // past — the bottom *is* offset 0.
        let result = MessageScrollDecision.stickToBottomOffset(
            currentOffset: 0,
            visibleHeight: 600,
            previousContentHeight: 0,
            newContentHeight: 200
        )
        #expect(result == 0)
    }

    @Test("Just at the threshold edge — scrolled up by exactly the threshold does not stick")
    func atThresholdBoundaryDoesNotStick() {
        // distance = 800 - currentOffset - visibleHeight = 20 (the threshold itself)
        // currentOffset = 800 - 300 - 20 = 480
        let result = MessageScrollDecision.stickToBottomOffset(
            currentOffset: 480,
            visibleHeight: 300,
            previousContentHeight: 800,
            newContentHeight: 1000
        )
        // Threshold is exclusive (< not <=), so 20 == threshold → no stick.
        #expect(result == nil)
    }
}
