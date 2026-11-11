import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' hide Playable;

import '../../sources/source.dart';

const bool pcmDecodingSupported = true;

/// Decodes a stream or file to mono 16-bit PCM by running a hidden mpv instance with its raw PCM
/// writer as the audio output and clock sync turned off, so it decodes as fast as the data arrives.
Future<Int16List?> decodeToPcm(Playable p, {int sampleRate = 11025}) async {
  final url = p.url;
  if (url == null) return null;
  // iPhone/iPad/Mac: decode with Apple's own audio stack (always present, no libmpv output driver needed).
  if (Platform.isIOS || Platform.isMacOS) {
    final native = await _decodeNative(url, p.headers, sampleRate);
    if (native != null) return native;
  }
  return _decodeMpv(p, url, sampleRate);
}

const _pcmChannel = MethodChannel('aurora/pcm');

Future<Int16List?> _decodeNative(String url, Map<String, String> headers, int sampleRate) async {
  try {
    final bytes = await _pcmChannel
        .invokeMethod<Uint8List>('decode', {'url': url, 'headers': headers, 'sampleRate': sampleRate, 'maxSeconds': 900})
        .timeout(const Duration(seconds: 90));
    if (bytes == null || bytes.length < sampleRate * 2 * 20) return null;
    final even = Uint8List.fromList(bytes.sublist(0, bytes.length - bytes.length % 2));
    return even.buffer.asInt16List();
  } catch (e) {
    debugPrint('Automix: native decode failed, trying mpv: $e');
    return null;
  }
}

Future<Int16List?> _decodeMpv(Playable p, String url, int sampleRate) async {
  Directory? dir;
  Player? player;
  try {
    dir = await Directory.systemTemp.createTemp('amx');
    final out = '${dir.path}${Platform.pathSeparator}a.pcm';
    player = Player(configuration: const PlayerConfiguration(title: 'Music analysis'));
    final native = player.platform;
    if (native is! NativePlayer) return null;
    await native.setProperty('vo', 'null');
    await native.setProperty('ao', 'pcm');
    await native.setProperty('ao-pcm-file', out);
    await native.setProperty('ao-pcm-waveheader', 'no');
    await native.setProperty('audio-samplerate', '$sampleRate');
    await native.setProperty('audio-channels', 'mono');
    await native.setProperty('audio-format', 's16');
    await native.setProperty('untimed', 'yes');
    await native.setProperty('end', '900');
    // Finish on completion, but give up at once when mpv reports an error (instead of waiting out the timeout).
    final finished = Completer<void>();
    final subDone = player.stream.completed.listen((c) {
      if (c && !finished.isCompleted) finished.complete();
    });
    final subErr = player.stream.error.listen((e) {
      if (e.isNotEmpty && !finished.isCompleted) finished.completeError(StateError(e));
    });
    try {
      await player.open(Media(url, httpHeaders: p.headers.isEmpty ? null : p.headers), play: true);
      await finished.future.timeout(Duration(seconds: Platform.isIOS ? 45 : 90));
    } finally {
      await subDone.cancel();
      await subErr.cancel();
    }
    await player.dispose();
    player = null;
    final f = File(out);
    if (!await f.exists()) return null;
    final bytes = await f.readAsBytes();
    if (bytes.length < sampleRate * 2 * 20) return null;
    // Copy so the view is aligned regardless of how the file buffer was allocated.
    final copy = Uint8List.fromList(bytes.sublist(0, bytes.length - bytes.length % 2));
    return copy.buffer.asInt16List();
  } catch (e) {
    debugPrint('Automix: decode failed: $e');
    return null;
  } finally {
    try {
      await player?.dispose();
    } catch (_) {}
    try {
      await dir?.delete(recursive: true);
    } catch (_) {}
  }
}
