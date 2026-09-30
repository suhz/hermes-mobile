import Foundation

/// A Hermes profile (an independent environment: separate config, skills, SOUL.md, and
/// its own sessions). Decoded from `ProfileInfo` in `GET /api/profiles`
/// (`{ profiles: [...] }`). The default profile (`isDefault`) can't be renamed/deleted.
///
/// Decodes leniently — missing optional fields (`model`/`provider`) and absent
/// `skill_count`/`has_env` never crash. `Identifiable` by `name`.
public struct Profile: Equatable, Sendable, Identifiable, Decodable {
  /// Profile name — the identifier used in `?profile=` scoping. Also the `id`.
  public var name: String
  /// Whether this is the default/primary profile (can't be renamed/deleted).
  public var isDefault: Bool
  public var model: String?
  public var provider: String?
  /// Number of skills configured for this profile.
  public var skillCount: Int
  /// Whether the profile has an `.env` (env overrides) configured.
  public var hasEnv: Bool
  /// Optional display title from `GET /api/profiles` (`display_name`). Roster-only.
  public var displayName: String?
  /// Optional one-line description from the same payload.
  public var description: String?
  /// When `true`, the agent injects teammate-messaging protocol into Bot Chat itself.
  /// Clients must not append that protocol text to SOUL.md on create.
  public var botModeProtocol: Bool

  public var id: String { name }

  /// Roster title: `display_name` when present, else the profile `name`.
  public var rosterTitle: String { displayName?.trimmedNonEmpty ?? name }

  enum CodingKeys: String, CodingKey {
    case name
    case isDefault = "is_default"
    case model
    case provider
    case skillCount = "skill_count"
    case hasEnv = "has_env"
    case displayName = "display_name"
    case description
    case botModeProtocol = "bot_mode_protocol"
  }

  public init(
    name: String,
    isDefault: Bool = false,
    model: String? = nil,
    provider: String? = nil,
    skillCount: Int = 0,
    hasEnv: Bool = false,
    displayName: String? = nil,
    description: String? = nil,
    botModeProtocol: Bool = false
  ) {
    self.name = name
    self.isDefault = isDefault
    self.model = model
    self.provider = provider
    self.skillCount = skillCount
    self.hasEnv = hasEnv
    self.displayName = displayName
    self.description = description
    self.botModeProtocol = botModeProtocol
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = (try? c.decode(String.self, forKey: .name)) ?? ""
    isDefault = (try? c.decodeIfPresent(Bool.self, forKey: .isDefault)) ?? false
    model = try? c.decodeIfPresent(String.self, forKey: .model)
    provider = try? c.decodeIfPresent(String.self, forKey: .provider)
    skillCount = (try? c.decodeIfPresent(Int.self, forKey: .skillCount)) ?? 0
    hasEnv = (try? c.decodeIfPresent(Bool.self, forKey: .hasEnv)) ?? false
    displayName = try? c.decodeIfPresent(String.self, forKey: .displayName)
    description = try? c.decodeIfPresent(String.self, forKey: .description)
    botModeProtocol = (try? c.decodeIfPresent(Bool.self, forKey: .botModeProtocol)) ?? false
  }
}
