import AVFoundation
import MediaPlayer
import UIKit

/// Lock screen, Control Centre and headset buttons, handled natively.
///
/// Play and pause act on the audio engine directly, so they work even when the Dart side is asleep (after a long
/// pause iOS may suspend the isolate; the old route through Dart then needed the app to be opened again). Next,
/// previous and seeking are queue decisions, so they are forwarded to Dart as `remote` events.
final class AuroraRemote {
  static let shared = AuroraRemote()
  private var installed = false
  private var artUrl = ""
  private var artwork: MPMediaItemArtwork?
  private var info: [String: Any] = [:]

  func install() {
    guard !installed else { return }
    installed = true
    DispatchQueue.main.async {
      let c = MPRemoteCommandCenter.shared()
      c.playCommand.isEnabled = true
      c.pauseCommand.isEnabled = true
      c.togglePlayPauseCommand.isEnabled = true
      c.nextTrackCommand.isEnabled = true
      c.previousTrackCommand.isEnabled = true
      c.changePlaybackPositionCommand.isEnabled = true
      c.playCommand.addTarget { [weak self] _ in self?.play(); return .success }
      c.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
      c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
      c.nextTrackCommand.addTarget { _ in AuroraAudio.shared.emit(["e": "remote", "cmd": "next"]); return .success }
      c.previousTrackCommand.addTarget { _ in AuroraAudio.shared.emit(["e": "remote", "cmd": "previous"]); return .success }
      c.changePlaybackPositionCommand.addTarget { event in
        guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
        AuroraAudio.shared.emit(["e": "remote", "cmd": "seek", "ms": Int(e.positionTime * 1000)])
        return .success
      }
      UIApplication.shared.beginReceivingRemoteControlEvents()
    }
  }

  private func voice() -> Voice? {
    let a = AuroraAudio.shared
    if let v = a.voices[a.activeId], v.hasMedia { return v }
    return a.voices.values.first(where: { $0.hasMedia })
  }

  private func play() {
    AuroraAudio.shared.q.async {
      AuroraAudio.shared.ensureRunning()
      self.voice()?.play()
    }
  }

  private func pause() {
    AuroraAudio.shared.q.async {
      for v in AuroraAudio.shared.voices.values where v.isPlaying { v.pause() }
    }
  }

  private func toggle() {
    AuroraAudio.shared.q.async {
      if AuroraAudio.shared.voices.values.contains(where: { $0.isPlaying }) {
        for v in AuroraAudio.shared.voices.values where v.isPlaying { v.pause() }
      } else {
        AuroraAudio.shared.ensureRunning()
        self.voice()?.play()
      }
    }
  }

  /// Title, artist, artwork, duration, position and play state from Dart.
  func update(_ a: [String: Any]) {
    var d: [String: Any] = [:]
    d[MPMediaItemPropertyTitle] = a["title"] as? String ?? ""
    d[MPMediaItemPropertyArtist] = a["artist"] as? String ?? ""
    d[MPMediaItemPropertyAlbumTitle] = a["album"] as? String ?? ""
    let dur = Double((a["durMs"] as? Int) ?? 0) / 1000
    if dur > 0 { d[MPMediaItemPropertyPlaybackDuration] = dur }
    d[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double((a["posMs"] as? Int) ?? 0) / 1000
    let playing = (a["playing"] as? Bool) ?? false
    d[MPNowPlayingInfoPropertyPlaybackRate] = playing ? ((a["rate"] as? Double) ?? 1.0) : 0.0
    d[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
    let url = a["artUrl"] as? String ?? ""
    DispatchQueue.main.async {
      if url != self.artUrl {
        self.artUrl = url
        self.artwork = nil
        self.loadArt(url)
      }
      if let art = self.artwork { d[MPMediaItemPropertyArtwork] = art }
      self.info = d
      MPNowPlayingInfoCenter.default().nowPlayingInfo = d
      MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }
  }

  private func loadArt(_ s: String) {
    guard !s.isEmpty else { return }
    let load: (UIImage?) -> Void = { img in
      guard let img = img else { return }
      DispatchQueue.main.async {
        guard s == self.artUrl else { return }
        let art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        self.artwork = art
        var d = self.info
        d[MPMediaItemPropertyArtwork] = art
        self.info = d
        MPNowPlayingInfoCenter.default().nowPlayingInfo = d
      }
    }
    if s.hasPrefix("http"), let u = URL(string: s) {
      URLSession.shared.dataTask(with: u) { data, _, _ in load(data.flatMap { UIImage(data: $0) }) }.resume()
    } else {
      let path = s.hasPrefix("file://") ? String(s.dropFirst(7)) : s
      load(UIImage(contentsOfFile: path))
    }
  }
}
