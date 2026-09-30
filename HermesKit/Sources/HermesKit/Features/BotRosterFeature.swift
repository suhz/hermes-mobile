import ComposableArchitecture
import Foundation

/// The Bot Mode roster: one row per Hermes profile. Tap opens that profile's canonical
/// `"Bot Chat"` (adopt-before-mint, fail-closed). Create reuses ``AddProfileFeature``
/// via ``Delegate/addBot`` — this reducer does not own the sheet.
@Reducer
public struct BotRosterFeature {
  @ObservableState
  public struct State: Equatable {
    public var connection: ServerConnection
    public var profiles: IdentifiedArrayOf<Profile>
    public var isLoading: Bool
    public var loadError: String?
    /// Profile whose Bot Chat open is in flight — double-tap guard.
    public var openingProfileName: String?

    public init(
      connection: ServerConnection,
      profiles: IdentifiedArrayOf<Profile> = [],
      isLoading: Bool = false,
      loadError: String? = nil,
      openingProfileName: String? = nil
    ) {
      self.connection = connection
      self.profiles = profiles
      self.isLoading = isLoading
      self.loadError = loadError
      self.openingProfileName = openingProfileName
    }
  }

  public enum Action {
    case task
    case pulledToRefresh
    case profilesResponse(Result<[Profile], RESTError>)
    case botTapped(name: String)
    /// Open a just-created profile: mint is allowed even without `include_hidden`.
    case openCreatedBot(name: String)
    case openResolved(
      name: String,
      allowMintWithoutHidden: Bool,
      Result<CanonicalBotChatLookup, CanonicalBotChatError>
    )
    case addBotTapped
    case delegate(Delegate)

    @CasePathable
    public enum Delegate: Equatable {
      /// Resume an existing `"Bot Chat"`.
      case openBotChat(session: Session, profileName: String)
      /// Registry miss after a successful lookup — seat `ChatFeature` to mint.
      case mintBotChat(profileName: String)
      /// Present the existing Add-profile sheet.
      case addBot
    }
  }

  private enum CancelID { case profiles, open }

  @Dependency(\.hermesProfiles) var profiles
  @Dependency(\.canonicalBotChat) var canonicalBotChat

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task, .pulledToRefresh:
        state.isLoading = true
        state.loadError = nil
        return .run { [profiles, connection = state.connection] send in
          do {
            let result = try await profiles.list(connection)
            await send(.profilesResponse(.success(result)))
          } catch let error as RESTError {
            await send(.profilesResponse(.failure(error)))
          } catch {
            await send(.profilesResponse(.failure(.unreachable)))
          }
        }
        .cancellable(id: CancelID.profiles, cancelInFlight: true)

      case let .profilesResponse(.success(result)):
        state.isLoading = false
        state.profiles = IdentifiedArray(result, uniquingIDsWith: { first, _ in first })
        return .none

      case let .profilesResponse(.failure(error)):
        state.isLoading = false
        state.loadError = error.message
        return .none

      case let .botTapped(name):
        return open(name, allowMintWithoutHidden: false, into: &state)

      case let .openCreatedBot(name):
        return open(name, allowMintWithoutHidden: true, into: &state)

      case let .openResolved(name, allowMintWithoutHidden, .success(lookup)):
        state.openingProfileName = nil
        switch CanonicalBotChat.resolve(lookup, allowMintWithoutHidden: allowMintWithoutHidden) {
        case let .success(.adopt(session)):
          return .send(.delegate(.openBotChat(session: session, profileName: name)))
        case .success(.mint):
          return .send(.delegate(.mintBotChat(profileName: name)))
        case let .failure(error):
          state.loadError = error.message
          return .none
        }

      case let .openResolved(_, _, .failure(error)):
        state.openingProfileName = nil
        state.loadError = error.message
        return .none

      case .addBotTapped:
        return .send(.delegate(.addBot))

      case .delegate:
        return .none
      }
    }
  }

  private func open(
    _ name: String,
    allowMintWithoutHidden: Bool,
    into state: inout State
  ) -> Effect<Action> {
    // `openCreatedBot` runs before the roster refresh lands — skip the membership
    // check there. A tap still requires the row to exist.
    if !allowMintWithoutHidden, state.profiles[id: name] == nil {
      state.loadError = CanonicalBotChatError.profileMissing.message
      return .none
    }
    guard state.openingProfileName == nil else { return .none }
    state.openingProfileName = name
    state.loadError = nil
    return .run { [canonicalBotChat, connection = state.connection] send in
      do {
        let lookup = try await canonicalBotChat.lookup(connection, name)
        await send(.openResolved(name: name, allowMintWithoutHidden: allowMintWithoutHidden, .success(lookup)))
      } catch {
        await send(.openResolved(name: name, allowMintWithoutHidden: allowMintWithoutHidden, .failure(.lookupFailed)))
      }
    }
    .cancellable(id: CancelID.open, cancelInFlight: true)
  }
}
