import AudioToolbox
import AVFoundation
import Flutter

/// Native iPhone/iPad audio engine, the counterpart of the Android Media3 engine.
///
/// Every song plays through its own "voice": two mono player nodes (left / right) -> time-pitch (tempo changes
/// for beat matching) -> 12-band EQ (10 equaliser bands + DJ high-pass / low-pass) -> either a plain stereo mixer
/// (pan -1 / +1) or, with Spatial Audio on, an AVAudioEnvironmentNode that places the two channels as virtual
/// speakers in front of the listener (HRTF binaural rendering). Two voices let Dart crossfade between songs.
///
/// Dart (QueueEngine) still owns the queue, source resolution and Automix planning; this class only plays.
final class AuroraAudio: NSObject, FlutterStreamHandler {
  static let shared = AuroraAudio()

  let q = DispatchQueue(label: "aurora.audio")
  let engine = AVAudioEngine()
  let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
  let stereoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!

  var voices: [Int: Voice] = [:]
  private var sink: FlutterEventSink?
  private var started = false
  var spatialOn = false
  private var protectOn = true
  private let guardEQ = AVAudioUnitEQ(numberOfBands: 1)
  private var limiter: AVAudioUnitEffect?
  private var timer: DispatchSourceTimer?
  private var lastLevelAt = Date.distantPast

