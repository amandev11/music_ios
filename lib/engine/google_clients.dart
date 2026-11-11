/// googlevideo answers 403, or throttles to a crawl, when the request's headers disagree with the
/// client that minted the URL. The URL names that client in its `c` parameter, so dress to match.
Map<String, String> googleVideoHeaders(String url) {
  final uri = Uri.tryParse(url);
  final host = uri?.host ?? '';
  if (uri == null || !host.endsWith('googlevideo.com')) return const {};
  const webUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36';
  final client = (uri.queryParameters['c'] ?? '').toUpperCase();
  if (client.startsWith('IOS')) {
    return const {'User-Agent': 'com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)'};
  }
  if (client == 'ANDROID_VR') {
    return const {
      'User-Agent':
          'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip'
    };
  }
  if (client == 'ANDROID_MUSIC') {
    return const {
      'User-Agent':
          'com.google.android.apps.youtube.music/8.39.42 (Linux; U; Android 15; en_US; Pixel 9 Pro; Build/AP4A.250205.002) gzip'
    };
  }
  if (client.startsWith('ANDROID')) {
    return const {
      'User-Agent':
          'com.google.android.youtube/21.26.364 (Linux; U; Android 15; en_US; Pixel 9 Pro; Build/AP4A.250205.002; Cronet/132.0.6834.79) gzip'
    };
  }
  if (client == 'WEB_REMIX') {
    return const {'User-Agent': webUa, 'Origin': 'https://music.youtube.com', 'Referer': 'https://music.youtube.com/'};
  }
  if (client.startsWith('WEB') || client == 'MWEB' || client.startsWith('TVHTML5')) {
    return const {'User-Agent': webUa, 'Origin': 'https://www.youtube.com', 'Referer': 'https://www.youtube.com/'};
  }
  return const {'User-Agent': webUa};
}
