import Testing
@testable import ParlotteLib

@Suite("MessageRenderCache")
struct MessageRenderCacheTests {

    // Synchronous availability is the load-bearing contract here. If the cache
    // ever returns nil on the first call for valid HTML and only populates on
    // a later call, MessageBubble renders the plain-text fallback first and
    // then re-renders at a different height after the formatted version is
    // ready. That post-render reflow happens *after* MessageScrollView's
    // scroll-to-bottom fires and clips the last message below the viewport.
    @Test("Returns a non-nil AttributedString synchronously on the first call")
    func synchronousFirstCallForFormattedHtml() {
        let html = "<strong>hello</strong> world"
        let result = MessageRenderCache.attributedString(for: html)
        #expect(result != nil)
        let plain = String(result!.characters)
        #expect(plain.contains("hello"))
        #expect(plain.contains("world"))
    }

    @Test("Returns nil for nil input")
    func nilInput() {
        #expect(MessageRenderCache.attributedString(for: nil) == nil)
    }

    @Test("Returns nil for empty string")
    func emptyInput() {
        #expect(MessageRenderCache.attributedString(for: "") == nil)
    }

    @Test("Subsequent calls for the same HTML still return a value")
    func cachedCallStillReturnsValue() {
        let html = "<em>cached</em> message"
        _ = MessageRenderCache.attributedString(for: html)
        let second = MessageRenderCache.attributedString(for: html)
        #expect(second != nil)
        #expect(String(second!.characters).contains("cached"))
    }

    @Test("Different HTML inputs produce different rendered text")
    func distinctInputsProduceDistinctOutput() {
        let a = MessageRenderCache.attributedString(for: "<p>first</p>")
        let b = MessageRenderCache.attributedString(for: "<p>second</p>")
        #expect(a != nil)
        #expect(b != nil)
        #expect(String(a!.characters).contains("first"))
        #expect(String(b!.characters).contains("second"))
    }
}
