import Foundation

// Represents a social account linked to a user (e.g., SSO providers like Authentik)
struct SocialAccount: Codable, Hashable {
    let uid: String?
    let provider: String?
    let display: String?
    let lastLogin: String?
    let dateJoined: String?
    let extraData: [String: AnyCodable]?

    private enum CodingKeys: String, CodingKey {
        case uid
        case provider
        case display
        case lastLogin = "last_login"
        case dateJoined = "date_joined"
        case extraData = "extra_data"
    }
}

// Wrapper to handle arbitrary JSON in extraData
enum AnyCodable: Codable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodable])
    case object([String: AnyCodable])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: AnyCodable].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodable")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let bool):
            try container.encode(bool)
        case .int(let int):
            try container.encode(int)
        case .double(let double):
            try container.encode(double)
        case .string(let string):
            try container.encode(string)
        case .array(let array):
            try container.encode(array)
        case .object(let object):
            try container.encode(object)
        }
    }
}

struct RMMUser: Identifiable, Decodable, Hashable {
    let id: Int
    let username: String
    let firstName: String?
    let lastName: String?
    let email: String?
    let isActive: Bool
    let lastLogin: String?
    let lastLoginIP: String?
    let role: Int?
    let blockDashboardLogin: Bool?
    let dateFormat: String?
    let socialAccounts: [SocialAccount]?

    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case isActive = "is_active"
        case lastLogin = "last_login"
        case lastLoginIP = "last_login_ip"
        case role
        case blockDashboardLogin = "block_dashboard_login"
        case dateFormat = "date_format"
        case socialAccounts = "social_accounts"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        
        // Required fields with fallbacks
        id = (try c.decodeIfPresent(Int.self, forKey: .id)) ?? 0
        username = (try c.decodeIfPresent(String.self, forKey: .username)) ?? "Unknown User"
        
        // Optional fields
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        isActive = (try c.decodeIfPresent(Bool.self, forKey: .isActive)) ?? false
        lastLogin = try c.decodeIfPresent(String.self, forKey: .lastLogin)
        lastLoginIP = try c.decodeIfPresent(String.self, forKey: .lastLoginIP)
        role = try c.decodeIfPresent(Int.self, forKey: .role)
        blockDashboardLogin = try c.decodeIfPresent(Bool.self, forKey: .blockDashboardLogin)
        dateFormat = try c.decodeIfPresent(String.self, forKey: .dateFormat)
        
        // Social accounts - handle as array of objects or ignore if missing
        socialAccounts = try c.decodeIfPresent([SocialAccount].self, forKey: .socialAccounts)
    }

    init(id: Int,
         username: String,
         firstName: String?,
         lastName: String?,
         email: String?,
         isActive: Bool,
         lastLogin: String?,
         lastLoginIP: String?,
         role: Int?,
         blockDashboardLogin: Bool?,
         dateFormat: String?,
         socialAccounts: [SocialAccount]?) {
        self.id = id
        self.username = username
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.isActive = isActive
        self.lastLogin = lastLogin
        self.lastLoginIP = lastLoginIP
        self.role = role
        self.blockDashboardLogin = blockDashboardLogin
        self.dateFormat = dateFormat
        self.socialAccounts = socialAccounts
    }

    var displayName: String {
        let components = [firstName, lastName].compactMap { value -> String? in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
            return trimmed
        }
        if components.isEmpty {
            return username
        }
        return components.joined(separator: " ")
    }

    var statusLabel: String { isActive ? "Active" : "Disabled" }

    var lastLoginDisplay: String {
        formatLastSeenTimestamp(lastLogin)
    }

    var roleLabel: String {
        guard let role else { return "Role unknown" }
        return "Role \(role)"
    }

    var canAccessDashboard: Bool {
        !(blockDashboardLogin ?? false)
    }
}
