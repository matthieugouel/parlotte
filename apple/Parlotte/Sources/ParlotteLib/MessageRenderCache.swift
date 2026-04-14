import Foundation
import SwiftUI

/// Synchronous cache for the expensive HTML → AttributedString conversion that
/// formatted Matrix message bodies require.
///
/// **Why synchronous matters.** The conversion uses
/// `NSAttributedString(data:options:)` with the HTML document type, which is
/// slow enough that calling it on every SwiftUI body re-evaluation visibly lags
/// scrolling in busy rooms. An earlier fix moved the work into `.onAppear`,
/// populating an `@State` after the first render. That made each bubble render
/// twice — first with the plain-text fallback (one height), then with the
/// formatted version (potentially a different height). The reflow happened
/// *after* `MessageScrollView`'s scroll-to-bottom fired, leaving the last
/// message clipped below the visible area. Returning a non-nil value on the
/// **first** call for valid HTML keeps the row's height stable across renders
/// so the auto-scroll lands in the right place.
public enum MessageRenderCache {
    private static let cache = NSCache<NSString, AttributedStringBox>()

    public static func attributedString(for formattedBody: String?) -> AttributedString? {
        guard let formattedBody, !formattedBody.isEmpty else { return nil }
        let key = formattedBody as NSString
        if let cached = cache.object(forKey: key) {
            return cached.value
        }
        guard let computed = build(from: formattedBody) else { return nil }
        cache.setObject(AttributedStringBox(value: computed), forKey: key)
        return computed
    }

    private static func build(from html: String) -> AttributedString? {
        let wrapped = "<html><body style=\"font-family: -apple-system; font-size: 14px;\">\(html)</body></html>"
        guard let data = wrapped.data(using: .utf8),
              let nsAttr = try? NSAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.html,
                            .characterEncoding: String.Encoding.utf8.rawValue],
                  documentAttributes: nil
              ) else { return nil }
        return try? AttributedString(nsAttr, including: \.swiftUI)
    }

    private final class AttributedStringBox {
        let value: AttributedString
        init(value: AttributedString) { self.value = value }
    }
}
