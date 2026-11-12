/// Prevents an OS rejection from feeding repeated settings / status publications back into itself.
public struct DockVisibilityCoordinator {
    private var lastRequest: Bool?
    public init() {}
    /// Returns true only when this request changed the actual policy.
    @discardableResult
    public mutating func apply(requested: Bool, current: Bool, transition: (Bool) -> Bool) -> Bool {
        guard lastRequest != requested else { return false }
        // Record the attempt before calling the OS. Failure must not retry on unrelated publications.
        lastRequest = requested
        guard current != requested else { return false }
        return transition(requested)
    }
}
