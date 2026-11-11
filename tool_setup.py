#!/usr/bin/env python3
"""Generates the platform folders with `flutter create`, then overlays the native Android engine.

Run once from the project root:  python3 tool_setup.py
"""
import os, re, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
os.chdir(ROOT)

FLUTTER = shutil.which("flutter") or "flutter"
subprocess.check_call([
    FLUTTER, "create", "--project-name", "aurora_music", "--org", "com.aurora",
    "--platforms", "android,ios,macos,windows,linux,web", ".",
])

# Re-assert our own entry files that `flutter create` may have replaced.
shutil.copyfile("template/main.dart", "lib/main.dart")
shutil.copyfile("template/index.html", "web/index.html")

NATIVE = os.path.join(ROOT, "native", "android")
APP = os.path.join(ROOT, "android", "app")
MAIN = os.path.join(APP, "src", "main")

# 1. Remove the generated Kotlin/Java MainActivity; ours (com.aurora.music) replaces it.
shutil.rmtree(os.path.join(MAIN, "kotlin"), ignore_errors=True)
shutil.rmtree(os.path.join(MAIN, "java"), ignore_errors=True)

def copytree(src, dst):
    shutil.copytree(src, dst, dirs_exist_ok=True)

copytree(os.path.join(NATIVE, "kotlin"), os.path.join(MAIN, "kotlin"))
copytree(os.path.join(NATIVE, "java"), os.path.join(MAIN, "java"))
copytree(os.path.join(NATIVE, "assets"), os.path.join(MAIN, "assets"))
copytree(os.path.join(NATIVE, "res"), os.path.join(MAIN, "res"))
shutil.copyfile(os.path.join(NATIVE, "proguard-rules.pro"), os.path.join(APP, "proguard-rules.pro"))

# 2. Manifest: permissions, service, Android Auto, application class.
manifest_path = os.path.join(MAIN, "AndroidManifest.xml")
m = open(manifest_path, encoding="utf-8").read()
perms = """
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
"""
if "READ_MEDIA_AUDIO" not in m:
    m = re.sub(r"(<manifest[^>]*>)", r"\1" + perms, m, count=1)
m = re.sub(r'android:name="\$\{applicationName\}"', 'android:name=".MusicApp"', m)
m = m.replace('android:name=".MainActivity"', 'android:name="com.aurora.music.MainActivity"')
service = """
        <meta-data
            android:name="com.google.android.gms.car.application"
            android:resource="@xml/automotive_app_desc" />

        <service
            android:name="com.aurora.music.playback.PlaybackService"
            android:exported="true"
            android:foregroundServiceType="mediaPlayback">
            <intent-filter>
                <action android:name="androidx.media3.session.MediaLibraryService" />
                <action android:name="androidx.media3.session.MediaSessionService" />
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>
"""
widget = """
        <receiver
            android:name="com.aurora.music.widget.NowPlayingWidget"
            android:exported="true"
            android:label="Now Playing">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/now_playing_widget_info" />
        </receiver>

        <!-- audio_service (iOS/macOS only) would otherwise steal hardware media buttons on Android. -->
        <service android:name="com.ryanheise.audioservice.AudioService" tools:node="remove" />
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver" tools:node="remove" />
"""
if "PlaybackService" not in m:
    m = m.replace("</application>", service + widget + "    </application>", 1)
