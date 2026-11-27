import ActivityKit
import SwiftUI
import WidgetKit

/// Sideloading tools (AltStore and similar) rename the App Group per Apple ID. The embedded provisioning
/// profile lists the group this install really owns; ALTAppGroups is the second source. The first group whose
/// shared container exists wins.
private func groupCandidates() -> [String] {
    var out: [String] = []
    func add(_ g: [String]?) { for x in g ?? [] where !out.contains(x) { out.append(x) } }
    func profile(_ url: URL) -> [String]? {
        guard let data = try? Data(contentsOf: url),
              let s = data.range(of: Data("<?xml".utf8)), let e = data.range(of: Data("</plist>".utf8)),
              let plist = try? PropertyListSerialization.propertyList(from: data.subdata(in: s.lowerBound..<e.upperBound), options: [], format: nil) as? [String: Any],
              let ents = plist["Entitlements"] as? [String: Any] else { return nil }
        return ents["com.apple.security.application-groups"] as? [String]
    }
    let host = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent() // Runner.app
    for url in [Bundle.main.bundleURL, host] {
        add(profile(url.appendingPathComponent("embedded.mobileprovision")))
        add(Bundle(url: url)?.object(forInfoDictionaryKey: "ALTAppGroups") as? [String])
    }
    add(["group.com.aurora.music"])
    return out
}

private func resolveAppGroup() -> String {
    let all = groupCandidates()
    return all.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil } ?? all.first ?? "group.com.aurora.music"
}

private let appGroup = resolveAppGroup()

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let playing: Bool
    let artwork: UIImage?
    var theme: String = "classic"

    var isIdle: Bool { title.isEmpty }
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), title: "Keystone", artist: "Nothing playing", playing: false, artwork: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        load { completion($0) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        load { entry in
            // The app reloads the timeline on every change; this is only a safety refresh.
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }

    private func load(_ done: @escaping (NowPlayingEntry) -> Void) {
        // No shared container means the install lost its App Group entitlement: say so instead of looking broken.
        if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) == nil {
            return done(NowPlayingEntry(date: Date(), title: "Setup needed", artist: "App Group missing (\(groupCandidates().count) tried)", playing: false, artwork: nil))
        }
        let d = UserDefaults(suiteName: appGroup)
        let title = d?.string(forKey: "title") ?? ""
        let artist = d?.string(forKey: "artist") ?? ""
        let playing = d?.bool(forKey: "playing") ?? false
        let art = d?.string(forKey: "art") ?? ""
        let theme = d?.string(forKey: "theme") ?? "classic"
        func finish(_ img: UIImage?) {
            done(NowPlayingEntry(date: Date(), title: title, artist: artist, playing: playing, artwork: img, theme: theme))
        }
        guard !title.isEmpty, let url = URL(string: art), !art.isEmpty else { return finish(nil) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        URLSession.shared.dataTask(with: req) { data, _, _ in
            finish(data.flatMap { UIImage(data: $0) })
        }.resume()
    }
}

private struct Art: View {
    let image: UIImage?
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color(white: 0.17)
                    Image(systemName: "music.note").foregroundColor(.white.opacity(0.4)).font(.title2)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct NowPlayingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowPlayingEntry

    private var title: String { entry.isIdle ? "Keystone" : entry.title }
    private var subtitle: String { entry.isIdle ? "Nothing playing" : entry.artist }
    private var symbol: String { entry.playing ? "pause.fill" : "play.fill" }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.isIdle ? "Keystone" : "\(entry.title) · \(entry.artist)")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: entry.playing ? "waveform" : "music.note").font(.title3)
            }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline).lineLimit(1)
                    Text(subtitle).font(.caption).lineLimit(1).opacity(0.8)
                }
                Spacer(minLength: 0)
            }
        case .systemMedium:
            HStack(spacing: 14) {
                Art(image: entry.artwork).aspectRatio(1, contentMode: .fit)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).lineLimit(2)
                    Text(subtitle).font(.subheadline).foregroundColor(.white.opacity(0.7)).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: symbol).font(.title3)
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Art(image: entry.artwork).aspectRatio(1, contentMode: .fit)
                Text(title).font(.footnote.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.caption2).foregroundColor(.white.opacity(0.7)).lineLimit(1)
            }
        }
    }
}

