import Foundation
import Testing

@testable import HermesKit

struct CanonicalBotChatTests {
  private func session(_ id: String, title: String?) -> Session {
    Session(id: id, title: title)
  }

  @Test func matchesExactTitleOnly() {
    #expect(CanonicalBotChat.matches(session("a", title: "Bot Chat")))
    #expect(!CanonicalBotChat.matches(session("b", title: "Bot chat")))
    #expect(!CanonicalBotChat.matches(session("c", title: " Bot Chat")))
    #expect(!CanonicalBotChat.matches(session("d", title: "Untitled")))
    #expect(!CanonicalBotChat.matches(session("e", title: nil)))
  }

  @Test func adoptTakesFirstExactMatch() {
    let sessions = [
      session("side", title: "Notes"),
      session("bot-1", title: "Bot Chat"),
      session("bot-2", title: "Bot Chat"),
    ]
    #expect(CanonicalBotChat.adopt(from: sessions)?.id == "bot-1")
    #expect(CanonicalBotChat.adopt(from: [session("x", title: "Hello")]) == nil)
  }

  @Test func resolveAdoptsBeforeMinting() {
    let lookup = CanonicalBotChatLookup(
      sessions: [session("bot", title: "Bot Chat")],
      includeHiddenSupported: true
    )
    let result = CanonicalBotChat.resolve(lookup)
    guard case let .success(.adopt(session)) = result else {
      Issue.record("expected adopt, got \(result)")
      return
    }
    #expect(session.id == "bot")
  }

  @Test func resolveMintsWhenHiddenListIsEmpty() {
    let lookup = CanonicalBotChatLookup(sessions: [], includeHiddenSupported: true)
    let result = CanonicalBotChat.resolve(lookup)
    guard case .success(.mint) = result else {
      Issue.record("expected mint, got \(result)")
      return
    }
  }

  @Test func resolveAdoptsFromVisibleListWithoutHiddenSupport() {
    let lookup = CanonicalBotChatLookup(
      sessions: [session("visible", title: "Bot Chat")],
      includeHiddenSupported: false
    )
    let result = CanonicalBotChat.resolve(lookup)
    guard case let .success(.adopt(session)) = result else {
      Issue.record("expected adopt, got \(result)")
      return
    }
    #expect(session.id == "visible")
  }

  @Test func resolveFailClosedWhenHiddenUnsupportedAndMissing() {
    let lookup = CanonicalBotChatLookup(sessions: [], includeHiddenSupported: false)
    let result = CanonicalBotChat.resolve(lookup)
    guard case .failure(.cannotVerifyUniqueness) = result else {
      Issue.record("expected fail-closed, got \(result)")
      return
    }
  }

  @Test func resolveAllowsMintWithoutHiddenForJustCreatedProfile() {
    let lookup = CanonicalBotChatLookup(sessions: [], includeHiddenSupported: false)
    let result = CanonicalBotChat.resolve(lookup, allowMintWithoutHidden: true)
    guard case .success(.mint) = result else {
      Issue.record("expected mint for just-created profile, got \(result)")
      return
    }
  }

  @Test func resolveIgnoresNearMissTitles() {
    let lookup = CanonicalBotChatLookup(
      sessions: [
        session("a", title: "Bot chat"),
        session("b", title: "My Bot Chat"),
        session("c", title: nil),
      ],
      includeHiddenSupported: true
    )
    let result = CanonicalBotChat.resolve(lookup)
    guard case .success(.mint) = result else {
      Issue.record("near-miss titles must not adopt, got \(result)")
      return
    }
  }
}
