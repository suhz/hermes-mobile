import Foundation

/// Desktop Bot Mode identity: a bot **is** a Hermes profile, and that bot's primary
/// conversation is the forever-session titled exactly ``title`` (`"Bot Chat"`).
/// Identity is `(profile, title == "Bot Chat")` — never a stored session-id pin.
///
/// Mobile is a thin remote client: this type is the registry rule only. Opening the
/// chat still goes through `ChatFeature` + `session.resume` / `session.create`.
public enum CanonicalBotChat: Sendable {
  /// Exact session title the desktop plugin uses (`CANONICAL_CHAT_TITLE`).
  public static let title = "Bot Chat"

  /// Optional one-shot kickoff sent after a successful mint (desktop create path).
  public static let introPrompt = "Hey, tell me about yourself!"

  /// True when `session.title` is exactly ``title`` (no trimming, no `"Untitled"` fallback).
  public static func matches(_ session: Session) -> Bool {
    session.title == title
  }

  /// Adopt the first exact-title match. Prefer the earliest list row if the registry
  /// ever forked — minting a second row is the failure this helper exists to prevent.
  public static func adopt(from sessions: [Session]) -> Session? {
    sessions.first(where: matches)
  }
}

/// Outcome of a successful registry lookup. A failed lookup never produces this —
/// callers must not mint when ``CanonicalBotChatClient/lookup`` throws.
public enum CanonicalBotChatResolution: Equatable, Sendable {
  /// An existing `"Bot Chat"` row — resume it. Never create.
  case adopt(Session)
  /// The list succeeded and no row exists — safe to `session.create` titled `"Bot Chat"`.
  case mint
}

/// Why Bot Chat was not opened. All cases are fail-closed: **never mint**.
public enum CanonicalBotChatError: Error, Equatable, Sendable {
  /// `session.list` / profile-sessions REST failed. Minting would risk a second Bot Chat.
  case lookupFailed
  /// The list succeeded but cannot prove uniqueness (no `include_hidden`), and this
  /// is not a just-created profile. Minting could fork a hidden Bot Chat.
  case cannotVerifyUniqueness
  /// The tapped profile is no longer in the roster.
  case profileMissing

  public var message: String {
    switch self {
    case .lookupFailed:
      "Couldn’t look up Bot Chat. Nothing was created."
    case .cannotVerifyUniqueness:
      "This agent doesn’t list hidden sessions, so a Bot Chat wasn’t created — that would risk a duplicate."
    case .profileMissing:
      "That bot is no longer on the server."
    }
  }
}

/// A completed profile-scoped session list used as the Bot Chat registry.
public struct CanonicalBotChatLookup: Equatable, Sendable {
  public var sessions: [Session]
  /// True when the list was fetched with `include_hidden` (or an equivalent that
  /// returns hidden rows). When false, a missing `"Bot Chat"` is not proof of absence.
  public var includeHiddenSupported: Bool

  public init(sessions: [Session], includeHiddenSupported: Bool) {
    self.sessions = sessions
    self.includeHiddenSupported = includeHiddenSupported
  }
}

public extension CanonicalBotChat {
  /// Adopt-before-mint, fail-closed.
  ///
  /// - A successful lookup is required. Callers that caught a transport/HTTP failure
  ///   must not call this with a synthetic empty list.
  /// - Exact title match → adopt (even when `include_hidden` is unsupported).
  /// - `include_hidden` supported and no match → mint.
  /// - `include_hidden` unsupported and `allowMintWithoutHidden` (just-created profile)
  ///   → mint (no Bot Chat can exist yet).
  /// - Otherwise → ``CanonicalBotChatError/cannotVerifyUniqueness``.
  static func resolve(
    _ lookup: CanonicalBotChatLookup,
    allowMintWithoutHidden: Bool = false
  ) -> Result<CanonicalBotChatResolution, CanonicalBotChatError> {
    if let existing = adopt(from: lookup.sessions) {
      return .success(.adopt(existing))
    }
    if lookup.includeHiddenSupported || allowMintWithoutHidden {
      return .success(.mint)
    }
    return .failure(.cannotVerifyUniqueness)
  }
}
