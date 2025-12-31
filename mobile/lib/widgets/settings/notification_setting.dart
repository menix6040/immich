import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/notification_permission.provider.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:immich_mobile/services/background.service.dart';
import 'package:immich_mobile/services/local_notification.service.dart';
import 'package:immich_mobile/services/memory_notification.service.dart';
import 'package:immich_mobile/utils/hooks/app_settings_update_hook.dart';
import 'package:immich_mobile/widgets/settings/settings_button_list_tile.dart';
import 'package:immich_mobile/widgets/settings/settings_slider_list_tile.dart';
import 'package:immich_mobile/widgets/settings/settings_sub_page_scaffold.dart';
import 'package:immich_mobile/widgets/settings/settings_switch_list_tile.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:logging/logging.dart';
import 'package:flutter/services.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

const _debugChannel = MethodChannel('immich/debug');
const _systemChannel = MethodChannel('immich/system');

class NotificationSetting extends HookConsumerWidget {
  const NotificationSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = Logger("NotificationSetting");
    final permissionService = ref.watch(notificationPermissionProvider);
    final askedBatteryOptimization = useState(false);
    final askedBackgroundRestricted = useState(false);

    final sliderValue = useAppSettingsState(AppSettingsEnum.uploadErrorNotificationGracePeriod);
    final totalProgressValue = useAppSettingsState(AppSettingsEnum.backgroundBackupTotalProgress);
    final singleProgressValue = useAppSettingsState(AppSettingsEnum.backgroundBackupSingleProgress);

    final hasPermission = permissionService == PermissionStatus.granted;

    Future<void> openAppNotificationSettings(BuildContext ctx) async {
      ctx.pop();
      await openAppSettings();
    }