  // MARK: Flutter plumbing

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  func emit(_ message: [String: Any]) {
    DispatchQueue.main.async { [weak self] in self?.sink?(message) }
  }

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let a = call.arguments as? [String: Any] ?? [:]
    let id = (a["id"] as? Int) ?? 0
    q.async { [weak self] in
      guard let self = self else { return }
      func done(_ value: Any? = nil) { DispatchQueue.main.async { result(value) } }
      func fail(_ code: String, _ message: String) {
        DispatchQueue.main.async { result(FlutterError(code: code, message: message, details: nil)) }
      }
      self.setupIfNeeded()
      if call.method == "init" { return done(self.engine.isRunning) }
      if call.method == "protect" {
        self.setProtection((a["on"] as? Bool) ?? true)
        return done()
      }
      if call.method == "spatial" {
        let on = (a["on"] as? Bool) ?? false
        self.spatialOn = on
        for v in self.voices.values { v.route(spatial: on) }
        return done()
      }
      guard let v = self.voices[id] else { return fail("bad_voice", "no voice \(id)") }
      switch call.method {
      case "open":
        guard let url = a["url"] as? String else { return fail("bad_args", "url missing") }
        let headers = a["headers"] as? [String: String] ?? [:]
        let startMs = (a["startMs"] as? Int) ?? 0
        v.open(url: url, headers: headers, startMs: startMs) { info, error in
          if let error = error { fail("open_failed", error) } else { done(info ?? ["dur": 0, "bytes": 0, "ms": 0]) }
        }
      case "play": v.play(); done()
      case "pause": v.pause(); done()
      case "seek": v.seek(ms: (a["ms"] as? Int) ?? 0); done()
      case "volume": v.mixer.outputVolume = Float(max(0, min(1, (a["v"] as? Double) ?? 1))); done()
      case "speed": v.setSpeed(Float((a["v"] as? Double) ?? 1)); done()
      case "eq":
        v.setEq(enabled: (a["enabled"] as? Bool) ?? false, gains: (a["gains"] as? [Double]) ?? [])
        done()
      case "mixChain": v.setMixChain((a["on"] as? Bool) ?? false); done()
      case "mixFilter":
        v.setMixFilter(hp: (a["hp"] as? Double) ?? 20, lp: (a["lp"] as? Double) ?? 18000)
        done()
      default: DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
      }
    }
  }

  // MARK: Engine lifecycle (always on `q`)

  private func setupIfNeeded() {
    guard !started else { return }
    configureSession()
    for id in 0..<2 { voices[id] = Voice(id: id, host: self) }
    _ = engine.mainMixerNode
    buildProtectionChain()
    installLevelTap()
    observe()
    started = true // set up exactly once, even if the engine itself fails to start
    engine.prepare()
    do {
      try engine.start()
    } catch {
      emit(["e": "error", "v": -1, "msg": "engine start failed: \(error.localizedDescription)"])
    }
    startTimer()
  }

  private func configureSession() {
    let s = AVAudioSession.sharedInstance()
    try? s.setCategory(.playback, mode: .default, options: [])
    // 48 kHz is the native rate of HDMI / AirPlay / home-theatre receivers and of most Bluetooth codecs, so
    // nothing downstream has to resample our output again.
    try? s.setPreferredSampleRate(48000)
    try? s.setPreferredIOBufferDuration(0.02)
    try? s.setActive(true)
  }

  /// Output protection, always the last stage before the speaker:
  /// - a 30 Hz high-pass removes inaudible sub-bass that overloads woofers and receiver protection circuits,
  /// - a peak limiter stops EQ boosts, spatial gain or loud masters from ever clipping,
  /// - about 3 dB of headroom keeps the limiter from working all the time.
  private func buildProtectionChain() {
    let main = engine.mainMixerNode
    let band = guardEQ.bands[0]
    band.filterType = .highPass
    band.frequency = 30
    band.bypass = false
    let desc = AudioComponentDescription(
      componentType: kAudioUnitType_Effect,
      componentSubType: kAudioUnitSubType_PeakLimiter,
      componentManufacturer: kAudioUnitManufacturer_Apple,
      componentFlags: 0,
      componentFlagsMask: 0
    )
    let lim = AVAudioUnitEffect(audioComponentDescription: desc)
    limiter = lim
    engine.attach(guardEQ)
    engine.attach(lim)
    engine.disconnectNodeOutput(main)
    engine.connect(main, to: guardEQ, format: nil)
    engine.connect(guardEQ, to: lim, format: nil)
    engine.connect(lim, to: engine.outputNode, format: nil)
    AudioUnitSetParameter(lim.audioUnit, AudioUnitParameterID(kLimiterParam_AttackTime), kAudioUnitScope_Global, 0, 0.002, 0)
    AudioUnitSetParameter(lim.audioUnit, AudioUnitParameterID(kLimiterParam_DecayTime), kAudioUnitScope_Global, 0, 0.05, 0)
    AudioUnitSetParameter(lim.audioUnit, AudioUnitParameterID(kLimiterParam_PreGain), kAudioUnitScope_Global, 0, 0, 0)
    setProtection(protectOn)
  }

  func setProtection(_ on: Bool) {
    protectOn = on
    engine.mainMixerNode.outputVolume = on ? 0.708 : 1.0
    guardEQ.bypass = !on
    limiter?.bypass = !on
  }

  func ensureRunning() {
    configureSession()
    if !engine.isRunning {
      engine.prepare()
      try? engine.start()
    }
  }

  private func installLevelTap() {
    let mixer = engine.mainMixerNode
    mixer.removeTap(onBus: 0)
    mixer.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buffer, _ in
      guard let self = self, let ch = buffer.floatChannelData?[0] else { return }
      let n = Int(buffer.frameLength)
      if n == 0 { return }
      var sum: Float = 0
      var low: Float = 0
      var lp: Float = 0
      for i in 0..<n {
        let x = ch[i]
        sum += x * x
        lp += 0.03 * (x - lp)
        low += lp * lp
      }
      let now = Date()
      if now.timeIntervalSince(self.lastLevelAt) < 0.04 { return }
      self.lastLevelAt = now
      self.emit(["e": "level", "rms": Double((sum / Float(n)).squareRoot()), "low": Double((low / Float(n)).squareRoot())])
    }
  }

  private func startTimer() {
    timer?.cancel()
    let t = DispatchSource.makeTimerSource(queue: q)
    t.schedule(deadline: .now() + 0.1, repeating: 0.1)
    t.setEventHandler { [weak self] in
      guard let self = self else { return }
      for v in self.voices.values where v.isPlaying {
        self.emit(["e": "pos", "v": v.id, "ms": v.currentMs(), "dur": v.durationMs])
      }
    }
    t.resume()
    timer = t
  }

  private func observe() {
    let nc = NotificationCenter.default
    nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] n in
      guard let self = self, let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
      var shouldResume = false
      if let o = n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt {
        shouldResume = AVAudioSession.InterruptionOptions(rawValue: o).contains(.shouldResume)
      }
      self.q.async {
        if type == .began {
          for v in self.voices.values { v.interrupt() }
        } else if shouldResume {
          self.ensureRunning()
          for v in self.voices.values { v.resumeAfterInterrupt() }
        }
      }
    }
    nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] n in
      guard let self = self, let raw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
      self.q.async { for v in self.voices.values { v.pause() } }
    }
    nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
      guard let self = self else { return }
      self.q.async {
        self.installLevelTap()
        self.ensureRunning()
        for v in self.voices.values { v.recover() }
      }
    }
  }
}

