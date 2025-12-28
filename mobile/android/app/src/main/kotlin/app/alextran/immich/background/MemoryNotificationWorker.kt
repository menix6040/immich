package app.alextran.immich.background

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.work.ListenableWorker
import androidx.work.WorkerParameters
import app.alextran.immich.MainActivity
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader

private const val TAG = "MemoryNotificationWorker"

class MemoryNotificationWorker(context: Context, params: WorkerParameters) :
  ListenableWorker(context, params), BackgroundWorkerBgHostApi {
  private val ctx: Context = context.applicationContext

  private var loader: FlutterLoader = FlutterInjector.instance().flutterLoader()
  private var engine: FlutterEngine? = null
  private val completionHandler: SettableFuture<Result> = SettableFuture.create()
  private var isComplete = false

  override fun startWork(): ListenableFuture<Result> {
    Log.i(TAG, "Starting memory notification worker")

    if (!loader.initialized()) {
      loader.startInitialization(ctx)
    }

    loader.ensureInitializationCompleteAsync(ctx, null, Handler(Looper.getMainLooper())) {
      engine = FlutterEngine(ctx)
      FlutterEngineCache.getInstance().put(ENGINE_CACHE_KEY, engine!!)

      MainActivity.registerPlugins(ctx, engine!!)
      try {
        io.flutter.plugins.GeneratedPluginRegistrant.registerWith(engine!!)
      } catch (e: Throwable) {
        Log.w(TAG, "GeneratedPluginRegistrant not available: ${e.message}")
      }

      BackgroundWorkerBgHostApi.setUp(engine!!.dartExecutor.binaryMessenger, this)

      engine!!.dartExecutor.executeDartEntrypoint(
        DartExecutor.DartEntrypoint(
          loader.findAppBundlePath(),
          "package:immich_mobile/services/memory_notification.service.dart",
          "memoryNotificationWorkerEntrypoint"
        )
      )
    }

    return completionHandler
  }

  override fun onInitialized() {
    // Not used by this worker.
  }

  override fun close() {
    if (isComplete) {
      return
    }
    complete(Result.success())
  }

  override fun onStopped() {
    Log.d(TAG, "MemoryNotificationWorker stopped")
    complete(Result.success())
  }

  private fun complete(result: Result) {
    if (isComplete) {
      return
    }
    isComplete = true

    try {
      if (engine != null) {
        MainActivity.cancelPlugins(engine!!)
      }
    } catch (_: Throwable) {}

    engine?.destroy()
    engine = null
    FlutterEngineCache.getInstance().remove(ENGINE_CACHE_KEY)

    MemoryNotificationScheduler.scheduleNext(ctx)
    completionHandler.set(result)
  }

  companion object {
    private const val ENGINE_CACHE_KEY = "immich::memory_notification::engine"
  }
}
