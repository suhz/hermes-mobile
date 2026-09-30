import Foundation
import Testing

@testable import HermesKit

struct CanonicalBotChatClientTests {
  private let connection = ServerConnection(
    baseURL: URL(string: "http://mac.tailnet:9119")!,
    token: "tok"
  )

  @Test func lookupUsesGatewaySessionListByTitle() async throws {
    let sent = LockIsolated<JSONValue?>(nil)
    let client = CanonicalBotChatClient.live {
      HermesGatewayClient(
        connect: { _, _ in AsyncStream { $0.yield(.ready) } },
        send: { method, params in
          sent.setValue(.object(["method": .string(method), "params": params]))
          #expect(method == "session.list")
          return .object([
            "sessions": .array([
              .object([
                "id": .string("registry-bot"),
                "resolved_id": .string("tip-bot"),
                "title": .string("Bot Chat"),
                "message_count": .number(12),
              ])
            ])
          ])
        },
        disconnect: {}
      )
    }

    let lookup = try await client.lookup(connection, "nadi")
    #expect(lookup.includeHiddenSupported)
    #expect(lookup.sessions.map(\.id) == ["tip-bot"])
    #expect(lookup.sessions.first?.lineageRootID == "registry-bot")
    #expect(lookup.sessions.first?.title == "Bot Chat")
    #expect(lookup.sessions.first?.messageCount == 12)

    #expect(sent.value?["method"]?.stringValue == "session.list")
    #expect(sent.value?["params"]?["title"] == .string("Bot Chat"))
    #expect(sent.value?["params"]?["include_hidden"] == .bool(true))
    #expect(sent.value?["params"]?["profile"] == .string("nadi"))
  }

  @Test func lookupPassesDefaultProfileLiterally() async throws {
    let profileParam = LockIsolated<String?>(nil)
    let client = CanonicalBotChatClient.live {
      HermesGatewayClient(
        connect: { _, _ in AsyncStream { $0.yield(.ready) } },
        send: { _, params in
          if case let .object(fields) = params {
            profileParam.setValue(fields["profile"]?.stringValue)
          }
          return .object(["sessions": .array([])])
        },
        disconnect: {}
      )
    }
    let lookup = try await client.lookup(connection, "default")
    #expect(lookup.includeHiddenSupported)
    #expect(lookup.sessions.isEmpty)
    #expect(profileParam.value == "default")
  }

  @Test func lookupFailsClosedWhenGatewayNeverReady() async {
    let client = CanonicalBotChatClient.live {
      HermesGatewayClient(
        connect: { _, _ in AsyncStream { $0.finish() } },
        send: { _, _ in
          Issue.record("send must not run without gateway.ready")
          return .object([:])
        },
        disconnect: {}
      )
    }
    await #expect(throws: GatewayError.disconnected) {
      _ = try await client.lookup(connection, "arif")
    }
  }

  @Test func lookupFailsClosedOnAuthExpired() async {
    let client = CanonicalBotChatClient.live {
      HermesGatewayClient(
        connect: { _, _ in AsyncStream { $0.yield(.authExpired) } },
        send: { _, _ in
          Issue.record("send must not run after authExpired")
          return .object([:])
        },
        disconnect: {}
      )
    }
    await #expect(throws: GatewayError.authExpired) {
      _ = try await client.lookup(connection, "bob")
    }
  }
}
