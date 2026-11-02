import Foundation

/// The bundled portrait pool is independent of the user's agent roster.
public enum AgentAvatarOption: String, CaseIterable, Identifiable, Sendable {
    case yuki, matt, sofia, richard
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .yuki: return "头像 1"
        case .matt: return "头像 2"
        case .sofia: return "头像 3"
        case .richard: return "头像 4"
        }
    }
}