if "xmlns:tools" not in m:
    m = m.replace("<manifest ", '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)
if "largeHeap" not in m:
    m = m.replace("<application", '<application android:largeHeap="true"', 1)
open(manifest_path, "w", encoding="utf-8").write(m)

# 3. Gradle (Kotlin DSL; Flutter >= 3.29 generates .kts).
gradle_path = os.path.join(APP, "build.gradle.kts")
if not os.path.exists(gradle_path):
    sys.exit("android/app/build.gradle.kts not found: upgrade Flutter (>= 3.29) so the template uses Kotlin DSL.")
g = open(gradle_path, encoding="utf-8").read()
g = re.sub(r'namespace\s*=\s*"[^"]+"', 'namespace = "com.aurora.music"', g)
g = re.sub(r'applicationId\s*=\s*"[^"]+"', 'applicationId = "com.aurora.music"', g)
g = re.sub(r'minSdk\s*=\s*[^\n]+', 'minSdk = 26', g)
if "stripNewPipeExtractorUtils" not in g:
    g += '''

android {
    compileOptions { isCoreLibraryDesugaringEnabled = true }
    buildTypes { release { proguardFiles("proguard-rules.pro") } }
    androidResources { noCompress += "onnx" }
    packaging { resources.excludes += "/META-INF/{AL2.0,LGPL2.1}" }
}

// NewPipeExtractor v0.26.3. native/android/java carries BitChord's patched Utils.java at the same
// package path, so the library's own Utils.class is stripped before dexing.
val newPipeExtractorRaw: Configuration by configurations.creating {
    isTransitive = false
    isCanBeConsumed = false
}
val newPipeExtractorStripped = tasks.register<org.gradle.api.tasks.bundling.Jar>("stripNewPipeExtractorUtils") {
    archiveFileName.set("NewPipeExtractor-v0.26.3-noutils.jar")
    destinationDirectory.set(layout.buildDirectory.dir("stripped-libs"))
    from(provider { newPipeExtractorRaw.map { zipTree(it) } }) {
        exclude("org/schabi/newpipe/extractor/utils/Utils.class")
        exclude("org/schabi/newpipe/extractor/utils/Utils\\$*.class")
    }
}

dependencies {
    newPipeExtractorRaw("com.github.TeamNewPipe:NewPipeExtractor:v0.26.3")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.media3:media3-exoplayer:1.8.0")
    implementation("androidx.media3:media3-session:1.8.0")
    implementation("androidx.media3:media3-datasource:1.8.0")
    implementation("androidx.media3:media3-datasource-okhttp:1.8.0")
    implementation("androidx.media3:media3-database:1.8.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-guava:1.10.2")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.22.0")
    implementation(files(newPipeExtractorStripped))
    implementation("com.github.TeamNewPipe:nanojson:e9d656ddb49a412a5a0a5d5ef20ca7ef09549996")
    implementation("org.jsoup:jsoup:1.22.2")
    implementation("com.google.code.findbugs:jsr305:3.0.2")
    implementation("com.google.protobuf:protobuf-javalite:4.35.0")
    implementation("org.mozilla:rhino:1.8.1")
    implementation("org.mozilla:rhino-engine:1.8.1")
}
'''
open(gradle_path, "w", encoding="utf-8").write(g)

root_gradle = os.path.join(ROOT, "android", "build.gradle.kts")
rg = open(root_gradle, encoding="utf-8").read()
if "jitpack" not in rg:
    rg += '\nallprojects {\n    repositories {\n        maven("https://jitpack.io")\n    }\n}\n'
    open(root_gradle, "w", encoding="utf-8").write(rg)

# 4. iOS / macOS: background audio and network client entitlement.
ios_plist = os.path.join(ROOT, "ios", "Runner", "Info.plist")
if os.path.exists(ios_plist):
    p = open(ios_plist, encoding="utf-8").read()
    if "UIBackgroundModes" not in p:
        p = p.replace("</dict>\n</plist>", "\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>audio</string>\n\t</array>\n</dict>\n</plist>")
        open(ios_plist, "w", encoding="utf-8").write(p)
    if "NSAppTransportSecurity" not in p:
        p = p.replace("</dict>\n</plist>", "\t<key>NSAppTransportSecurity</key>\n\t<dict>\n\t\t<key>NSAllowsLocalNetworking</key>\n\t\t<true/>\n\t</dict>\n</dict>\n</plist>")
        open(ios_plist, "w", encoding="utf-8").write(p)
podfile = os.path.join(ROOT, "ios", "Podfile")
if os.path.exists(podfile):
    pf = open(podfile, encoding="utf-8").read()
    pf = re.sub(r"#?\s*platform :ios, '[^']*'", "platform :ios, '13.0'", pf, count=1)
    open(podfile, "w", encoding="utf-8").write(pf)
for ent in ("DebugProfile.entitlements", "Release.entitlements"):
    path = os.path.join(ROOT, "macos", "Runner", ent)
    if os.path.exists(path):
        e = open(path, encoding="utf-8").read()
        if "network.client" not in e:
            e = e.replace("</dict>", "\t<key>com.apple.security.network.client</key>\n\t<true/>\n\t<key>com.apple.security.files.user-selected.read-only</key>\n\t<true/>\n</dict>")
            open(path, "w", encoding="utf-8").write(e)


# 4b. Windows: webview_windows uses <experimental/coroutine>, which MSVC 14.51 (Visual Studio 18) rejects
# unless this is defined before the plugins are added. Safe on older toolchains.
win_cmake = os.path.join(ROOT, "windows", "CMakeLists.txt")
if os.path.exists(win_cmake):
    w = open(win_cmake, encoding="utf-8").read()
    if "_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS" not in w:
        define = "add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)\n"
        key = "include(flutter/generated_plugins.cmake)"
        if key in w:
            w = w.replace(key, define + key, 1)
            open(win_cmake, "w", encoding="utf-8").write(w)

# 5. App name "Music" on every platform (best effort: files differ slightly between Flutter versions).
def sub_file(path, pattern, repl, flags=0):
    if not os.path.exists(path):
        return
    txt = open(path, encoding="utf-8", errors="ignore").read()
    new = re.sub(pattern, repl, txt, flags=flags)
    if new != txt:
        open(path, "w", encoding="utf-8").write(new)

sub_file(manifest_path, r'android:label="[^"]*"', 'android:label="Music"')
sub_file(ios_plist, r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)", r"\1Music\2")
sub_file(ios_plist, r"(<key>CFBundleName</key>\s*<string>)[^<]*(</string>)", r"\1Music\2")
sub_file(os.path.join(ROOT, "macos", "Runner", "Configs", "AppInfo.xcconfig"), r"PRODUCT_NAME = .*", "PRODUCT_NAME = Music")
sub_file(os.path.join(ROOT, "windows", "runner", "main.cpp"), r'L"aurora_music"', 'L"Music"')
sub_file(os.path.join(ROOT, "windows", "runner", "Runner.rc"), r'(VALUE "(?:ProductName|FileDescription)", )"[^"]*"', r'\1"Music"')
sub_file(os.path.join(ROOT, "linux", "runner", "my_application.cc"), r'"aurora_music"', '"Music"')
sub_file(os.path.join(ROOT, "web", "manifest.json"), r'"(name|short_name)":\s*"[^"]*"', r'"\1": "Music"')

# 6. Launcher icons from assets/icon/icon.png for every platform.
subprocess.check_call(["flutter", "pub", "get"] if not shutil.which("flutter") else [shutil.which("flutter"), "pub", "get"])
subprocess.check_call([shutil.which("dart") or "dart", "run", "flutter_launcher_icons"])

print("\nDone. Next: flutter run -d <android|ios|macos|windows|linux|chrome>")
