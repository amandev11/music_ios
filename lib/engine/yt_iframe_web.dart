import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

@JS('auroraYT')
external _AuroraYt? get _yt;

extension type _AuroraYt._(JSObject _) implements JSObject {
  external void setCallback(JSFunction f);
  external void load(String id);
  external void play();
  external void pause();
  external void seek(double seconds);
  external void setRate(double rate);
  external void setVolume(double percent);
  external double time();
  external double duration();
}

/// Thin wrapper over `window.auroraYT` (see web/index.html).
class YtIframe {
  bool get available => _yt != null;

  void setCallback(void Function(String type, num value) cb) {
    _yt?.setCallback(((JSString type, JSNumber value) => cb(type.toDart, value.toDartDouble)).toJS);
  }

  void load(String id) => _yt?.load(id);
  void play() => _yt?.play();
  void pause() => _yt?.pause();
  void seek(double seconds) => _yt?.seek(seconds);
  void setRate(double rate) => _yt?.setRate(rate);
  void setVolume(double percent) => _yt?.setVolume(percent);
  double time() => _yt?.time() ?? 0;
  double duration() => _yt?.duration() ?? 0;
}

String blobUrlFor(List<int> bytes, String mime) {
  final data = Uint8List.fromList(bytes);
  final blob = web.Blob([data.toJS].toJS, web.BlobPropertyBag(type: mime));
  return web.URL.createObjectURL(blob);
}
