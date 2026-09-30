import ComposableArchitecture
import DependenciesMacros
import Foundation

/// Profile-scoped registry lookup for the canonical `"Bot Chat"` session.
///
/// Desktop resolves via gateway `session.list { title, include_hidden, profile }` —
/// an exact-title, window-free read that finds the hidden forever-chat. Mobile has no
/// standing socket outside `ChatFeature`, so the live path opens a **short-lived**
/// gateway connection (a separate `HermesGatewayClient` instance — never the chat
/// slot's shared dependency), runs the same RPC, and disconnects.
///
/// REST `GET /api/profiles/sessions?include_hidden=true` is **not** used: the dashboard
/// endpoint ignores `include_hidden` / `title`, silently returns only visible rows, and
/// would make a successful empty list look like "no Bot Chat" → minting a fork.
@DependencyClient
public struct CanonicalBotChatClient: Sendable {
  /// Exact-title registry lookup for `profile` (literal name, including `"default"`).
  /// Throws on any transport/RPC failure — never returns a partial/empty list in that
  /// case (callers must not mint).
  public var lookup: @Sendable (_ connection: ServerConnection, _ profile: String) async throws -> CanonicalBotChatLookup
}

public extension CanonicalBotChatClient {
  /// Live lookup over gateway `session.list` with `title: "Bot Chat"`.
  ///
  /// `gatewayFactory` builds an **ephemeral** client so this never steals
  /// `ChatFeature`'s shared `hermesGateway` socket. Tests inject a stub factory.
  static func live(
    gatewayFactory: @escaping @Sendable () -> HermesGatewayClient = { .live() }
  ) -> CanonicalBotChatClient {
    CanonicalBotChatClient(
      lookup: { connection, profile in
        try await lookupViaGateway(
          connection: connection,
          profile: profile,
          gateway: gatewayFactory()
        )
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

// MARK: - Gateway one-shot

private func lookupViaGateway(
  connection: ServerConnection,
  profile: String,
  gateway: HermesGatewayClient
) async throws -> CanonicalBotChatLookup {
  try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CanonicalBotChatLookup, any Error>) in
    let settled = LockIsolated(false)
    let finish: @Sendable (Result<CanonicalBotChatLookup, any Error>) -> Void = { result in
      let alreadyResumed = settled.withValue { flag -> Bool in
        defer { flag = true }
        return flag
      }
      guard !alreadyResumed else { return }
      gateway.disconnect()
      continuation.resume(with: result)
    }

    Task {
      var sawReady = false
      for await event in gateway.connect(connection.baseURL, connection.auth) {
        switch event {
        case .ready:
          sawReady = true
          do {
            let lookup = try await sessionListBotChat(gateway: gateway, profile: profile)
            finish(.success(lookup))
          } catch {
            finish(.failure(error))
          }
          return
        case .authExpired:
          finish(.failure(GatewayError.authExpired))
          return
        default:
          continue
        }
      }
      if !sawReady {
        finish(.failure(GatewayError.disconnected))
      }
    }
  }
}

private func sessionListBotChat(
  gateway: HermesGatewayClient,
  profile: String
) async throws -> CanonicalBotChatLookup {
  // Exact-title path is window-free and resolves hidden rows (desktop contract).
  // Always pass `profile` so the gateway opens that profile's state.db — omitting it
  // would search the default store and miss arif/bob/nadi forever-chats.
  let params: JSONValue = .object([
    "title": .string(CanonicalBotChat.title),
    "include_hidden": .bool(true),
    "limit": .number(200),
    "profile": .string(profile),
  ])
  let result = try await gateway.send("session.list", params)
  let sessions = decodeGatewaySessions(result)
  // Title lookup finds hidden rows by design — treat as include_hidden-capable so a
  // confirmed miss may mint; a thrown error above stays fail-closed.
  return CanonicalBotChatLookup(sessions: sessions, includeHiddenSupported: true)
}

/// Decode `session.list` rows. Prefer `resolved_id` (compression tip) as `Session.id` so
/// `session.resume` opens the live tip — same as desktop `openStoredBotChat`.
private func decodeGatewaySessions(_ result: JSONValue) -> [Session] {
  guard case let .object(root) = result,
        case let .array(rows) = root["sessions"]
  else { return [] }

  return rows.compactMap { row -> Session? in
    guard case let .object(fields) = row,
          let registryID = fields["id"]?.stringValue?.trimmedNonEmpty
    else { return nil }
    let tip = fields["resolved_id"]?.stringValue?.trimmedNonEmpty
    let openID = tip ?? registryID
    let title = fields["title"]?.stringValue
    let messageCount: Int?
    if case let .number(n) = fields["message_count"] {
      messageCount = Int(n)
    } else {
      messageCount = nil
    }
    return Session(
      id: openID,
      title: title,
      messageCount: messageCount,
      lineageRootID: openID == registryID ? nil : registryID
    )
  }
}
