import AVFoundation
import FlutterMacOS

/// Decodes a song (URL or file) to mono 16-bit PCM at a low sample rate for Automix's tempo/key analysis.
/// The file is downloaded first, then read with AVAssetReader (reading straight from HTTP is unreliable).
public class AuroraPcmPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "aurora/pcm", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(AuroraPcmPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
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
