package app.alextran.immich.background

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import java.time.Duration
import java.time.LocalDateTime
import java.util.concurrent.ThreadLocalRandom
import java.util.concurrent.TimeUnit

private const val TAG = "MemoryNotificationScheduler"

object MemoryNotificationScheduler {
  private const val WORK_NAME_PREFIX = "immich/MemoryNotificationV1"
  private const val WORK_NAME_1 = "$WORK_NAME_PREFIX-1"
  private const val WORK_NAME_2 = "$WORK_NAME_PREFIX-2"
  private const val WORK_NAME_DEBUG = "$WORK_NAME_PREFIX-debug"
  private const val START_HOUR = 9
  private const val END_HOUR = 21

  fun scheduleNext(context: Context) {
    val times = randomScheduleTimes()
    enqueue(context, WORK_NAME_1, times[0])
    enqueue(context, WORK_NAME_2, times[1])
  }

  fun scheduleDebug(context: Context, delayMinutes: Long) {
    val delayMillis = TimeUnit.MINUTES.toMillis(delayMinutes).coerceAtLeast(0)
    val builder = OneTimeWorkRequest.Builder(MemoryNotificationWorker::class.java)
      .setInitialDelay(delayMillis, TimeUnit.MILLISECONDS)
      .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.MINUTES)
    if (delayMillis == 0L) {
      builder.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
    }
    val request: OneTimeWorkRequest = builder.build()

    WorkManager.getInstance(context).enqueueUniqueWork(WORK_NAME_DEBUG, ExistingWorkPolicy.REPLACE, request)
    Log.i(TAG, "Scheduled debug worker in ${delayMillis / 1000}s")
  }

  private fun enqueue(context: Context, workName: String, targetTime: LocalDateTime) {
    val now = LocalDateTime.now()
    val delay = Duration.between(now, targetTime)
    val delayMillis = delay.toMillis().coerceAtLeast(0)

    val request: OneTimeWorkRequest = OneTimeWorkRequest.Builder(MemoryNotificationWorker::class.java)
      .setInitialDelay(delayMillis, TimeUnit.MILLISECONDS)
      .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.MINUTES)
      .build()

    WorkManager.getInstance(context).enqueueUniqueWork(workName, ExistingWorkPolicy.REPLACE, request)
    Log.i(TAG, "Scheduled $workName in ${delayMillis / 1000}s at $targetTime")
  }

  private fun randomScheduleTimes(): List<LocalDateTime> {
    val now = LocalDateTime.now()
    val days = mutableSetOf<Int>()
    val rng = ThreadLocalRandom.current()
    while (days.size < 2) {
      days.add(rng.nextInt(0, 7))
    }

    return days.map { offset ->
      val hour = rng.nextInt(START_HOUR, END_HOUR)
      val minute = rng.nextInt(0, 60)
      var time = now.withHour(hour).withMinute(minute).withSecond(0).withNano(0).plusDays(offset.toLong())
      if (time.isBefore(now)) {
        time = time.plusDays(7)
      }
      time
    }.sorted()
  }
}
