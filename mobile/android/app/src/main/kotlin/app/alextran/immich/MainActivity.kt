package app.alextran.immich

import android.content.Context
import android.os.Build
import android.os.ext.SdkExtensions
import android.app.ActivityManager
import android.os.PowerManager
import app.alextran.immich.background.BackgroundEngineLock
import app.alextran.immich.background.BackgroundWorkerApiImpl
import app.alextran.immich.background.BackgroundWorkerFgHostApi
import app.alextran.immich.background.BackgroundWorkerLockApi
import app.alextran.immich.background.MemoryNotificationScheduler
import app.alextran.immich.connectivity.ConnectivityApi
import app.alextran.immich.connectivity.ConnectivityApiImpl
import app.alextran.immich.core.ImmichPlugin
import app.alextran.immich.images.ThumbnailApi
import app.alextran.immich.images.ThumbnailsImpl
import app.alextran.immich.sync.NativeSyncApi
import app.alextran.immich.sync.NativeSyncApiImpl26
import app.alextran.immich.sync.NativeSyncApiImpl30
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    registerPlugins(this, flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "immich/debug")
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "scheduleMemoryWorkerInMinutes" -> {
            val minutes = call.argument<Int>("minutes") ?: 1
            MemoryNotificationScheduler.scheduleDebug(this, minutes.toLong())
            result.success(null)
          }
          else -> result.notImplemented()
        }
      }
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "immich/system")
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "getBackgroundConditions" -> {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val backgroundRestricted =
              if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) activityManager.isBackgroundRestricted else false
            val batteryOptimizationsIgnored = powerManager.isIgnoringBatteryOptimizations(packageName)
            result.success(
              mapOf(
                "backgroundRestricted" to backgroundRestricted,
                "batteryOptimizationsIgnored" to batteryOptimizationsIgnored
              )
            )
          }
          else -> result.notImplemented()
        }
      }
  }

  companion object {
    fun registerPlugins(ctx: Context, flutterEngine: FlutterEngine) {
      val messenger = flutterEngine.dartExecutor.binaryMessenger
      val backgroundEngineLockImpl = BackgroundEngineLock(ctx)
      BackgroundWorkerLockApi.setUp(messenger, backgroundEngineLockImpl)
      val nativeSyncApiImpl =
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) < 1) {
          NativeSyncApiImpl26(ctx)
        } else {
          NativeSyncApiImpl30(ctx)
        }
      NativeSyncApi.setUp(messenger, nativeSyncApiImpl)
      ThumbnailApi.setUp(messenger, ThumbnailsImpl(ctx))
      BackgroundWorkerFgHostApi.setUp(messenger, BackgroundWorkerApiImpl(ctx))
      ConnectivityApi.setUp(messenger, ConnectivityApiImpl(ctx))

      flutterEngine.plugins.add(BackgroundServicePlugin())
      flutterEngine.plugins.add(HttpSSLOptionsPlugin())
      flutterEngine.plugins.add(backgroundEngineLockImpl)
      flutterEngine.plugins.add(nativeSyncApiImpl)
    }

    fun cancelPlugins(flutterEngine: FlutterEngine) {
      val nativeApi =
        flutterEngine.plugins.get(NativeSyncApiImpl26::class.java) as ImmichPlugin?
          ?: flutterEngine.plugins.get(NativeSyncApiImpl30::class.java) as ImmichPlugin?
      nativeApi?.detachFromEngine()
    }
  }
}
