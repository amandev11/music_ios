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

    var isIdle: Bool { title.isEmpty }
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), title: "Music", artist: "Nothing playing", playing: false, artwork: nil)
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
        func finish(_ img: UIImage?) {
            done(NowPlayingEntry(date: Date(), title: title, artist: artist, playing: playing, artwork: img))
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

    private var title: String { entry.isIdle ? "Music" : entry.title }
    private var subtitle: String { entry.isIdle ? "Nothing playing" : entry.artist }
    private var symbol: String { entry.playing ? "pause.fill" : "play.fill" }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.isIdle ? "Music" : "\(entry.title) · \(entry.artist)")
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

@main
struct AuroraNowPlaying: Widget {
    let kind = "AuroraNowPlaying"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            if #available(iOS 17.0, *) {
                NowPlayingView(entry: entry)
                    .foregroundColor(.white)
                    .containerBackground(for: .widget) { GlassBackground(image: entry.artwork) }
            } else {
                NowPlayingView(entry: entry)
                    .foregroundColor(.white)
                    .padding()
                    .background(GlassBackground(image: entry.artwork))
            }
        }
        .configurationDisplayName("Now Playing")
        .description("The song that is playing, on your Home Screen and Lock Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
