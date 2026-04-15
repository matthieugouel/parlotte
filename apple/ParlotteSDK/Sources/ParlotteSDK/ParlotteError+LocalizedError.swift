import Foundation
@_exported import ParlotteFFI

extension ParlotteError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .Auth(let message),
             .Network(let message),
             .Room(let message),
             .Store(let message),
             .Sync(let message),
             .Unknown(let message):
            return message
        }
    }
}
