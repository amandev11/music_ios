# ONNX Runtime and Media3
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**
-keep class androidx.media3.session.** { *; }

# NewPipeExtractor, nanojson, jsoup, protobuf-lite and Rhino all use reflection / service lookup.
# R8 stripping them was a release-only startup/playback crash.
-keep class org.schabi.newpipe.extractor.** { *; }
-keep class com.grack.nanojson.** { *; }
-keep class org.jsoup.** { *; }
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }
-keep class org.mozilla.javascript.** { *; }
-keep class org.mozilla.classfile.** { *; }
-keep class javax.script.** { *; }
-keepclassmembers class * implements javax.script.ScriptEngineFactory { *; }

# App code (widget, bridge, service are referenced from the manifest and by reflection).
-keep class com.aurora.music.** { *; }

# Optional classes referenced by dependencies that do not exist on Android.
-dontwarn java.beans.**
-dontwarn org.mozilla.javascript.**
-dontwarn javax.script.**
-dontwarn javax.lang.model.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**
-dontwarn okhttp3.internal.platform.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