final class Voice {
  let id: Int
  unowned let host: AuroraAudio
  private var engine: AVAudioEngine { host.engine }

  let playerL = AVAudioPlayerNode()
  let playerR = AVAudioPlayerNode()
  let tpL = AVAudioUnitTimePitch()
  let tpR = AVAudioUnitTimePitch()
  let eqL = AVAudioUnitEQ(numberOfBands: 12)
  let eqR = AVAudioUnitEQ(numberOfBands: 12)
  let mixer = AVAudioMixerNode()
  let env = AVAudioEnvironmentNode()

  private var asset: AVURLAsset?
  private var audioTrack: AVAssetTrack?
  private var reader: AVAssetReader?
  private var output: AVAssetReaderTrackOutput?
  private var carry: [Float] = []
  private var hasMedia = false
  private var localURL: URL?
  private var downloader: ParallelDownloader?
  private var gen = 0
  private var eof = true
  private var outstanding = 0
  private var baseMs = 0
  private var lastPosMs = 0
  private var completedSent = false
  private var wasPlayingBeforeInterrupt = false
  private var mixOn = false
  private var routedSpatial = false
  private(set) var durationMs = 0
  private(set) var isPlaying = false

  private static let freqs: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
  private static let chunkFrames: AVAudioFrameCount = 96_000 // 2 s at 48 kHz
  private static let chunksAhead = 4

  init(id: Int, host: AuroraAudio) {
    self.id = id
    self.host = host
    let nodes: [AVAudioNode] = [playerL, playerR, tpL, tpR, eqL, eqR, mixer, env]
    for n in nodes { engine.attach(n) }
    let mono = host.monoFormat
    engine.connect(playerL, to: tpL, format: mono)
    engine.connect(tpL, to: eqL, format: mono)
    engine.connect(playerR, to: tpR, format: mono)
    engine.connect(tpR, to: eqR, format: mono)
    engine.connect(mixer, to: engine.mainMixerNode, format: host.stereoFormat)
    playerL.pan = -1
    playerR.pan = 1
    playerL.position = AVAudio3DPoint(x: -1.0, y: 0, z: -1.73)
    playerR.position = AVAudio3DPoint(x: 1.0, y: 0, z: -1.73)
    playerL.renderingAlgorithm = .HRTFHQ
    playerR.renderingAlgorithm = .HRTFHQ
    env.outputType = .auto
    env.reverbParameters.enable = true
    env.reverbParameters.loadFactoryReverbPreset(.mediumRoom)
    env.reverbParameters.level = -22
    env.distanceAttenuationParameters.rolloffFactor = 0 // virtual speakers keep full level
    playerL.reverbBlend = 0.12
    playerR.reverbBlend = 0.12
    for eq in [eqL, eqR] {
      for i in 0..<10 {
        let b = eq.bands[i]
        b.filterType = .parametric
        b.frequency = Voice.freqs[i]
        b.bandwidth = 1.0
        b.gain = 0
        b.bypass = true
      }
      let hp = eq.bands[10]
      hp.filterType = .highPass
      hp.frequency = 20
      hp.bypass = true
      let lp = eq.bands[11]
      lp.filterType = .lowPass
      lp.frequency = 18000
      lp.bypass = true
    }
    route(spatial: host.spatialOn)
  }

