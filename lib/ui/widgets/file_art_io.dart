import 'dart:io';

import 'package:flutter/painting.dart';

ImageProvider? fileArt(String path) {
  final f = File(path.startsWith('file://') ? path.substring(7) : path);
  return f.existsSync() ? FileImage(f) : null;
}
