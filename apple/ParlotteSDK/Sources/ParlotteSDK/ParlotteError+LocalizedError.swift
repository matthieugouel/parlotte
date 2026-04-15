import Foundation
@_exported import ParlotteFFI

public extension Error {
    /// User-facing message for the error. For `ParlotteError` (a UniFFI-
    /// generated enum whose `localizedDescription` falls back to a reflection
    /// dump like `ParlotteFFI.ParlotteError.Unknown(message: "...")`), this
    /// unwraps the inner message. For anything else, falls through to
    /// `localizedDescription`.
    var displayMessage: String {
        if let ffi = self as? ParlotteError {
            switch ffi {
            case .Auth(let message),
                 .Network(let message),
                 .Room(let message),
                 .Store(let message),
                 .Sync(let message),
                 .Unknown(let message):
                return message
            }
        }
        return localizedDescription
    }
}
