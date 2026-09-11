import Foundation

/// A source of playback state. Implementations poll or subscribe to a player
/// and deliver `PlayerSnapshot`s on the main actor.
protocol PlayerMonitor: AnyObject {
    var name: String { get }
    var onSnapshot: (@MainActor (PlayerSnapshot) -> Void)? { get set }
    func start()
    func stop()
    /// Ask for a fresh snapshot as soon as possible.
    func refreshNow()
}
