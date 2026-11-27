import ActivityKit
import Foundation
import UIKit

/// Must match the copy in AuroraWidget.swift field for field: ActivityKit pairs the two by name and shape.
struct KeystoneAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var title: String
    var artist: String
    var playing: Bool
    var artVersion: Int
  }
  var name: String
}

/// Lock Screen / Dynamic Island "now playing" poster. iOS does not let an app draw live visuals on the
/// Lock Screen or Always-On Display; a Live Activity is the supported surface, and it stays on the
/// dimmed Always-On Display. Called by the aurora_pcm plugin by class name, with a dictionary.
@objc(KeystoneLiveActivityBridge)
final class KeystoneLiveActivityBridge: NSObject {
  private static var version = 0
  private static var lastArt = ""

  @objc static func update(_ info: NSDictionary) {
    guard #available(iOS 16.2, *) else { return }
    let title = info["title"] as? String ?? ""
    let artist = info["artist"] as? String ?? ""
    let playing = info["playing"] as? Bool ?? false
    let art = info["art"] as? String ?? ""
    let group = info["group"] as? String ?? ""
    Task { await KSLive.apply(title: title, artist: artist, playing: playing, art: art, group: group) }
  }

  @available(iOS 16.2, *)
  fileprivate enum KSLive {
    static var activity: Activity<KeystoneAttributes>?

    static func apply(title: String, artist: String, playing: Bool, art: String, group: String) async {
      guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
      if title.isEmpty {
        await end()
        return
      }
      if art != KeystoneLiveActivityBridge.lastArt {
        KeystoneLiveActivityBridge.lastArt = art
        await saveArtwork(art, group: group)
        KeystoneLiveActivityBridge.version += 1
      }
      let state = KeystoneAttributes.ContentState(
        title: title, artist: artist, playing: playing, artVersion: KeystoneLiveActivityBridge.version)
      if activity == nil { activity = Activity<KeystoneAttributes>.activities.first }
      if let a = activity {
        await a.update(ActivityContent(state: state, staleDate: nil))
      } else {
        activity = try? Activity.request(
          attributes: KeystoneAttributes(name: "Keystone"),
          content: ActivityContent(state: state, staleDate: nil),
          pushType: nil)
      }
    }

    static func end() async {
      for a in Activity<KeystoneAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
      activity = nil
    }

    /// Live Activities cannot load images from the network, so the cover is saved to the shared container.
    static func saveArtwork(_ art: String, group: String) async {
      guard !group.isEmpty,
            let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return }
      let file = dir.appendingPathComponent("liveart.jpg")
      guard let url = URL(string: art), art.hasPrefix("http") else {
        try? FileManager.default.removeItem(at: file)
        return
      }
      var req = URLRequest(url: url)
      req.timeoutInterval = 8
      if let (data, _) = try? await URLSession.shared.data(for: req), let img = UIImage(data: data),
         let jpg = img.jpegData(compressionQuality: 0.85) {
        try? jpg.write(to: file, options: .atomic)
      }
    }
  }
}
