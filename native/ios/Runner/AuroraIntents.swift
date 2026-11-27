import AppIntents
import Foundation

/// Siri / Shortcuts support: "Hey Siri, play <song> on Music". Uses App Intents (iOS 16+), which needs no
/// special entitlement, so it works in sideloaded builds with a free Apple ID.
enum AuroraSiri {
  static let key = "aurora.siri.query"
  static let note = Notification.Name("AuroraSiriQuery")

  /// One command for the Flutter side: {"cmd": play|pause|resume|next|previous|like|shuffle|liked|playlist, "q": text}.
  static func send(_ cmd: String, _ q: String = "", title: String = "") {
    let text = q.trimmingCharacters(in: .whitespacesAndNewlines)
    if (cmd == "play" || cmd == "track") && text.isEmpty { return }
    guard let data = try? JSONSerialization.data(withJSONObject: ["cmd": cmd, "q": text, "t": title]),
          let json = String(data: data, encoding: .utf8) else { return }
    UserDefaults.standard.set(json, forKey: key)
    UserDefaults.standard.synchronize()
    NotificationCenter.default.post(name: note, object: json)
  }

  /// What is playing, written by the app so Siri can read it out.
  static var nowPlaying: String { UserDefaults.standard.string(forKey: "aurora.siri.now") ?? "" }
}

/// The songs, artists and playlists the app last reported (library, liked, recent, downloads). Siri can only
/// recognise a spoken name that is in this list, so the app refreshes it as the library changes.
enum AuroraCatalog {
  static func load() -> (songs: [[String]], artists: [String], playlists: [String]) {
    guard let raw = UserDefaults.standard.string(forKey: "aurora.siri.catalog"),
          let data = raw.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ([], [], []) }
    return (obj["songs"] as? [[String]] ?? [], obj["artists"] as? [String] ?? [], obj["playlists"] as? [String] ?? [])
  }
  static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
}

/// Called by the plugin after the app saved a new catalog, so Siri re-reads the spoken-name vocabulary.
@objc(AuroraSiriRefresher)
final class AuroraSiriRefresher: NSObject {
  @objc static func refresh() {
    if #available(iOS 16.0, *) { AuroraShortcuts.updateAppShortcutParameters() }
  }
}

@available(iOS 16.0, *)
struct SongEntity: AppEntity {
  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Song")
  static var defaultQuery = SongEntityQuery()
  var id: String
  var title: String
  var artist: String
  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: LocalizedStringResource(stringLiteral: title),
      subtitle: artist.isEmpty ? nil : LocalizedStringResource(stringLiteral: artist))
  }
}

@available(iOS 16.0, *)
struct SongEntityQuery: EntityStringQuery {
  private func all() -> [SongEntity] {
    AuroraCatalog.load().songs.compactMap { $0.count >= 2 ? SongEntity(id: $0[0], title: $0[1], artist: $0.count > 2 ? $0[2] : "") : nil }
  }
  func entities(for identifiers: [String]) async throws -> [SongEntity] {
    let known = all()
    return identifiers.map { id in
      known.first(where: { $0.id == id }) ?? SongEntity(id: id, title: id.hasPrefix("q:") ? String(id.dropFirst(2)) : id, artist: "")
    }
  }
  func entities(matching string: String) async throws -> [SongEntity] {
    let q = AuroraCatalog.fold(string)
    let hits = all().filter { AuroraCatalog.fold($0.title).contains(q) || AuroraCatalog.fold($0.artist).contains(q) }
    // Not in the library: still play it, by searching the catalogue for the spoken words.
    return hits.isEmpty ? [SongEntity(id: "q:" + string, title: string, artist: "")] : Array(hits.prefix(25))
  }
  func suggestedEntities() async throws -> [SongEntity] { Array(all().prefix(200)) }
}

@available(iOS 16.0, *)
struct ArtistEntity: AppEntity {
  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Artist")
  static var defaultQuery = ArtistEntityQuery()
  var id: String
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: LocalizedStringResource(stringLiteral: id)) }
}

