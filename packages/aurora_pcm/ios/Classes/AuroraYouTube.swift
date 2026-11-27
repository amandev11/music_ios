import Foundation

/// YouTube audio resolver, entirely native (URLSession), following the client strategy Metrolist's `innertubex`
/// uses (benchmarks Aug-Nov 2026): VISIONOS 0.1 on the YouTube Music player endpoint first (no PO token, needs a
/// real visitorData), the two Android VR profiles after it. The player request and the download both run in this
/// one process and network stack, so the stream links (which YouTube binds to the requester) are used by the same
/// client that asked for them; the earlier Dart-asks / native-downloads split was refused with HTTP 403.
///
/// A client that failed for a video is skipped for five minutes (Metrolist's health tracking), and a download that
/// is refused moves on to the next client instead of giving up.
final class AuroraYT {
  static let shared = AuroraYT()

  struct Client {
    let name: String
    let version: String
    let id: Int
    let ua: String
    let ctx: [String: Any]
    let music: Bool
    let mediaHeaders: Bool
  }

  static let clients: [Client] = [
    Client(
      name: "VISIONOS", version: "0.1", id: 101,
      ua: "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
      ctx: ["osName": "VISION_OS", "osVersion": "1.3", "deviceMake": "Apple", "deviceModel": "RealityDevice14,1", "platform": "MOBILE"],
      music: true, mediaHeaders: false),
    Client(
      name: "ANDROID_VR", version: "1.65.10", id: 28,
      ua: "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
      ctx: ["deviceMake": "Oculus", "deviceModel": "Quest 3", "osName": "Android", "osVersion": "12L", "androidSdkVersion": 32],
      music: false, mediaHeaders: false),
    Client(
      name: "ANDROID_VR", version: "1.60.19", id: 28,
      ua: "com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
      ctx: ["deviceMake": "Oculus", "deviceModel": "Quest 3", "osName": "Android", "osVersion": "12L", "androidSdkVersion": 32],
      music: false, mediaHeaders: false),
  ]

