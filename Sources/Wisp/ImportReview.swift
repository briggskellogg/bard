import Foundation
import WispCore

/// A review is a presentation of prepared copies, not a saved library change.
struct ImportReview: Identifiable {
    let id: UUID
    let tracks: [Track]
    let notes: [UUID: [String]]
    let duplicateCount: Int
    let failures: [String]
    let destinationName: String
}
