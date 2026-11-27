/// Lets low-level code ask "is this song saved on the device?" without importing the UI or app layers.
class OfflineIndex {
  /// File path of the saved copy of [mediaId], or null. Installed by [DownloadManager].
  static String? Function(String mediaId) pathOf = (_) => null;
}
