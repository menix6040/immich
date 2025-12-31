import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/backup/manual_upload.provider.dart';
import 'package:immich_mobile/providers/notification_permission.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:immich_mobile/utils/debug_print.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:logging/logging.dart';

final localNotificationService = Provider(
  (ref) => LocalNotificationService(ref),
);

class LocalNotificationService {
  final FlutterLocalNotificationsPlugin _localNotificationPlugin = FlutterLocalNotificationsPlugin();
  final Ref ref;
  final _log = Logger("LocalNotificationService");

  LocalNotificationService(this.ref);

  static const manualUploadNotificationID = 4;
  static const manualUploadDetailedNotificationID = 5;
  static const manualUploadChannelName = 'Manual Asset Upload';
  static const manualUploadChannelID = 'immich/manualUpload';
  static const manualUploadChannelNameDetailed = 'Manual Asset Upload Detailed';
  static const manualUploadDetailedChannelID = 'immich/manualUploadDetailed';
  static const cancelUploadActionID = 'cancel_upload';
  static const memoryNotificationID = 6;
  static const memoryNotificationSecondaryID = 7;
  static const memoryChannelName = 'Memories';
  static const memoryChannelID = 'immich/memories';
  static const memoryNotificationPayload = 'memories';

  Future<void> setup() async {
    const androidSetting = AndroidInitializationSettings('@drawable/notification_icon');
    const iosSetting = DarwinInitializationSettings();

    const initSettings = InitializationSettings(android: androidSetting, iOS: iosSetting);

    await _localNotificationPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onDidReceiveForegroundNotificationResponse,
    );
  }

  Future<void> _showOrUpdateNotification(
    int id,
    String title,
    String body,
    AndroidNotificationDetails androidNotificationDetails,
    DarwinNotificationDetails iosNotificationDetails, {
    String? payload,
  }) async {
    final notificationDetails = NotificationDetails(android: androidNotificationDetails, iOS: iosNotificationDetails);

    if (_hasPermission()) {
      await _localNotificationPlugin.show(id, title, body, notificationDetails, payload: payload);
    }
  }

  Future<void> closeNotification(int id) {
    return _localNotificationPlugin.cancel(id);
  }

  Future<void> showOrUpdateManualUploadStatus(
    String title,
    String body, {
    bool? isDetailed,
    bool? presentBanner,
    bool? showActions,
    int? maxProgress,
    int? progress,
  }) {
    var notificationlId = manualUploadNotificationID;
    var androidChannelID = manualUploadChannelID;
    var androidChannelName = manualUploadChannelName;
    // Separate Notification for Info/Alerts and Progress
    if (isDetailed != null && isDetailed) {
      notificationlId = manualUploadDetailedNotificationID;
      androidChannelID = manualUploadDetailedChannelID;
      androidChannelName = manualUploadChannelNameDetailed;
    }
    // Progress notification
    final androidNotificationDetails = (maxProgress != null && progress != null)
        ? AndroidNotificationDetails(
            androidChannelID,
            androidChannelName,
            ticker: title,
            showProgress: true,
            onlyAlertOnce: true,
            maxProgress: maxProgress,
            progress: progress,
            indeterminate: false,
            playSound: false,
            priority: Priority.low,
            importance: Importance.low,
            ongoing: true,
            actions: (showActions ?? false)
                ? <AndroidNotificationAction>[
                    const AndroidNotificationAction(cancelUploadActionID, 'Cancel', showsUserInterface: true),
                  ]
                : null,
          )
        // Non-progress notification
        : AndroidNotificationDetails(androidChannelID, androidChannelName, playSound: false);

    final iosNotificationDetails = DarwinNotificationDetails(
      presentBadge: true,
      presentList: true,
      presentBanner: presentBanner,
    );

    return _showOrUpdateNotification(notificationlId, title, body, androidNotificationDetails, iosNotificationDetails);
  }

  Future<void> showMemoryNotification({required int count}) {
    final title = "New memories";
    final body = count == 1 ? "You have 1 memory to revisit." : "You have $count memories to revisit.";
    return showMemoryNotificationCustom(title: title, body: body);
  }

  Future<void> showMemoryNotificationCustom({required String title, required String body}) {
    const androidNotificationDetails = AndroidNotificationDetails(
      memoryChannelID,
      memoryChannelName,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosNotificationDetails = DarwinNotificationDetails(
      presentBadge: true,
      presentList: true,
      presentBanner: true,
    );

    return _showOrUpdateNotification(
      memoryNotificationID,
      title,
      body,
      androidNotificationDetails,
      iosNotificationDetails,
      payload: memoryNotificationPayload,
    );
  }

  Future<void> cancelMemoryNotifications() async {
    await _localNotificationPlugin.cancel(memoryNotificationID);
    await _localNotificationPlugin.cancel(memoryNotificationSecondaryID);
  }

  Future<void> scheduleMemoryNotifications({
    required String title,
    required String body,
    required List<tz.TZDateTime> scheduleTimes,
  }) async {
    if (!_hasPermission()) {
      _log.info("Memory notification schedule skipped: no permission");
      return;
    }

    const androidNotificationDetails = AndroidNotificationDetails(
      memoryChannelID,
      memoryChannelName,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosNotificationDetails = DarwinNotificationDetails(
      presentBadge: true,
      presentList: true,
      presentBanner: true,
    );
    const details = NotificationDetails(android: androidNotificationDetails, iOS: iosNotificationDetails);

    final ids = [memoryNotificationID, memoryNotificationSecondaryID];
    for (int i = 0; i < scheduleTimes.length && i < ids.length; i++) {
      _log.info("Scheduling memory notification id=${ids[i]} at ${scheduleTimes[i]} (tz=${scheduleTimes[i].location.name})");
      try {
        await _localNotificationPlugin.zonedSchedule(
          ids[i],
          title,
          body,
          scheduleTimes[i],
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          payload: memoryNotificationPayload,
        );
      } on PlatformException {
        rethrow;
      }
    }
  }

  void _onDidReceiveForegroundNotificationResponse(NotificationResponse notificationResponse) {
    if (notificationResponse.payload == memoryNotificationPayload) {
      _openMemories();
      return;
    }

    // Handle notification actions
    switch (notificationResponse.actionId) {
      case cancelUploadActionID:
        {
          dPrint(() => "User cancelled manual upload operation");
          ref.read(manualUploadProvider.notifier).cancelBackup();
        }
    }
  }

  void _openMemories() {
    final router = ref.read(appRouterProvider);
    if (Store.isBetaTimelineEnabled) {
      router.replaceAll([const TabShellRoute(children: [MainTimelineRoute()])]);
      return;
    }

    router.replaceAll([const TabControllerRoute(children: [PhotosRoute()])]);
  }

  bool _hasPermission() {
    return ref.read(notificationPermissionProvider) == PermissionStatus.granted;
  }
}