@available(iOS 16.0, *)
struct ArtistEntityQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [ArtistEntity] { identifiers.map { ArtistEntity(id: $0) } }
  func entities(matching string: String) async throws -> [ArtistEntity] {
    let q = AuroraCatalog.fold(string)
    let hits = AuroraCatalog.load().artists.filter { AuroraCatalog.fold($0).contains(q) }
    return hits.isEmpty ? [ArtistEntity(id: string)] : hits.prefix(15).map { ArtistEntity(id: $0) }
  }
  func suggestedEntities() async throws -> [ArtistEntity] { AuroraCatalog.load().artists.prefix(100).map { ArtistEntity(id: $0) } }
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
    if song.id.hasPrefix("q:") {
      AuroraSiri.send("play", String(song.id.dropFirst(2)))
    } else {
      AuroraSiri.send("track", song.id, title: song.title)
    }
    return .result(dialog: IntentDialog(stringLiteral: "Playing \(song.title)"))
  }
}

@available(iOS 16.0, *)
struct PlayArtistIntent: AppIntent {
  static var title: LocalizedStringResource = "Play an artist"
  static var openAppWhenRun: Bool = true
  @Parameter(title: "Artist", requestValueDialog: "Which artist?")
  var artist: ArtistEntity
  static var parameterSummary: some ParameterSummary { Summary("Play music by \(\.$artist)") }
  func perform() async throws -> some IntentResult & ProvidesDialog {
    AuroraSiri.send("play", artist.id)
    return .result(dialog: IntentDialog(stringLiteral: "Playing \(artist.id)"))
  }
}

/// "Play music on Keystone": Siri asks which song, then plays it.
@available(iOS 16.0, *)
struct PlayAskIntent: AppIntent {
  static var title: LocalizedStringResource = "Play music"
  static var openAppWhenRun: Bool = true

  @Parameter(title: "Song or artist", requestValueDialog: "Which song or artist?")
  var query: String

  func perform() async throws -> some IntentResult & ProvidesDialog {
    AuroraSiri.send("play", query)
    return .result(dialog: "Playing \(query)")
  }
}

@available(iOS 16.0, *)
struct PauseMusicIntent: AppIntent {
  static var title: LocalizedStringResource = "Pause music"
  func perform() async throws -> some IntentResult & ProvidesDialog {
    AuroraSiri.send("pause")
    return .result(dialog: "Paused")
  }
}

@available(iOS 16.0, *)
struct ResumeMusicIntent: AppIntent {
  static var title: LocalizedStringResource = "Play Keystone"
  // Opens the app so the player exists even when it was closed.
  static var openAppWhenRun: Bool = true
  func perform() async throws -> some IntentResult & ProvidesDialog {
    AuroraSiri.send("resume")
    return .result(dialog: "Resuming")
  }
}

@available(iOS 16.0, *)
struct NextSongIntent: AppIntent {
  static var title: LocalizedStringResource = "Next song"
  func perform() async throws -> some IntentResult & ProvidesDialog {
    AuroraSiri.send("next")
    return .result(dialog: "Next song")
  }
}

@available(iOS 16.0, *)
struct PreviousSongIntent: AppIntent {
  static var title: LocalizedStringResource = "Previous song"
  func perform() async throws -> some IntentResult & ProvidesDialog {
    AuroraSiri.send("previous")
    return .result(dialog: "Previous song")
  }
}

@available(iOS 16.0, *)
struct LikeSongIntent: AppIntent {
  static var title: LocalizedStringResource = "Like this song"
  func perform() async throws -> some IntentResult & ProvidesDialog {
    AuroraSiri.send("like")
    return .result(dialog: "Done")
  }
}

@available(iOS 16.0, *)
struct WhatsPlayingIntent: AppIntent {
  static var title: LocalizedStringResource = "What's playing"
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let now = AuroraSiri.nowPlaying
    return .result(dialog: IntentDialog(stringLiteral: now.isEmpty ? "Nothing is playing" : "Playing \(now)"))
  }
}

@available(iOS 16.0, *)
struct PlayLikedIntent: AppIntent {
  static var title: LocalizedStringResource = "Play my liked songs"
  static var openAppWhenRun: Bool = true
  func perform() async throws -> some IntentResult & ProvidesDialog {
    AuroraSiri.send("liked")
    return .result(dialog: "Playing your liked songs")
  }
}