  private static let webUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"
  private let session: URLSession = {
    let c = URLSessionConfiguration.ephemeral
    c.timeoutIntervalForRequest = 15
    c.httpMaximumConnectionsPerHost = 8
    c.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: c)
  }()
  private let lock = NSLock()
  private var visitor: String?
  private var visitorAt = Date.distantPast
  private var failures: [String: Date] = [:]
  private let work = DispatchQueue(label: "aurora.yt", qos: .userInitiated, attributes: .concurrent)

  struct Failure: Error { let text: String }

  /// Resolves [videoId] to a local audio file. `quality` 0 = lowest, 1 = medium, 2 = highest.
  func resolve(videoId: String, quality: Int, done: @escaping ([String: Any]?, String?) -> Void) {
    work.async {
      var trace: [String] = []
      let cache = AuroraYT.cacheDir()
      let cached = cache.appendingPathComponent("yt_\(videoId)_\(quality).m4a")
      if let size = (try? FileManager.default.attributesOfItem(atPath: cached.path)[.size] as? Int), size > 100_000 {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: cached.path)
        return done(["path": cached.path, "client": "cache", "trace": []], nil)
      }
      let vd = self.visitorData(&trace)
      if vd == nil { trace.append("no-visitor") }
      var list = AuroraYT.clients
      let fresh = list.filter { !self.recentlyFailed(videoId, $0) }
      if !fresh.isEmpty { list = fresh }
      for c in list {
        let tag = "\(c.name)\(c.version)"
        do {
          let formats = try self.player(videoId: videoId, client: c, visitor: vd)
          let ordered = AuroraYT.order(formats, quality: quality)
          if ordered.isEmpty { throw Failure(text: "no-audio") }
          var lastError = "none"
          for f in ordered.prefix(3) {
            do {
              let out = try self.download(url: f.url, client: c)
              try? FileManager.default.removeItem(at: cached)
              try FileManager.default.moveItem(at: out, to: cached)
              AuroraYT.trim(cache)
              return done(["path": cached.path, "client": tag, "kbps": f.bitrate / 1000, "trace": trace], nil)
            } catch {
              lastError = (error as? Failure)?.text ?? error.localizedDescription
              trace.append("\(tag):dl:\(lastError)")
            }
          }
          throw Failure(text: "dl:\(lastError)")
        } catch {
          let why = (error as? Failure)?.text ?? error.localizedDescription
          if !why.hasPrefix("dl:") { trace.append("\(tag):\(why)") }
          self.markFailed(videoId, c)
        }
      }
      done(nil, "YouTube: no client could download this song [" + trace.suffix(8).joined(separator: " | ") + "]")
    }
  }

  // MARK: Health

  private func recentlyFailed(_ v: String, _ c: Client) -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard let at = failures["\(v)|\(c.name)\(c.version)"] else { return false }
    return Date().timeIntervalSince(at) < 300
  }

  private func markFailed(_ v: String, _ c: Client) {
    lock.lock(); defer { lock.unlock() }
    failures["\(v)|\(c.name)\(c.version)"] = Date()
    if failures.count > 400 { failures = failures.filter { Date().timeIntervalSince($0.value) < 300 } }
  }

  // MARK: Visitor data

  private func visitorData(_ trace: inout [String]) -> String? {
    lock.lock()
    if let v = visitor, Date().timeIntervalSince(visitorAt) < 4 * 3600 { lock.unlock(); return v }
    lock.unlock()
    var found: String?
    if let body = fetch("https://www.youtube.com/sw.js_data", ua: AuroraYT.webUA) {
      let text = String(decoding: body, as: UTF8.self)
      if let nl = text.firstIndex(of: "\n"),
         let obj = try? JSONSerialization.jsonObject(with: Data(text[text.index(after: nl)...].trimmingCharacters(in: .whitespaces).utf8)),
         let a = obj as? [Any], let b = a.first as? [Any], b.count > 2, let c = b[2] as? [Any], let d = c.first as? [Any],
         let e = d.first as? [Any], e.count > 13, let s = e[13] as? String, !s.isEmpty {
        found = s
      }
    }
    if found == nil, let body = fetch("https://music.youtube.com/", ua: AuroraYT.webUA) {
      let text = String(decoding: body, as: UTF8.self)
      if let r = text.range(of: "\"visitorData\":\"") ?? text.range(of: "\"VISITOR_DATA\":\"") {
        let rest = text[r.upperBound...]
        if let end = rest.firstIndex(of: "\"") { found = String(rest[..<end]) }
      }
    }
    if let f = found {
      lock.lock(); visitor = f; visitorAt = Date(); lock.unlock()
    } else {
      trace.append("visitor-failed")
    }
    return found
  }

  private func fetch(_ url: String, ua: String) -> Data? {
    guard let u = URL(string: url) else { return nil }
    var r = URLRequest(url: u)
    r.setValue(ua, forHTTPHeaderField: "User-Agent")
    r.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
    return sync(r).data
  }

  private func sync(_ r: URLRequest) -> (data: Data?, status: Int, error: String?) {
    let sem = DispatchSemaphore(value: 0)
    var out: (Data?, Int, String?) = (nil, 0, nil)
    session.dataTask(with: r) { d, resp, e in
      out = (d, (resp as? HTTPURLResponse)?.statusCode ?? 0, e?.localizedDescription)
      sem.signal()
    }.resume()
    _ = sem.wait(timeout: .now() + 25)
    return out
  }

  // MARK: Player request

  struct Format {
    let url: String
    let bitrate: Int
    let mime: String
  }

  private func player(videoId: String, client c: Client, visitor: String?) throws -> [Format] {
    let host = c.music ? "music.youtube.com" : "www.youtube.com"
    guard let url = URL(string: "https://\(host)/youtubei/v1/player?prettyPrint=false") else { throw Failure(text: "url") }
    var clientCtx: [String: Any] = ["clientName": c.name, "clientVersion": c.version, "hl": "en", "gl": "US"]
    if let v = visitor { clientCtx["visitorData"] = v }
    for (k, v) in c.ctx { clientCtx[k] = v }
    let body: [String: Any] = [
      "context": ["client": clientCtx],
      "videoId": videoId,
      "contentCheckOk": true,
      "racyCheckOk": true,
    ]
    var r = URLRequest(url: url)
    r.httpMethod = "POST"
    r.httpBody = try JSONSerialization.data(withJSONObject: body)
    r.setValue("application/json", forHTTPHeaderField: "Content-Type")
    r.setValue(c.ua, forHTTPHeaderField: "User-Agent")
    r.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")
    r.setValue("\(c.id)", forHTTPHeaderField: "X-YouTube-Client-Name")
    r.setValue(c.version, forHTTPHeaderField: "X-YouTube-Client-Version")
    let origin = c.music ? "https://music.youtube.com" : "https://www.youtube.com"
    r.setValue(origin, forHTTPHeaderField: "Origin")
    r.setValue(origin, forHTTPHeaderField: "X-Origin")
    r.setValue(origin + "/", forHTTPHeaderField: "Referer")
    if let v = visitor { r.setValue(v, forHTTPHeaderField: "X-Goog-Visitor-Id") }
    let res = sync(r)
    guard res.status == 200, let data = res.data else { throw Failure(text: "HTTP\(res.status)\(res.error.map { ":" + $0 } ?? "")") }
    guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure(text: "bad-json") }
    let ps = j["playabilityStatus"] as? [String: Any]
    let status = ps?["status"] as? String ?? "NO_STATUS"
    guard let sd = j["streamingData"] as? [String: Any] else { throw Failure(text: status) }
    var out: [Format] = []
    for f in (sd["adaptiveFormats"] as? [[String: Any]]) ?? [] {
      let mime = f["mimeType"] as? String ?? ""
      guard mime.hasPrefix("audio/mp4"), let u = f["url"] as? String else { continue }
      out.append(Format(url: u, bitrate: (f["bitrate"] as? Int) ?? 0, mime: mime))
    }
    for f in (sd["formats"] as? [[String: Any]]) ?? [] {
      let mime = f["mimeType"] as? String ?? ""
      guard mime.hasPrefix("video/mp4"), mime.contains("mp4a"), let u = f["url"] as? String else { continue }
      out.append(Format(url: u, bitrate: (f["bitrate"] as? Int) ?? 0, mime: mime))
    }
    if out.isEmpty { throw Failure(text: "\(status):no-direct-url") }
    return out
  }

  /// AAC (audio/mp4) streams in the order wanted for [quality]; the muxed MP4 last.
  private static func order(_ f: [Format], quality: Int) -> [Format] {
    let audio = f.filter { $0.mime.hasPrefix("audio/") }.sorted { $0.bitrate > $1.bitrate }
    let muxed = f.filter { $0.mime.hasPrefix("video/") }.sorted { $0.bitrate < $1.bitrate }
    var a = audio
    if quality <= 0 { a = audio.reversed() } else if quality == 1, audio.count > 1 { a = [audio[audio.count / 2]] + audio }
    return Array(a.prefix(2)) + Array(muxed.prefix(1))
  }

  // MARK: Download

  private func download(url: String, client c: Client) throws -> URL {
    guard let u = URL(string: url) else { throw Failure(text: "bad-url") }
    let d = ParallelDownloader(url: u, headers: c.mediaHeaders ? ["User-Agent": c.ua] : [:])
    let sem = DispatchSemaphore(value: 0)
    var result: Result<ParallelDownloader.Output, Error>?
    d.start { r in result = r; sem.signal() }
    if sem.wait(timeout: .now() + 90) == .timedOut {
      d.cancel()
      throw Failure(text: "timeout")
    }
    switch result {
    case .success(let o)?:
      if o.mime.contains("webm") || o.mime.contains("opus") {
        try? FileManager.default.removeItem(at: o.url)
        throw Failure(text: "webm")
      }
      return o.url
    case .failure(let e)?:
      throw Failure(text: e.localizedDescription)
    case nil:
      throw Failure(text: "no-result")
    }
  }

  // MARK: Cache

  static func cacheDir() -> URL {
    let d = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("music_audio_cache", isDirectory: true)
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
  }

  private static func trim(_ dir: URL) {
    let fm = FileManager.default
    guard var files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
    files.sort {
      let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
      let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
      return a < b
    }
    if files.count > 20 { for f in files.prefix(files.count - 20) { try? fm.removeItem(at: f) } }
  }
}