    // When permissions are permanently denied, you need to go to settings to
    // allow them
    showPermissionsDialog() {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          content: const Text('notification_permission_dialog_content').tr(),
          actions: [
            TextButton(child: const Text('cancel').tr(), onPressed: () => ctx.pop()),
            TextButton(onPressed: () => openAppNotificationSettings(ctx), child: const Text('settings').tr()),
          ],
        ),
      );
    }

    void showBatteryOptimizationInfoToUser() {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) {
          return AlertDialog(
            title: const Text('backup_controller_page_background_battery_info_title').tr(),
            content: SingleChildScrollView(
              child: const Text('backup_controller_page_background_battery_info_message').tr(),
            ),
            actions: [
              ElevatedButton(
                onPressed: () async {
                  await launchUrl(
                    Uri.parse('https://dontkillmyapp.com'),
                    mode: LaunchMode.externalApplication,
                  );
                },
                child: const Text(
                  "backup_controller_page_background_battery_info_link",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ).tr(),
              ),
              ElevatedButton(
                child: const Text(
                  'backup_controller_page_background_battery_info_ok',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ).tr(),
                onPressed: () => ctx.pop(),
              ),
            ],
          );
        },
      );
    }

    useEffect(() {
      if (!Platform.isAndroid || askedBatteryOptimization.value) {
        return null;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final isIgnoring = await ref.read(backgroundServiceProvider).isIgnoringBatteryOptimizations();
        if (!isIgnoring && !askedBatteryOptimization.value) {
          askedBatteryOptimization.value = true;
          showBatteryOptimizationInfoToUser();
        }

        if (!askedBackgroundRestricted.value) {
          try {
            final result = await _systemChannel.invokeMethod<Map<Object?, Object?>>('getBackgroundConditions');
            final restricted = result?['backgroundRestricted'] == true;
            if (restricted) {
              askedBackgroundRestricted.value = true;
              await showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Background activity restricted'),
                  content: const Text(
                    'Background activity is restricted for Immich. '
                    'Please allow background activity in system settings.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        await openAppSettings();
                        ctx.pop();
                      },
                      child: const Text('Open settings'),
                    ),
                    TextButton(onPressed: () => ctx.pop(), child: const Text('OK')),
                  ],
                ),
              );
            }
          } catch (_) {}
        }
      });
      return null;
    }, [askedBatteryOptimization.value]);

    final String formattedValue = _formatSliderValue(sliderValue.value.toDouble());

    final notificationSettings = [
      if (!hasPermission)
        SettingsButtonListTile(
          icon: Icons.notifications_outlined,
          title: 'notification_permission_list_tile_title'.tr(),
          subtileText: 'notification_permission_list_tile_content'.tr(),
          buttonText: 'notification_permission_list_tile_enable_button'.tr(),
          onButtonTap: () async {
            final permission = await ref
                .watch(notificationPermissionProvider.notifier)
                .requestNotificationPermission();
            if (permission == PermissionStatus.permanentlyDenied) {
              showPermissionsDialog();
            }
          },
        ),
      SettingsSwitchListTile(
        enabled: hasPermission,
        valueNotifier: totalProgressValue,
        title: 'setting_notifications_total_progress_title'.tr(),
        subtitle: 'setting_notifications_total_progress_subtitle'.tr(),
      ),
      SettingsSwitchListTile(
        enabled: hasPermission,
        valueNotifier: singleProgressValue,
        title: 'setting_notifications_single_progress_title'.tr(),
        subtitle: 'setting_notifications_single_progress_subtitle'.tr(),
      ),
      SettingsSliderListTile(
        enabled: hasPermission,
        valueNotifier: sliderValue,
        text: 'setting_notifications_notify_failures_grace_period'.tr(namedArgs: {'duration': formattedValue}),
        maxValue: 5.0,
        noDivisons: 5,
        label: formattedValue,
      ),
      SettingsButtonListTile(
        icon: Icons.shield_outlined,
        title: 'Check background conditions',
        subtileText: 'Notifications, battery optimization, background limits',
        buttonText: 'Check',
        onButtonTap: () async {
          final notificationStatus = ref.read(notificationPermissionProvider);
          final notificationGranted = notificationStatus == PermissionStatus.granted;
          final batteryOptimizationIgnored = Platform.isAndroid
              ? await ref.read(backgroundServiceProvider).isIgnoringBatteryOptimizations()
              : true;
          bool backgroundRestricted = false;
          if (Platform.isAndroid) {
            try {
              final result = await _systemChannel.invokeMethod<Map<Object?, Object?>>('getBackgroundConditions');
              if (result != null) {
                backgroundRestricted = result['backgroundRestricted'] == true;
              }
            } catch (_) {}
          }

          if (!notificationGranted) {
            await ref.read(notificationPermissionProvider.notifier).requestNotificationPermission();
          }

          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Background conditions'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Notifications: ${notificationGranted ? "allowed" : "not allowed"}'),
                  Text('Battery optimization: ${batteryOptimizationIgnored ? "ignored" : "enabled"}'),
                  Text('Background restricted: ${backgroundRestricted ? "yes" : "no"}'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => ctx.pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        },
      ),
      if (kDebugMode)
        SettingsButtonListTile(
          icon: Icons.notifications_active_outlined,
          title: 'Debug: memory notification test',
          subtileText: 'Send a test memories notification now',
          buttonText: 'Send',
          onButtonTap: () async {
            if (!hasPermission) {
              await ref.read(notificationPermissionProvider.notifier).requestNotificationPermission();
            }
            final template = ref.read(memoryNotificationServiceProvider).debugRandomTemplate(count: 3);
            await ref.read(localNotificationService).showMemoryNotificationCustom(
              title: template.title,
              body: template.body,
            );
          },
        ),
      if (kDebugMode)
        SettingsButtonListTile(
          icon: Icons.schedule_outlined,
          title: 'Debug: memory notification in 1 minute',
          subtileText: 'Schedule a single memories notification 1 minute from now',
          buttonText: 'Schedule',
          onButtonTap: () async {
            if (!hasPermission) {
              await ref.read(notificationPermissionProvider.notifier).requestNotificationPermission();
            }
            final template = ref.read(memoryNotificationServiceProvider).debugRandomTemplate(count: 3);
            final nowLocal = DateTime.now();
            final scheduledDateTime = nowLocal.add(const Duration(minutes: 1));
            final scheduled = tz.TZDateTime.from(scheduledDateTime, tz.local);
            await ref.read(localNotificationService).scheduleMemoryNotifications(
                  title: template.title,
                  body: template.body,
                  scheduleTimes: [scheduled],
                );
            log.info(
              "Scheduled debug memory notification at $scheduled (local $scheduledDateTime, tz=${tz.local.name}, offset=${nowLocal.timeZoneOffset})",
            );
          },
        ),
      if (kDebugMode)
        SettingsButtonListTile(
          icon: Icons.alarm_outlined,
          title: 'Debug: memory worker in 1 minute',
          subtileText: 'Schedule WorkManager worker in 1 minute',
          buttonText: 'Schedule',
          onButtonTap: () async {
            await Store.put(StoreKey.memoryNotificationDebugForce, true);
            await _debugChannel.invokeMethod<void>('scheduleMemoryWorkerInMinutes', {'minutes': 1});
            log.info("Scheduled debug WorkManager worker in 1 minute");
          },
        ),
    ];

    return SettingsSubPageScaffold(settings: notificationSettings);
  }
}

String _formatSliderValue(double v) {
  if (v == 0.0) {
    return 'setting_notifications_notify_immediately'.tr();
  } else if (v == 1.0) {
    return 'setting_notifications_notify_minutes'.tr(namedArgs: {'count': '30'});
  } else if (v == 2.0) {
    return 'setting_notifications_notify_hours'.tr(namedArgs: {'count': '2'});
  } else if (v == 3.0) {
    return 'setting_notifications_notify_hours'.tr(namedArgs: {'count': '8'});
  } else if (v == 4.0) {
    return 'setting_notifications_notify_hours'.tr(namedArgs: {'count': '24'});
  } else {
    return 'setting_notifications_notify_never'.tr();
  }
}
