import AppIntents
import Foundation

/// Siri / Shortcuts support: "Hey Siri, play <song> on Music". Uses App Intents (iOS 16+), which needs no
/// special entitlement, so it works in sideloaded builds with a free Apple ID.
enum AuroraSiri {
  static let key = "aurora.siri.query"
  static let note = Notification.Name("AuroraSiriQuery")

  static func send(_ query: String) {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return }
    UserDefaults.standard.set(q, forKey: key)
    UserDefaults.standard.synchronize()
    NotificationCenter.default.post(name: note, object: q)
  }
}

@available(iOS 16.0, *)
struct SongEntity: AppEntity {
  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Song")
  static var defaultQuery = SongEntityQuery()
  var id: String
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: LocalizedStringResource(stringLiteral: id)) }
}

/// Free-form: whatever Siri heard becomes the search text.
@available(iOS 16.0, *)
struct SongEntityQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [SongEntity] { identifiers.map { SongEntity(id: $0) } }
  func entities(matching string: String) async throws -> [SongEntity] { [SongEntity(id: string)] }
  func suggestedEntities() async throws -> [SongEntity] { [] }
}

@available(iOS 16.0, *)
struct PlaySongIntent: AppIntent {
  static var title: LocalizedStringResource = "Play a song"
  static var description = IntentDescription("Searches for a song or artist and plays it.")
  static var openAppWhenRun: Bool = true

  @Parameter(title: "Song", requestValueDialog: "Which song?")
  var song: SongEntity

  static var parameterSummary: some ParameterSummary { Summary("Play \(\.$song)") }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    AuroraSiri.send(song.id)
    return .result(dialog: "Playing \(song.id)")
  }
}

/// "Play music on Music": Siri asks which song, then plays it.
@available(iOS 16.0, *)
struct PlayAskIntent: AppIntent {
  static var title: LocalizedStringResource = "Play music"
  static var openAppWhenRun: Bool = true

  @Parameter(title: "Song or artist", requestValueDialog: "Which song or artist?")
  var query: String

  func perform() async throws -> some IntentResult & ProvidesDialog {
    AuroraSiri.send(query)
    return .result(dialog: "Playing \(query)")
  }
}

@available(iOS 16.0, *)
struct AuroraShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: PlaySongIntent(),
      phrases: [
        "Play \(\.$song) on \(.applicationName)",
        "Play \(\.$song) in \(.applicationName)",
        "\(.applicationName) play \(\.$song)",
      ],
      shortTitle: "Play a song",
      systemImageName: "play.circle.fill"
    )
    AppShortcut(
      intent: PlayAskIntent(),
      phrases: [
        "Play music on \(.applicationName)",
        "Play a song on \(.applicationName)",
        "Search \(.applicationName)",
        "Open \(.applicationName) and play",
      ],
      shortTitle: "Play music",
      systemImageName: "music.note"
    )
  }
}