@available(iOS 16.0, *)
struct ShuffleLikedIntent: AppIntent {
  static var title: LocalizedStringResource = "Shuffle my liked songs"
  static var openAppWhenRun: Bool = true
  func perform() async throws -> some IntentResult & ProvidesDialog {
    AuroraSiri.send("shuffle")
    return .result(dialog: "Shuffling your liked songs")
  }
}

@available(iOS 16.0, *)
struct PlaylistEntity: AppEntity {
  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Playlist")
  static var defaultQuery = PlaylistEntityQuery()
  var id: String
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: LocalizedStringResource(stringLiteral: id)) }
}

@available(iOS 16.0, *)
struct PlaylistEntityQuery: EntityStringQuery {
  func entities(for identifiers: [String]) async throws -> [PlaylistEntity] { identifiers.map { PlaylistEntity(id: $0) } }
  func entities(matching string: String) async throws -> [PlaylistEntity] {
    let q = AuroraCatalog.fold(string)
    let hits = AuroraCatalog.load().playlists.filter { AuroraCatalog.fold($0).contains(q) }
    return hits.isEmpty ? [PlaylistEntity(id: string)] : hits.map { PlaylistEntity(id: $0) }
  }
  func suggestedEntities() async throws -> [PlaylistEntity] { AuroraCatalog.load().playlists.map { PlaylistEntity(id: $0) } }
}

@available(iOS 16.0, *)
struct PlayPlaylistIntent: AppIntent {
  static var title: LocalizedStringResource = "Play a playlist"
  static var openAppWhenRun: Bool = true
  @Parameter(title: "Playlist", requestValueDialog: "Which playlist?")
  var playlist: PlaylistEntity
  static var parameterSummary: some ParameterSummary { Summary("Play playlist \(\.$playlist)") }
  func perform() async throws -> some IntentResult & ProvidesDialog {
    AuroraSiri.send("playlist", playlist.id)
    return .result(dialog: "Playing \(playlist.id)")
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
        "Play \(\.$song) with \(.applicationName)",
        "\(.applicationName) play \(\.$song)",
      ],
      shortTitle: "Play a song",
      systemImageName: "play.circle.fill"
    )
    AppShortcut(
      intent: PlayArtistIntent(),
      phrases: [
        "Play music by \(\.$artist) on \(.applicationName)",
        "Play \(\.$artist) songs on \(.applicationName)",
        "Play songs by \(\.$artist) on \(.applicationName)",
      ],
      shortTitle: "Play an artist",
      systemImageName: "person.wave.2.fill"
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
    AppShortcut(intent: ResumeMusicIntent(), phrases: ["Play \(.applicationName)", "Start \(.applicationName)", "Resume \(.applicationName)", "Resume music on \(.applicationName)"], shortTitle: "Play Keystone", systemImageName: "play.fill")
    AppShortcut(intent: PlayLikedIntent(), phrases: ["Play my liked songs on \(.applicationName)", "Shuffle my liked songs on \(.applicationName)", "Play my favourites on \(.applicationName)"], shortTitle: "Liked songs", systemImageName: "heart.fill")
    AppShortcut(intent: PlayPlaylistIntent(), phrases: ["Play playlist \(\.$playlist) on \(.applicationName)"], shortTitle: "Play a playlist", systemImageName: "music.note.list")
    AppShortcut(intent: PauseMusicIntent(), phrases: ["Pause \(.applicationName)", "Pause the music on \(.applicationName)"], shortTitle: "Pause", systemImageName: "pause.fill")
    AppShortcut(intent: NextSongIntent(), phrases: ["Next song on \(.applicationName)", "Skip on \(.applicationName)"], shortTitle: "Next", systemImageName: "forward.fill")
    AppShortcut(intent: LikeSongIntent(), phrases: ["Like this song on \(.applicationName)"], shortTitle: "Like", systemImageName: "heart")
    AppShortcut(intent: WhatsPlayingIntent(), phrases: ["What's playing on \(.applicationName)"], shortTitle: "What's playing", systemImageName: "waveform")
  }
}
