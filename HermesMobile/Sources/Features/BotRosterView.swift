import ComposableArchitecture
import HermesKit
import SwiftUI

/// Bot Mode roster: one row per Hermes profile. Tap opens that bot's canonical Bot Chat.
struct BotRosterView: View {
  @Bindable var store: StoreOf<BotRosterFeature>

  var body: some View {
    List {
      if let error = store.loadError {
        Label(error, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
          .listRowSeparator(.hidden)
      }
      ForEach(store.profiles) { profile in
        Button {
          store.send(.botTapped(name: profile.name))
        } label: {
          HStack(spacing: 12) {
            Image(systemName: profile.isDefault ? "house.fill" : "person.crop.circle.fill")
              .font(.title2)
              .foregroundStyle(Color.hermesAccent)
              .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
              Text(profile.rosterTitle)
                .fontWeight(.semibold)
                .lineLimit(1)
              if let subtitle = rosterSubtitle(profile) {
                Text(subtitle)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
            }
            Spacer()
            if store.openingProfileName == profile.name {
              ProgressView()
            } else {
              Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.openingProfileName != nil)
        .listRowSeparator(.hidden)
        .accessibilityLabel(profile.rosterTitle)
        .accessibilityHint("Opens this bot’s Bot Chat")
      }
    }
    .listStyle(.plain)
    .overlay {
      if store.profiles.isEmpty, !store.isLoading, store.loadError == nil {
        ContentUnavailableView(
          "No bots",
          systemImage: "person.2",
          description: Text("A bot is a Hermes profile. Add one to start a Bot Chat.")
        )
      }
    }
    .refreshable { store.send(.pulledToRefresh) }
    .task { store.send(.task) }
  }

  private func rosterSubtitle(_ profile: Profile) -> String? {
    if let description = profile.description?.trimmingCharacters(in: .whitespacesAndNewlines),
       !description.isEmpty {
      return description
    }
    switch (profile.model, profile.provider) {
    case let (model?, provider?): return "\(model) · \(provider)"
    case let (model?, nil): return model
    case let (nil, provider?): return provider
    case (nil, nil): return profile.isDefault ? "Default profile" : nil
    }
  }
}