  // MARK: Routing

  func route(spatial: Bool) {
    if spatial == routedSpatial, engine.outputConnectionPoints(for: eqL, outputBus: 0).count > 0 { return }
    routedSpatial = spatial
    engine.disconnectNodeOutput(eqL)
    engine.disconnectNodeOutput(eqR)
    engine.disconnectNodeOutput(env)
    let mono = host.monoFormat
    if spatial {
      engine.connect(eqL, to: env, format: mono)
      engine.connect(eqR, to: env, format: mono)
      engine.connect(env, to: mixer, fromBus: 0, toBus: 0, format: host.stereoFormat)
    } else {
      engine.connect(eqL, to: mixer, fromBus: 0, toBus: 0, format: mono)
      engine.connect(eqR, to: mixer, fromBus: 0, toBus: 1, format: mono)
    }
  }

  // MARK: Opening

  func open(url: String, headers: [String: String], startMs: Int, completion: @escaping ([String: Any]?, String?) -> Void) {
    gen += 1
    let g = gen
    hardStop()
    downloader?.cancel()
    downloader = nil
    completedSent = false
    let began = Date()
    fetch(url, headers: headers) { [weak self] result in
      guard let self = self else { return }
      self.host.q.async {
        guard g == self.gen else { return completion(["dur": 0, "bytes": 0, "ms": 0], nil) }
        switch result {
        case .failure(let error):
          completion(nil, error.localizedDescription)
        case .success(let location):
          let ms = Int(Date().timeIntervalSince(began) * 1000)
          self.prepare(location.url, isTemp: location.temp, startMs: startMs) { dur, err in
            var info: [String: Any]?
            if let d = dur { info = ["dur": d, "bytes": location.bytes, "ms": ms] }
            completion(info, err)
          }
        }
      }
    }
  }

  private func prepare(_ url: URL, isTemp: Bool, startMs: Int, completion: (Int?, String?) -> Void) {
    // AVAssetReader decodes everything iOS can play, including the fragmented MP4 (DASH) audio YouTube serves.
    let a = AVURLAsset(url: url)
    let sem = DispatchSemaphore(value: 0)
    a.loadValuesAsynchronously(forKeys: ["tracks", "duration"]) { sem.signal() }
    _ = sem.wait(timeout: .now() + 20)
    guard let track = a.tracks(withMediaType: .audio).first else {
      if isTemp { try? FileManager.default.removeItem(at: url) }
      return completion(nil, "cannot decode this audio")
    }
    let old = localURL
    asset = a
    audioTrack = track
    localURL = isTemp ? url : nil
    if let old = old, old != url { try? FileManager.default.removeItem(at: old) }
    let seconds = CMTimeGetSeconds(a.duration)
    durationMs = seconds.isFinite && seconds > 0 ? Int(seconds * 1000) : 0
    let start = (startMs > 0 && (durationMs == 0 || startMs < durationMs)) ? startMs : 0
    guard openReader(at: start) else { return completion(nil, "cannot read this audio") }
    hasMedia = true
    eof = false
    outstanding = 0
    baseMs = start
    lastPosMs = start
    feed()
    completion(durationMs, nil)
  }

