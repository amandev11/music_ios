import 'source.dart';

/// Browsers never go through the local proxy.
Future<Playable> proxyPlayable(Playable p) async => p;

Future<String> proxySelfTest(Playable p) async => 'not used on the web';

Future<Playable?> fetchPlayable(Playable p) async => p;

Future<Playable?> localCopyFor(Playable proxied) async => null;

bool nativeOnlyYoutube = false;
