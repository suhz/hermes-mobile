import ComposableArchitecture
import DependenciesMacros
import Foundation

/// Profile-scoped registry lookup for the canonical `"Bot Chat"` session.
///
/// Desktop uses gateway `session.list { title, include_hidden, profile }`. Mobile has no
/// standing socket outside `ChatFeature`, so the live path is REST
/// `GET /api/profiles/sessions` with `include_hidden=true` when the agent accepts it,
/// falling back to the visible list (capability-gated). A thrown error is fail-closed:
/// the caller must not mint.
@DependencyClient
public struct CanonicalBotChatClient: Sendable {
  /// List sessions for `profile` (literal name, including `"default"`). Throws on any
  /// transport/HTTP/decode failure — never returns a partial/empty list in that case.
  public var lookup: @Sendable (_ connection: ServerConnection, _ profile: String) async throws -> CanonicalBotChatLookup
}

public extension CanonicalBotChatClient {
  /// Live lookup over profile-scoped REST. Tries `include_hidden=true` first; a 400/404/405
  /// falls back to the visible list and marks `includeHiddenSupported = false`.
  ///
  /// When `profiles` is omitted, the live client reads ``DependencyValues/hermesProfiles``
  /// so DemoMode / tests that override that client are honored (never a second URLSession).
  static func live(profiles: HermesProfileClient? = nil) -> CanonicalBotChatClient {
    CanonicalBotChatClient(
      lookup: { connection, profile in
        @Dependency(\.hermesProfiles) var injected
        let profiles = profiles ?? injected
        do {
          let sessions = try await listPages(
            profiles: profiles, connection: connection, profile: profile, includeHidden: true
          )
          return CanonicalBotChatLookup(sessions: sessions, includeHiddenSupported: true)
        } catch let error as RESTError where isIncludeHiddenUnsupported(error) {
          let sessions = try await listPages(
            profiles: profiles, connection: connection, profile: profile, includeHidden: false
          )
          return CanonicalBotChatLookup(sessions: sessions, includeHiddenSupported: false)
        }
      }
    )
  }

  /// Empty successful lookup (hidden supported) — tests that only need the client present.
  static func inMemory() -> CanonicalBotChatClient {
    CanonicalBotChatClient(
      lookup: { _, _ in CanonicalBotChatLookup(sessions: [], includeHiddenSupported: true) }
    )
  }
}

extension CanonicalBotChatClient: DependencyKey {
  public static var liveValue: CanonicalBotChatClient { .live() }
  public static var testValue: CanonicalBotChatClient { CanonicalBotChatClient() }
}

public extension DependencyValues {
  var canonicalBotChat: CanonicalBotChatClient {
    get { self[CanonicalBotChatClient.self] }
    set { self[CanonicalBotChatClient.self] = newValue }
  }
}

/// Page through the profile session list looking for the registry row. Cap is a safety
/// bound (no server-side title index on older agents); a Bot Chat older than the cap
/// would be missed — documented in the Bot Mode plan.
private func listPages(
  profiles: HermesProfileClient,
  connection: ServerConnection,
  profile: String,
  includeHidden: Bool
) async throws -> [Session] {
  var all: [Session] = []
  var offset = 0
  let pageSize = 100
  let cap = 500
  while all.count < cap {
    let page: [Session]
    if includeHidden {
      page = try await profiles.sessionsIncludingHidden(
        connection, profile, .exclude, .recent, pageSize, offset
      )
    } else {
      page = try await profiles.sessions(
        connection, profile, .exclude, .recent, pageSize, offset
      )
    }
    all.append(contentsOf: page)
    if page.count < pageSize { break }
    offset += pageSize
  }
  return all
}

/// Query-param / verb the agent doesn't know. 400 covers "unknown query"; 404/405 is the
/// shared missing-endpoint verdict.
private func isIncludeHiddenUnsupported(_ error: RESTError) -> Bool {
  if error.isMissingEndpointVerdict { return true }
  if case .server(status: 400, _) = error { return true }
  return false
}
