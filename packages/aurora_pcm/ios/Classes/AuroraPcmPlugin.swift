import AVFoundation
import Flutter

/// Decodes a song (URL or file) to mono 16-bit PCM at a low sample rate for Automix's tempo/key analysis.
/// The file is downloaded first, then read with AVAssetReader (reading straight from HTTP is unreliable).
public class AuroraPcmPlugin: NSObject, FlutterPlugin {
  private static var sharedPlugin: AuroraPcmPlugin?
  private var channel: FlutterMethodChannel?
  private var siriObserver: NSObjectProtocol?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "aurora/pcm", binaryMessenger: registrar.messenger())
    let plugin = AuroraPcmPlugin()
    plugin.channel = channel
    registrar.addMethodCallDelegate(plugin, channel: channel)
    // Siri hands the spoken song over by notification (app already running) or UserDefaults (cold start).
    plugin.siriObserver = NotificationCenter.default.addObserver(forName: Notification.Name("AuroraSiriQuery"), object: nil, queue: .main) { [weak plugin] n in
      guard let q = n.object as? String else { return }
      plugin?.channel?.invokeMethod("siri", arguments: q) { r in
        if (r as? Bool) == true { UserDefaults.standard.removeObject(forKey: "aurora.siri.query") }
      }
    }
    sharedPlugin = plugin

    // Native playback engine (see AuroraAudioEngine.swift).
    let audio = FlutterMethodChannel(name: "aurora/ios_audio", binaryMessenger: registrar.messenger())
    audio.setMethodCallHandler { call, result in AuroraAudio.shared.handle(call, result) }
    let events = FlutterEventChannel(name: "aurora/ios_audio/events", binaryMessenger: registrar.messenger())
    events.setStreamHandler(AuroraAudio.shared)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "appGroup" {
      result(AppGroups.best())
      return
    }
    if call.method == "takeSiri" {
      let q = UserDefaults.standard.string(forKey: "aurora.siri.query")
      UserDefaults.standard.removeObject(forKey: "aurora.siri.query")
      result(q)
      return
    }
    guard call.method == "decode", let a = call.arguments as? [String: Any], let source = a["url"] as? String else {
      result(FlutterMethodNotImplemented)
      return
    }
    let headers = a["headers"] as? [String: String] ?? [:]
    let rate = (a["sampleRate"] as? Int) ?? 11025
    let maxSeconds = (a["maxSeconds"] as? Int) ?? 900
    DispatchQueue.global(qos: .utility).async {
      let data = AuroraPcm.decode(source: source, headers: headers, sampleRate: rate, maxSeconds: maxSeconds)
      DispatchQueue.main.async { result(data.map { FlutterStandardTypedData(bytes: $0) }) }
    }
  }
}

enum AuroraPcm {
  static func decode(source: String, headers: [String: String], sampleRate: Int, maxSeconds: Int) -> Data? {
    var tempFile: URL?
    defer { if let f = tempFile { try? FileManager.default.removeItem(at: f) } }

    let fileURL: URL
    if source.hasPrefix("http://") || source.hasPrefix("https://") {
      guard let url = URL(string: source), let downloaded = download(url, headers: headers) else { return nil }
      tempFile = downloaded
      fileURL = downloaded
    } else if source.hasPrefix("file://"), let url = URL(string: source) {
      fileURL = url
    } else {
      fileURL = URL(fileURLWithPath: source)
    }

    let asset = AVURLAsset(url: fileURL)
    guard let track = loadAudioTrack(asset) else { return nil }
    guard let reader = try? AVAssetReader(asset: asset) else { return nil }
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
    guard reader.canAdd(output) else { return nil }
    reader.add(output)
    guard reader.startReading() else { return nil }

    var pcm = Data()
    let cap = maxSeconds * sampleRate * 2
    while let buffer = output.copyNextSampleBuffer() {
      if let block = CMSampleBufferGetDataBuffer(buffer) {
        let length = CMBlockBufferGetDataLength(block)
        var chunk = Data(count: length)
        let status = chunk.withUnsafeMutableBytes { ptr -> OSStatus in
          guard let base = ptr.baseAddress else { return -1 }
          return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
        }
        if status == kCMBlockBufferNoErr { pcm.append(chunk) }
      }
      CMSampleBufferInvalidate(buffer)
      if pcm.count >= cap { break }
    }
    if reader.status == .failed { return nil }
    return pcm.count > sampleRate * 2 * 20 ? pcm : nil
  }

