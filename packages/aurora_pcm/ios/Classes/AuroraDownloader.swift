import Foundation

/// Downloads one file with several HTTP range requests in flight at once, so a 4-5 MB song arrives in about a
/// second instead of crawling through one connection. Falls back to a plain single download when the server
/// ignores ranges. Writes straight into the destination file with pwrite (thread safe, no seeking).
final class ParallelDownloader {
  struct Output {
    let url: URL
    let mime: String
    let bytes: Int
  }

  private let source: URL
  private let headers: [String: String]
  private let session: URLSession
  private let lock = NSLock()
  private var tasks: [URLSessionDataTask] = []
  private var cancelled = false
  private var finished = false

  private var fd: Int32 = -1
  private var dest: URL!
  private var mime = ""
  private var total = 0
  private var pending: [(start: Int, end: Int)] = []
  private var inflight = 0
  private var received = 0
  private var completion: ((Result<Output, Error>) -> Void)?

  static let chunk = 1_048_576
  static let width = 6

  init(url: URL, headers: [String: String]) {
    source = url
    self.headers = headers
    let cfg = URLSessionConfiguration.ephemeral
    cfg.httpMaximumConnectionsPerHost = ParallelDownloader.width + 2
    cfg.timeoutIntervalForRequest = 20
    cfg.timeoutIntervalForResource = 120
    cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
    session = URLSession(configuration: cfg)
  }

  func start(_ done: @escaping (Result<Output, Error>) -> Void) {
    completion = done
    // First range: learns the total size (Content-Range) and proves the link works.
    request(0, ParallelDownloader.chunk - 1, tries: 4) { [weak self] result in
      guard let self = self else { return }
      switch result {
      case .failure(let e):
        self.finish(.failure(e))
      case .success(let r):
        self.afterFirst(r)
      }
    }
  }

  func cancel() {
    lock.lock()
    cancelled = true
    let t = tasks
    lock.unlock()
    t.forEach { $0.cancel() }
    session.invalidateAndCancel()
  }

  // MARK: Internals

  private struct Piece {
    let data: Data
    let status: Int
    let contentRange: String?
    let mime: String
  }

  /// googlevideo links are most reliable when the byte range travels in the URL (`&range=a-b`), exactly as
  /// YouTube's own apps ask for it; a `Range` header is the fallback. Returns nil for other hosts.
  private var isGV: Bool { (source.host ?? "").contains("googlevideo.com") }
  private var gvLength: Int? {
    URLComponents(url: source, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "clen" }?.value.flatMap { Int($0) }
  }

  private func rangedURL(_ start: Int, _ end: Int) -> URL {
    guard var c = URLComponents(url: source, resolvingAgainstBaseURL: false) else { return source }
    var items = (c.queryItems ?? []).filter { $0.name != "range" }
    items.append(URLQueryItem(name: "range", value: "\(start)-\(end)"))
    c.queryItems = items
    return c.url ?? source
  }

