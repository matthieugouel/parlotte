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

@Suite("HtmlSanitizer")
struct HtmlSanitizerTests {
    @Test("Strips <img> — NSAttributedString would fetch src")
    func stripsImg() {
        let out = HtmlSanitizer.sanitize(#"hi <img src="https://evil/ping"> there"#)
        #expect(!out.lowercased().contains("<img"))
        #expect(!out.contains("evil"))
    }

    @Test("Strips <script> and its contents")
    func stripsScriptBlock() {
        let out = HtmlSanitizer.sanitize("before<script>alert(1)</script>after")
        #expect(!out.lowercased().contains("<script"))
        #expect(!out.contains("alert"))
        #expect(out.contains("before"))
        #expect(out.contains("after"))
    }

    @Test("Strips <style>, <iframe>, <svg>, <link>, <meta>")
    func stripsOtherRiskyTags() {
        let cases = [
            #"x<style>@import 'https://evil/'</style>y"#,
            #"x<iframe src="https://evil"></iframe>y"#,
            #"x<svg><image href="https://evil"/></svg>y"#,
            #"x<link rel="stylesheet" href="https://evil">y"#,
            #"x<meta http-equiv="refresh" content="0;url=https://evil">y"#,
        ]
        for input in cases {
            let out = HtmlSanitizer.sanitize(input)
            #expect(!out.contains("evil"), "leaked `evil` from: \(input) -> \(out)")
            #expect(out.contains("x") && out.contains("y"))
        }
    }

    @Test("Keeps allowed tags")
    func keepsAllowedTags() {
        let input = "<strong>bold</strong> <em>em</em> <code>c</code>"
        let out = HtmlSanitizer.sanitize(input).lowercased()
        #expect(out.contains("<strong>"))
        #expect(out.contains("<em>"))
        #expect(out.contains("<code>"))
    }

    @Test("Strips on* event handlers")
    func stripsEventHandlers() {
        let out = HtmlSanitizer.sanitize(#"<a href="https://ok" onclick="x()">hi</a>"#)
        #expect(!out.contains("onclick"))
        #expect(out.contains("https://ok"))
    }

    @Test("Neutralises javascript: hrefs")
    func neutralisesJavascriptHrefs() {
        let out = HtmlSanitizer.sanitize(#"<a href="javascript:alert(1)">click</a>"#)
        #expect(!out.lowercased().contains("javascript:"))
        #expect(out.contains("#"))
    }

    @Test("Strips unknown tags but keeps inner text")
    func dropsUnknownTagsKeepsText() {
        let out = HtmlSanitizer.sanitize("<foo>keep me</foo>")
        #expect(!out.contains("<foo>"))
        #expect(out.contains("keep me"))
    }
}
