-keep class androidx.lifecycle.DefaultLifecycleObserver
-keep class com.pauldemarco.flutter_blue.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }

-keep class com.arthenica.mobileffmpeg.Config {
    native <methods>;
    void log(long, int, byte[]);
    void statistics(long, int, float, float, long , int, double, double);
}

-keep class com.arthenica.mobileffmpeg.AbiDetect {
    native <methods>;
}
-keep class org.videolan.libvlc.** { *; }

#Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class de.prosiebensat1digital.** { *; }
