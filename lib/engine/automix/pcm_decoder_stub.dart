import 'dart:typed_data';

import '../../sources/source.dart';

/// Browsers cannot decode a cross-origin stream to raw samples, so Automix falls back to plain
/// crossfades there.
const bool pcmDecodingSupported = false;

Future<Int16List?> decodeToPcm(Playable p, {int sampleRate = 11025}) async => null;