/// Frosted-glass backdrop: the artwork, blown up and blurred, under a thin material and a soft rim light.
struct GlassBackground: View {
    let image: UIImage?
    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill().blur(radius: 28).saturation(1.3)
            } else {
                LinearGradient(colors: [Color(white: 0.24), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// The six looks chosen in Appearance > Widget Theme.
struct ThemedBackground: View {
    let theme: String
    let image: UIImage?
    var body: some View {
        switch theme {
        case "minimal":
            Color(red: 0.04, green: 0.04, blue: 0.05)
        case "gradient":
            LinearGradient(colors: [Color(red: 0.48, green: 0.18, blue: 0.9), Color(red: 0.18, green: 0.36, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "glass":
            ZStack {
                LinearGradient(colors: [Color(white: 0.22), Color(white: 0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Rectangle().fill(.ultraThinMaterial)
            }
        case "vinyl":
            LinearGradient(colors: [Color(red: 0.09, green: 0.07, blue: 0.06), Color(red: 0.05, green: 0.04, blue: 0.035)], startPoint: .top, endPoint: .bottom)
        case "neon":
            ZStack {
                Color.black
                LinearGradient(colors: [Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.22), Color.clear], startPoint: .topTrailing, endPoint: .bottomLeading)
            }
        default:
            GlassBackground(image: image)
        }
    }
}

struct AuroraNowPlaying: Widget {
    let kind = "AuroraNowPlaying"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            if #available(iOS 17.0, *) {
                NowPlayingView(entry: entry)
                    .foregroundColor(.white)
                    .containerBackground(for: .widget) { ThemedBackground(theme: entry.theme, image: entry.artwork) }
            } else {
                NowPlayingView(entry: entry)
                    .foregroundColor(.white)
                    .padding()
                    .background(ThemedBackground(theme: entry.theme, image: entry.artwork))
            }
        }
        .configurationDisplayName("Now Playing")
        .description("The song that is playing, on your Home Screen and Lock Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Lock Screen poster (Live Activity)

/// Same shape as the copy in the app target (Runner/KeystoneLiveActivity.swift).
struct KeystoneAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var playing: Bool
        var artVersion: Int
    }
    var name: String
}

private func liveArt() -> UIImage? {
    guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
    return UIImage(contentsOfFile: dir.appendingPathComponent("liveart.jpg").path)
}

@available(iOS 16.2, *)
private struct LivePoster: View {
    let state: KeystoneAttributes.ContentState

    var body: some View {
        let art = liveArt()
        ZStack {
            // The cover, blown up and blurred, becomes the poster background.
            if let art {
                Image(uiImage: art).resizable().scaledToFill().blur(radius: 38).opacity(0.9)
            } else {
                LinearGradient(colors: [Color(white: 0.2), .black], startPoint: .top, endPoint: .bottom)
            }
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            HStack(spacing: 16) {
                Group {
                    if let art {
                        Image(uiImage: art).resizable().scaledToFill()
                    } else {
                        ZStack { Color(white: 0.2); Image(systemName: "music.note").foregroundColor(.white.opacity(0.5)).font(.title) }
                    }
                }
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text("KEYSTONE").font(.system(size: 10, weight: .bold)).tracking(2).foregroundColor(.white.opacity(0.6))
                    Text(state.title).font(.system(size: 20, weight: .heavy)).lineLimit(2).foregroundColor(.white)
                    Text(state.artist).font(.system(size: 14, weight: .medium)).lineLimit(1).foregroundColor(.white.opacity(0.75))
                    Spacer(minLength: 0)
                    EqBars(active: state.playing)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }
}

/// Four bars that move while a song plays (a symbol effect on iOS 17, still bars before that).
@available(iOS 16.2, *)
private struct EqBars: View {
    let active: Bool
    var body: some View {
        if #available(iOS 17.0, *) {
            Image(systemName: "waveform")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .symbolEffect(.variableColor.iterative, isActive: active)
        } else {
            Image(systemName: active ? "waveform" : "pause.fill").font(.system(size: 20)).foregroundColor(.white)
        }
    }
}

@available(iOS 16.2, *)
struct KeystoneLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KeystoneAttributes.self) { context in
            LivePoster(state: context.state)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let art = liveArt() {
                        Image(uiImage: art).resizable().scaledToFill().frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading) {
                        Text(context.state.title).font(.headline).lineLimit(1)
                        Text(context.state.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) { EqBars(active: context.state.playing) }
            } compactLeading: {
                if let art = liveArt() {
                    Image(uiImage: art).resizable().scaledToFill().frame(width: 22, height: 22).clipShape(Circle())
                } else {
                    Image(systemName: "music.note")
                }
            } compactTrailing: {
                EqBars(active: context.state.playing)
            } minimal: {
                Image(systemName: context.state.playing ? "waveform" : "pause.fill")
            }
        }
    }
}

@main
struct KeystoneWidgets: WidgetBundle {
    var body: some Widget {
        AuroraNowPlaying()
        if #available(iOS 16.2, *) { KeystoneLiveActivity() }
    }
}
