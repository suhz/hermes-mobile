import Foundation

/// The home sidebar's presentation mode. Sessions is the existing list; Bots is the
/// Bot Mode roster (one row per Hermes profile). Device-local / in-memory only —
/// not persisted, so logout has nothing extra to clear.
public enum HomeMode: String, Equatable, Sendable, CaseIterable {
  case sessions
  case bots
}