  private func openReader(at ms: Int) -> Bool {
    guard let a = asset, let track = audioTrack, let r = try? AVAssetReader(asset: a) else { return false }
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: 48000,
      AVNumberOfChannelsKey: 2,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]
    let out = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
    guard r.canAdd(out) else { return false }
    r.add(out)
    if ms > 0 {
      r.timeRange = CMTimeRange(start: CMTime(seconds: Double(ms) / 1000, preferredTimescale: 1000), duration: .positiveInfinity)
    }
    guard r.startReading() else { return false }
    reader = r
    output = out
    carry.removeAll(keepingCapacity: true)
    return true
  }

  private func fetch(_ source: String, headers: [String: String], done: @escaping (Result<(url: URL, temp: Bool, bytes: Int), Error>) -> Void) {
    if !(source.hasPrefix("http://") || source.hasPrefix("https://")) {
      let u = source.hasPrefix("file://") ? (URL(string: source) ?? URL(fileURLWithPath: source)) : URL(fileURLWithPath: source)
      return done(.success((u, false, 0)))
    }
    guard let url = URL(string: source) else {
      return done(.failure(NSError(domain: "aurora", code: 1, userInfo: [NSLocalizedDescriptionKey: "bad url"])))
    }
    let d = ParallelDownloader(url: url, headers: headers)
    downloader = d
    d.start { result in
      switch result {
      case .failure(let e):
        done(.failure(e))
      case .success(let out):
        if out.mime.contains("webm") || out.mime.contains("ogg") || out.mime.contains("opus") {
          try? FileManager.default.removeItem(at: out.url)
          return done(.failure(NSError(domain: "aurora", code: 3, userInfo: [NSLocalizedDescriptionKey: "this audio format (webm/opus) is not playable natively"])))
        }
        done(.success((out.url, true, out.bytes)))
      }
    }
  }

  // MARK: Feeding

  /// Pulls decoded interleaved stereo float samples and splits them into one mono buffer per channel.
  private func nextChunk() -> (AVAudioPCMBuffer, AVAudioPCMBuffer)? {
    guard !eof, let out = output else { return nil }
    let want = Int(Voice.chunkFrames)
    var readerDone = false
    while carry.count / 2 < want && !readerDone {
      guard let sb = out.copyNextSampleBuffer() else { readerDone = true; break }
      if let block = CMSampleBufferGetDataBuffer(sb) {
        let length = CMBlockBufferGetDataLength(block)
        if length >= 8 {
          let floatCount = length / MemoryLayout<Float>.size
          var floats = [Float](repeating: 0, count: floatCount)
          let status = floats.withUnsafeMutableBytes { ptr -> OSStatus in
            guard let base = ptr.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: floatCount * MemoryLayout<Float>.size, destination: base)
          }
          if status == kCMBlockBufferNoErr { carry.append(contentsOf: floats) }
        }
      }
      CMSampleBufferInvalidate(sb)
    }
    if readerDone { eof = true }
    let frames = min(want, carry.count / 2)
    if frames == 0 {
      eof = true
      return nil
    }
    guard let l = AVAudioPCMBuffer(pcmFormat: host.monoFormat, frameCapacity: AVAudioFrameCount(frames)),
          let r = AVAudioPCMBuffer(pcmFormat: host.monoFormat, frameCapacity: AVAudioFrameCount(frames)),
          let dl = l.floatChannelData?[0], let dr = r.floatChannelData?[0] else { return nil }
    carry.withUnsafeBufferPointer { p in
      for i in 0..<frames {
        dl[i] = p[i * 2]
        dr[i] = p[i * 2 + 1]
      }
    }
    carry.removeFirst(frames * 2)
    l.frameLength = AVAudioFrameCount(frames)
    r.frameLength = AVAudioFrameCount(frames)
    return (l, r)
  }

  private func feed() {
    while !eof && outstanding < Voice.chunksAhead {
      guard let (l, r) = nextChunk() else { break }
      outstanding += 1
      let g = gen
      playerR.scheduleBuffer(r, completionHandler: nil)
      playerL.scheduleBuffer(l, completionCallbackType: .dataPlayedBack) { [weak self] _ in
        guard let self = self else { return }
        self.host.q.async {
          guard self.gen == g else { return }
          self.outstanding -= 1
          self.feed()
        }
      }
    }
    if eof && outstanding == 0 && hasMedia && !completedSent {
      completedSent = true
      isPlaying = false
      host.emit(["e": "done", "v": id])
    }
  }

  // MARK: Transport

  func play() {
    guard hasMedia else { return }
    host.ensureRunning()
    if !isPlaying {
      let start = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.03)
      let t = AVAudioTime(hostTime: start)
      playerL.play(at: t)
      playerR.play(at: t)
      isPlaying = true
    }
    host.emit(["e": "state", "v": id, "playing": true])
  }

  func pause() {
    playerL.pause()
    playerR.pause()
    _ = currentMs()
    isPlaying = false
    wasPlayingBeforeInterrupt = false
    host.emit(["e": "state", "v": id, "playing": false])
  }

  func interrupt() {
    wasPlayingBeforeInterrupt = isPlaying
    playerL.pause()
    playerR.pause()
    _ = currentMs()
    isPlaying = false
    host.emit(["e": "state", "v": id, "playing": false])
  }

  func resumeAfterInterrupt() {
    if wasPlayingBeforeInterrupt { play() }
    wasPlayingBeforeInterrupt = false
  }

  func seek(ms: Int) {
    guard hasMedia else { return }
    let wasPlaying = isPlaying
    gen += 1
    playerL.stop()
    playerR.stop()
    isPlaying = false
    outstanding = 0
    completedSent = false
    reader?.cancelReading()
    let target = max(0, min(ms, max(0, durationMs - 50)))
    guard openReader(at: target) else {
      eof = true
      host.emit(["e": "error", "v": id, "msg": "seek failed"])
      return
    }
    eof = false
    baseMs = target
    lastPosMs = target
    feed()
    if wasPlaying { play() }
  }

  /// After an audio-route change the engine restarts and the player nodes lose their queue: rebuild from the last position.
  func recover() {
    guard hasMedia else { return }
    let wasPlaying = isPlaying || wasPlayingBeforeInterrupt
    let at = lastPosMs
    isPlaying = false
    seek(ms: at)
    if wasPlaying { play() }
  }

  private func hardStop() {
    playerL.stop()
    playerR.stop()
    isPlaying = false
    outstanding = 0
    eof = true
    baseMs = 0
    lastPosMs = 0
    durationMs = 0
    hasMedia = false
    reader?.cancelReading()
    reader = nil
    output = nil
    carry.removeAll()
  }

  func currentMs() -> Int {
    guard let nt = playerL.lastRenderTime, nt.isSampleTimeValid, let pt = playerL.playerTime(forNodeTime: nt), pt.sampleRate > 0 else {
      return lastPosMs
    }
    let ms = baseMs + Int(Double(pt.sampleTime) / pt.sampleRate * 1000)
    lastPosMs = max(0, min(ms, durationMs))
    return lastPosMs
  }

  // MARK: Sound shaping

  func setSpeed(_ speed: Float) {
    let r = max(0.25, min(4.0, speed))
    tpL.rate = r
    tpR.rate = r
  }

  func setEq(enabled: Bool, gains: [Double]) {
    for eq in [eqL, eqR] {
      for i in 0..<10 {
        let g = enabled && i < gains.count ? Float(max(-24.0, min(24.0, gains[i]))) : 0
        let b = eq.bands[i]
        b.gain = g
        b.bypass = abs(g) < 0.05
      }
      let peak = enabled ? Float(gains.max() ?? 0) : 0
      eq.globalGain = peak > 0 ? -peak : 0
    }
  }

  func setMixChain(_ on: Bool) {
    mixOn = on
    for eq in [eqL, eqR] {
      eq.bands[10].frequency = 20
      eq.bands[11].frequency = 18000
      eq.bands[10].bypass = !on
      eq.bands[11].bypass = !on
    }
  }

  func setMixFilter(hp: Double, lp: Double) {
    guard mixOn else { return }
    for eq in [eqL, eqR] {
      eq.bands[10].frequency = Float(max(20, min(20000, hp)))
      eq.bands[11].frequency = Float(max(200, min(20000, lp)))
    }
  }
}
