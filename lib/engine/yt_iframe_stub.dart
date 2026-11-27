/// Non-web stub: the IFrame player only exists in a browser.
class YtIframe {
  bool get available => false;
  void setCallback(void Function(String type, num value) cb) {}
  void load(String id) {}
  void play() {}
  void pause() {}
  void seek(double seconds) {}
  void setRate(double rate) {}
  void setVolume(double percent) {}
  double time() => 0;
  double duration() => 0;
}

String blobUrlFor(List<int> bytes, String mime) => '';
