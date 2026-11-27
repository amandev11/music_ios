/// Short breadcrumbs of what each stage of the YouTube pipeline did for the current song, appended to the
/// "Couldn't play" message so a failure says exactly where it happened.
class YtTrace {
  static final _items = <String>[];

  static void log(String s) {
    if (_items.length < 14) _items.add(s);
  }

  static void clear() => _items.clear();

  static String take() {
    if (_items.isEmpty) return '';
    final s = _items.join(' > ');
    _items.clear();
    return s;
  }
}