  private func request(_ start: Int, _ end: Int, tries: Int, attempt: Int = 0, _ done: @escaping (Result<Piece, Error>) -> Void) {
    // Even attempts use the URL range (googlevideo only), odd attempts the Range header.
    let viaURL = isGV && attempt % 2 == 0
    var req = URLRequest(url: viaURL ? rangedURL(start, end) : source)
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    if !viaURL { req.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range") }
    let task = session.dataTask(with: req) { [weak self] data, response, error in
      guard let self = self else { return }
      if self.isCancelled { return done(.failure(NSError(domain: "aurora", code: -999, userInfo: [NSLocalizedDescriptionKey: "cancelled"]))) }
      if let http = response as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 206), let data = data, error == nil {
        var status = http.statusCode
        var range = http.value(forHTTPHeaderField: "Content-Range")
        if viaURL, status == 200, let total = self.gvLength {
          // The URL range answers 200 with just the slice: describe it as the 206 the rest of the code expects.
          status = 206
          range = "bytes \(start)-\(start + data.count - 1)/\(total)"
        }
        return done(.success(Piece(
          data: data,
          status: status,
          contentRange: range,
          mime: (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        )))
      }
      if tries > 1 {
        return self.request(start, end, tries: tries - 1, attempt: attempt + 1, done)
      }
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      let why = error?.localizedDescription ?? "HTTP \(status)"
      done(.failure(NSError(domain: "aurora", code: status, userInfo: [NSLocalizedDescriptionKey: "download failed (\(why))"])))
    }
    lock.lock()
    tasks.append(task)
    lock.unlock()
    task.resume()
  }

  private var isCancelled: Bool {
    lock.lock(); defer { lock.unlock() }
    return cancelled
  }

  private func afterFirst(_ first: Piece) {
    mime = first.mime
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("aurora_play", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    dest = dir.appendingPathComponent("\(UUID().uuidString).\(Self.ext(for: first.mime, url: source))")
    fd = open(dest.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    guard fd >= 0 else { return finish(.failure(NSError(domain: "aurora", code: 4, userInfo: [NSLocalizedDescriptionKey: "cannot create temp file"]))) }

    if first.status == 200 {
      // Server ignored the range: this is already the whole file.
      write(first.data, at: 0)
      total = first.data.count
      return finish(.success(Output(url: dest, mime: mime, bytes: total)))
    }
    guard let range = first.contentRange, let slash = range.lastIndex(of: "/"),
          let size = Int(range[range.index(after: slash)...]), size > 0 else {
      write(first.data, at: 0)
      total = first.data.count
      return finish(.success(Output(url: dest, mime: mime, bytes: total)))
    }
    total = size
    ftruncate(fd, off_t(size))
    write(first.data, at: 0)
    received = first.data.count
    var start = first.data.count
    while start < size {
      let end = min(size - 1, start + ParallelDownloader.chunk - 1)
      pending.append((start, end))
      start = end + 1
    }
    if pending.isEmpty { return finish(.success(Output(url: dest, mime: mime, bytes: total))) }
    pump()
  }

  private func pump() {
    lock.lock()
    var launch: [(start: Int, end: Int)] = []
    while inflight < ParallelDownloader.width, !pending.isEmpty, !finished, !cancelled {
      launch.append(pending.removeFirst())
      inflight += 1
    }
    lock.unlock()
    for piece in launch {
      request(piece.start, piece.end, tries: 4) { [weak self] result in
        guard let self = self else { return }
        switch result {
        case .failure(let e):
          self.finish(.failure(e))
        case .success(let p):
          // A ranged request must come back as 206 with exactly the bytes asked for.
          if p.status != 206 || p.data.count != piece.end - piece.start + 1 {
            return self.finish(.failure(NSError(domain: "aurora", code: 5, userInfo: [NSLocalizedDescriptionKey: "incomplete range from server"])))
          }
          self.write(p.data, at: piece.start)
          self.lock.lock()
          self.inflight -= 1
          self.received += p.data.count
          let allDone = self.pending.isEmpty && self.inflight == 0
          self.lock.unlock()
          if allDone {
            self.finish(.success(Output(url: self.dest, mime: self.mime, bytes: self.total)))
          } else {
            self.pump()
          }
        }
      }
    }
  }

  private func write(_ data: Data, at offset: Int) {
    data.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      var done = 0
      while done < raw.count {
        let n = pwrite(fd, base + done, raw.count - done, off_t(offset + done))
        if n <= 0 { break }
        done += n
      }
    }
  }

  private func finish(_ result: Result<Output, Error>) {
    lock.lock()
    if finished { lock.unlock(); return }
    finished = true
    let cb = completion
    completion = nil
    let t = tasks
    lock.unlock()
    if fd >= 0 { close(fd); fd = -1 }
    if case .failure = result {
      t.forEach { $0.cancel() }
      if let d = dest { try? FileManager.default.removeItem(at: d) }
    }
    session.finishTasksAndInvalidate()
    cb?(result)
  }

  static func ext(for mime: String, url: URL) -> String {
    if mime.contains("mpeg") { return "mp3" }
    if mime.contains("mp4") || mime.contains("m4a") { return "m4a" }
    if mime.contains("aac") { return "aac" }
    if mime.contains("wav") { return "wav" }
    if mime.contains("flac") { return "flac" }
    let e = url.pathExtension.lowercased()
    return (e.isEmpty || e.count > 5) ? "m4a" : e
  }
}