  private static func loadAudioTrack(_ asset: AVURLAsset) -> AVAssetTrack? {
    let sem = DispatchSemaphore(value: 0)
    asset.loadValuesAsynchronously(forKeys: ["tracks"]) { sem.signal() }
    _ = sem.wait(timeout: .now() + 20)
    return asset.tracks(withMediaType: .audio).first
  }

  /// Downloads to a temp file whose extension matches the content type, because AVFoundation sniffs by extension.
  private static func download(_ url: URL, headers: [String: String]) -> URL? {
    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
    let sem = DispatchSemaphore(value: 0)
    var out: URL?
    let task = URLSession.shared.downloadTask(with: request) { location, response, error in
      defer { sem.signal() }
      guard error == nil, let location = location, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
      let mime = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
      if mime.contains("webm") || mime.contains("ogg") || mime.contains("opus") { return } // AVFoundation cannot decode these
      var ext = url.pathExtension.lowercased()
      if mime.contains("mpeg") { ext = "mp3" }
      else if mime.contains("mp4") || mime.contains("m4a") { ext = "m4a" }
      else if mime.contains("aac") { ext = "aac" }
      else if mime.contains("wav") { ext = "wav" }
      else if mime.contains("flac") { ext = "flac" }
      if ext.isEmpty || ext.count > 5 { ext = "m4a" }
      let dest = FileManager.default.temporaryDirectory.appendingPathComponent("amx-\(UUID().uuidString).\(ext)")
      do {
        try FileManager.default.moveItem(at: location, to: dest)
        out = dest
      } catch {}
    }
    task.resume()
    if sem.wait(timeout: .now() + 60) == .timedOut {
      task.cancel()
      return nil
    }
    return out
  }
}


/// Finds the App Group this install really owns. Sideloading tools rename the group per Apple ID, so look in
/// the embedded provisioning profile (the truth), then ALTAppGroups, then the default; prefer one whose
/// shared container actually exists.
enum AppGroups {
  static let fallback = "group.com.aurora.music"

  static func candidates() -> [String] {
    var out: [String] = []
    func add(_ g: [String]?) { for x in g ?? [] where !out.contains(x) { out.append(x) } }
    // Main app bundle (the widget lives in PlugIns/ inside it).
    let main = Bundle.main.bundleURL.pathExtension == "appex"
      ? Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
      : Bundle.main.bundleURL
    for url in [Bundle.main.bundleURL, main] {
      add(fromProfile(url.appendingPathComponent("embedded.mobileprovision")))
      add(Bundle(url: url)?.object(forInfoDictionaryKey: "ALTAppGroups") as? [String])
    }
    add([fallback])
    return out
  }

  static func best() -> String {
    let all = candidates()
    return all.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil } ?? all.first ?? fallback
  }

  private static func fromProfile(_ url: URL) -> [String]? {
    guard let data = try? Data(contentsOf: url),
          let start = data.range(of: Data("<?xml".utf8)),
          let end = data.range(of: Data("</plist>".utf8)) else { return nil }
    let xml = data.subdata(in: start.lowerBound..<end.upperBound)
    guard let plist = try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil) as? [String: Any],
          let ents = plist["Entitlements"] as? [String: Any] else { return nil }
    return ents["com.apple.security.application-groups"] as? [String]
  }
}
