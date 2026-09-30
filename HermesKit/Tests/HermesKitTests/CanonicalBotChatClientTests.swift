import Foundation
import Testing

@testable import HermesKit

struct CanonicalBotChatClientTests {
  private let connection = ServerConnection(
    baseURL: URL(string: "http://mac.tailnet:9119")!,
    token: "tok"
  )

  @Test func lookupUsesHiddenListWhenSupported() async throws {
    let hidden = Session(id: "bot", title: "Bot Chat")
    var profiles = HermesProfileClient()
    profiles.sessionsIncludingHidden = { _, profile, _, _, _, _ in
      #expect(profile == "arif")
      return [hidden]
    }
    profiles.sessions = { _, _, _, _, _, _ in
      Issue.record("visible list should not be consulted when include_hidden works")
      return []
    }
    let client = CanonicalBotChatClient.live(profiles: profiles)
    let lookup = try await client.lookup(connection, "arif")
    #expect(lookup.includeHiddenSupported)
    #expect(lookup.sessions.map(\.id) == ["bot"])
  }

  @Test func lookupFallsBackWhenIncludeHiddenIs404() async throws {
    var profiles = HermesProfileClient()
    profiles.sessionsIncludingHidden = { _, _, _, _, _, _ in throw RESTError.notFound }
    profiles.sessions = { _, _, _, _, _, _ in [Session(id: "vis", title: "Notes")] }
    let client = CanonicalBotChatClient.live(profiles: profiles)
    let lookup = try await client.lookup(connection, "arif")
    #expect(!lookup.includeHiddenSupported)
    #expect(lookup.sessions.map(\.id) == ["vis"])
  }

  @Test func lookupFallsBackWhenIncludeHiddenIs400() async throws {
    var profiles = HermesProfileClient()
    profiles.sessionsIncludingHidden = { _, _, _, _, _, _ in
      throw RESTError.server(status: 400, detail: "unknown query")
    }
    profiles.sessions = { _, _, _, _, _, _ in [] }
    let client = CanonicalBotChatClient.live(profiles: profiles)
    let lookup = try await client.lookup(connection, "default")
    #expect(!lookup.includeHiddenSupported)
    #expect(lookup.sessions.isEmpty)
  }

  @Test func lookupRethrowsUnrelatedFailures() async {
    var profiles = HermesProfileClient()
    profiles.sessionsIncludingHidden = { _, _, _, _, _, _ in throw RESTError.unauthorized }
    let client = CanonicalBotChatClient.live(profiles: profiles)
    await #expect(throws: RESTError.unauthorized) {
      _ = try await client.lookup(connection, "arif")
    }
  }
}
