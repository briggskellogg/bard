import Foundation
import CoreGraphics

/// Separates pointer intent from hover events caused by the sidebar's own layout.
struct SidebarHoverState: Equatable {
    enum Action: Hashable { case open(String), close(String) }
    struct Pending: Hashable {
        let action: Action
        let deadline: TimeInterval
    }

    private(set) var expanded: String?
    private(set) var hovered: String?
    private(set) var pending: Pending?
    private var layoutPointer: CGPoint?
    private var displacedArtist: String?

    mutating func enter(_ artist: String, pointer: CGPoint, now: TimeInterval) {
        // Returning to the open group always cancels a delayed departure.
        if expanded == artist {
            _ = isLayoutMovement(pointer)
            displacedArtist = nil
            hovered = artist
            pending = nil
            return
        }
        guard !isLayoutMovement(pointer) else { return }
        displacedArtist = nil
        hovered = artist
        guard pending?.action != .open(artist) else { return }
        pending = Pending(action: .open(artist), deadline: now + 0.09)
    }

    mutating func leave(_ artist: String, pointer: CGPoint, now: TimeInterval) {
        if isLayoutMovement(pointer) {
            if hovered == artist { displacedArtist = artist }
            return
        }
        guard hovered == artist else { return }
        displacedArtist = nil
        hovered = nil
        pending = expanded.map { Pending(action: .close($0), deadline: now + 0.34) }
    }

    // A group can slide away from a stationary pointer. Observe the stable
    // sidebar too, so its next real movement can still complete that departure.
    mutating func move(pointer: CGPoint, now: TimeInterval) {
        guard !isLayoutMovement(pointer), displacedArtist != nil else { return }
        depart(now: now)
    }

    mutating func depart(now: TimeInterval) {
        displacedArtist = nil
        hovered = nil
        layoutPointer = nil
        guard pending?.action != expanded.map(Action.close) else { return }
        pending = expanded.map { Pending(action: .close($0), deadline: now + 0.34) }
    }

    mutating func resolve(_ request: Pending, pointer: CGPoint, now: TimeInterval) {
        guard pending == request, now >= request.deadline else { return }
        pending = nil
        switch request.action {
        case .open(let artist):
            guard hovered == artist else { return }
            expanded = artist
        case .close(let artist):
            guard hovered != artist, expanded == artist else { return }
            expanded = nil
        }
        layoutPointer = pointer
        displacedArtist = nil
    }

    mutating func reveal(_ artist: String?, pointer: CGPoint) {
        pending = nil
        hovered = nil
        expanded = artist
        layoutPointer = pointer
        displacedArtist = nil
    }

    mutating func cancelPending() { pending = nil; hovered = nil; displacedArtist = nil }

    private mutating func isLayoutMovement(_ pointer: CGPoint) -> Bool {
        guard let anchor = layoutPointer else { return false }
        if hypot(pointer.x - anchor.x, pointer.y - anchor.y) <= 1 { return true }
        layoutPointer = nil
        return false
    }
}
