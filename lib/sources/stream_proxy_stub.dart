import 'source.dart';

/// Browsers never go through the local proxy.
Future<Playable> proxyPlayable(Playable p) async => p;

Future<String> proxySelfTest(Playable p) async => 'not used on the web';

Future<Playable?> fetchPlayable(Playable p) async => p;

Future<Playable?> localCopyFor(Playable proxied) async => null;

bool nativeOnlyYoutube = false;

Future<({String path, int bytes})?> saveStream(
  Playable p,
  String name, {
  void Function(double)? progress,
}) async => null;

Future<bool> fileExists(String path) async => false;

Future<void> deleteSavedFile(String path) async {}

Future<String> keepDirPath() async => '';

Future<String?> saveArtwork(String url, String name) async => null;
