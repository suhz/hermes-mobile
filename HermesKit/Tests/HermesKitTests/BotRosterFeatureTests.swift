import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

@MainActor
struct BotRosterFeatureTests {
  private let connection = ServerConnection(
    baseURL: URL(string: "http://mac.tailnet:9119")!,
    token: "tok"
  )

  private func store(
    profiles: [Profile] = [Profile(name: "default", isDefault: true), Profile(name: "arif")],
    lookup: @escaping @Sendable (ServerConnection, String) async throws -> CanonicalBotChatLookup
  ) -> TestStoreOf<BotRosterFeature> {
    TestStore(
      initialState: BotRosterFeature.State(
        connection: connection,
        profiles: IdentifiedArray(uniqueElements: profiles)
      )
    ) {
      BotRosterFeature()
    } withDependencies: {
      $0.canonicalBotChat.lookup = lookup
      $0.hermesProfiles.list = { @Sendable _ in profiles }
    }
  }

  @Test func tapAdoptsExistingBotChat() async {
    let existing = Session(id: "bot-arif", title: "Bot Chat")
    let store = store { _, profile in
      #expect(profile == "arif")
      return CanonicalBotChatLookup(sessions: [existing], includeHiddenSupported: true)
    }

    await store.send(.botTapped(name: "arif")) {
      $0.openingProfileName = "arif"
    }
    await store.receive(\.openResolved) {
      $0.openingProfileName = nil
    }
    await store.receive(\.delegate.openBotChat) {
      // payload asserted via CasePath — session + profile
    }
  }

  @Test func tapMintsWhenHiddenListHasNoBotChat() async {
    let store = store { _, _ in
      CanonicalBotChatLookup(sessions: [Session(id: "other", title: "Notes")], includeHiddenSupported: true)
    }

    await store.send(.botTapped(name: "arif")) {
      $0.openingProfileName = "arif"
    }
    await store.receive(\.openResolved) {
      $0.openingProfileName = nil
    }
    await store.receive(\.delegate.mintBotChat)
  }

  @Test func tapFailClosedWhenLookupThrows() async {
    let store = store { _, _ in throw RESTError.unreachable }

    await store.send(.botTapped(name: "arif")) {
      $0.openingProfileName = "arif"
    }
    await store.receive(\.openResolved) {
      $0.openingProfileName = nil
      $0.loadError = CanonicalBotChatError.lookupFailed.message
    }
    // No mint / open delegate — fail closed.
  }

  @Test func tapFailClosedWhenHiddenUnsupportedAndMissing() async {
    let store = store { _, _ in
      CanonicalBotChatLookup(sessions: [], includeHiddenSupported: false)
    }

    await store.send(.botTapped(name: "arif")) {
      $0.openingProfileName = "arif"
    }
    await store.receive(\.openResolved) {
      $0.openingProfileName = nil
      $0.loadError = CanonicalBotChatError.cannotVerifyUniqueness.message
    }
  }

  @Test func justCreatedProfileMintsWithoutHiddenSupport() async {
    let store = store { _, _ in
      CanonicalBotChatLookup(sessions: [], includeHiddenSupported: false)
    }

    await store.send(.openCreatedBot(name: "arif")) {
      $0.openingProfileName = "arif"
    }
    await store.receive(\.openResolved) {
      $0.openingProfileName = nil
    }
    await store.receive(\.delegate.mintBotChat)
  }

  @Test func missingProfileDoesNotLookup() async {
    let lookedUp = LockIsolated(false)
    let store = store { _, _ in
      lookedUp.setValue(true)
      return CanonicalBotChatLookup(sessions: [], includeHiddenSupported: true)
    }

    await store.send(.botTapped(name: "ghost")) {
      $0.loadError = CanonicalBotChatError.profileMissing.message
    }
    #expect(lookedUp.value == false)
  }

  @Test func addBotDelegatesToParentSheet() async {
    let store = store { _, _ in
      CanonicalBotChatLookup(sessions: [], includeHiddenSupported: true)
    }
    await store.send(.addBotTapped)
    await store.receive(\.delegate.addBot)
  }
}
