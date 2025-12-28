import 'dart:math';
import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/platform/background_worker_api.g.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/db.provider.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/providers/infrastructure/memory.provider.dart';
import 'package:immich_mobile/providers/notification_permission.provider.dart';
import 'package:immich_mobile/services/local_notification.service.dart';
import 'package:immich_mobile/services/memory.service.dart';
import 'package:immich_mobile/utils/bootstrap.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;

final memoryNotificationServiceProvider = Provider((ref) => MemoryNotificationService(ref));

class MemoryNotificationService {
  MemoryNotificationService(this._ref);

  final Ref _ref;
  final _log = Logger("MemoryNotificationService");

  static const int _dayStartHour = 9;
  static const int _dayEndHour = 21;
  static const List<_MemoryNotificationTemplate> _templates = [
    _MemoryNotificationTemplate(
      title: "Трохи подорожі в часі ⏳",
      singleBody: "На тебе чекає один спогад ✨",
      pluralBody: "На тебе чекають {count} спогадів ✨",
    ),
    _MemoryNotificationTemplate(
      title: "Повернись у минуле 📸",
      singleBody: "Сьогодні на тебе чекає один спогад 💭",
      pluralBody: "Сьогодні на тебе чекають {count} спогадів 💭",
    ),
    _MemoryNotificationTemplate(
      title: "Твої спогади ❤️",
      singleBody: "Один новий спогад уже готовий для тебе",
      pluralBody: "{count} нових спогадів уже готові для тебе",
    ),
    _MemoryNotificationTemplate(
      title: "Час для флешбеку 🌅",
      singleBody: "Є один спогад, який варто переглянути",
      pluralBody: "Є {count} спогадів, які варто переглянути",
    ),
    _MemoryNotificationTemplate(
      title: "Колись давно… 🌙",
      singleBody: "У тебе є один спогад, до якого можна повернутися",
      pluralBody: "У тебе є {count} спогадів, до яких можна повернутися",
    ),
  ];

  Future<void> scheduleInBackground() async {
    if (Platform.isAndroid) {
      return;
    }
    if (!_ref.read(authProvider).isAuthenticated) {
      return;
    }

    final currentUser = Store.tryGet(StoreKey.currentUser);
    if (currentUser == null || !currentUser.memoryEnabled) {
      return;
    }

    final permission = _ref.read(notificationPermissionProvider);
    if (!permission.isGranted) {
      return;
    }

    try {
      final int count = await _loadMemoryCount();
      if (count <= 0) {
        await _ref.read(localNotificationService).cancelMemoryNotifications();
        return;
      }

      final lastCount = Store.tryGet(StoreKey.memoryNotificationLastCount) ?? 0;
      if (count < lastCount) {
        await Store.put(StoreKey.memoryNotificationLastCount, count);
        await _ref.read(localNotificationService).cancelMemoryNotifications();
        return;
      }

      if (count == lastCount) {
        return;
      }

      final scheduleTimes = _randomScheduleTimes();
      final template = _randomTemplate();
      final title = template.title;
      final body = template.bodyForCount(count);

      await _ref.read(localNotificationService).cancelMemoryNotifications();
      await _ref
          .read(localNotificationService)
          .scheduleMemoryNotifications(title: title, body: body, scheduleTimes: scheduleTimes);

      await Store.put(StoreKey.memoryNotificationLastCount, count);
    } catch (e, stack) {
      _log.warning("Failed to schedule memories notification", e, stack);
    }
  }

  Future<void> cancelInForeground() {
    return _ref.read(localNotificationService).cancelMemoryNotifications();
  }

  Future<int> _loadMemoryCount() async {
    if (Store.isBetaTimelineEnabled) {
      final service = _ref.read(driftMemoryServiceProvider);
      return service.getCount();
    }

    final service = _ref.read(memoryServiceProvider);
    final memories = await service.getMemoryLane();
    return memories?.length ?? 0;
  }

  List<tz.TZDateTime> _randomScheduleTimes() {
    final nowLocal = DateTime.now();
    final random = Random();
    final days = <int>{};
    while (days.length < 2) {
      days.add(random.nextInt(7));
    }

    return days.map((offset) {
      final hour = _dayStartHour + random.nextInt(_dayEndHour - _dayStartHour);
      final minute = random.nextInt(60);
      var scheduledLocal = DateTime(nowLocal.year, nowLocal.month, nowLocal.day, hour, minute)
          .add(Duration(days: offset));

      if (!scheduledLocal.isAfter(nowLocal)) {
        scheduledLocal = scheduledLocal.add(const Duration(days: 1));
      }

      return tz.TZDateTime.from(scheduledLocal, tz.local);
    }).toList()..sort((a, b) => a.compareTo(b));
  }

  _MemoryNotificationTemplate _randomTemplate() {
    final random = Random();
    return _templates[random.nextInt(_templates.length)];
  }

  _MemoryNotificationTemplate debugRandomTemplate() => _randomTemplate();

  Future<void> showIfNewMemoriesNow() async {
    if (!_ref.read(authProvider).isAuthenticated) {
      return;
    }

    final currentUser = Store.tryGet(StoreKey.currentUser);
    if (currentUser == null || !currentUser.memoryEnabled) {
      return;
    }

    final permission = _ref.read(notificationPermissionProvider);
    if (!permission.isGranted) {
      return;
    }

    try {
      final int count = await _loadMemoryCount();
      if (count <= 0) {
        return;
      }

      final lastCount = Store.tryGet(StoreKey.memoryNotificationLastCount) ?? 0;
      if (count <= lastCount) {
        return;
      }

      final template = _randomTemplate();
      await _ref.read(localNotificationService).showMemoryNotificationCustom(
        title: template.title,
        body: template.bodyForCount(count),
      );
      await Store.put(StoreKey.memoryNotificationLastCount, count);
    } catch (e, stack) {
      _log.warning("Failed to show memories notification", e, stack);
    }
  }
}

@pragma('vm:entry-point')
Future<void> memoryNotificationWorkerEntrypoint() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final (isar, drift, logDb) = await Bootstrap.initDB();
  await Bootstrap.initDomain(isar, drift, logDb, shouldBufferLogs: false, listenStoreUpdates: false);

  final container = ProviderContainer(
    overrides: [
      dbProvider.overrideWithValue(isar),
      isarProvider.overrideWithValue(isar),
      driftProvider.overrideWith(driftOverride(drift)),
    ],
  );

  final notificationService = container.read(localNotificationService);
  await notificationService.setup();
  final debugForce = Store.tryGet(StoreKey.memoryNotificationDebugForce) ?? false;
  if (debugForce) {
    final template = container.read(memoryNotificationServiceProvider).debugRandomTemplate();
    await notificationService.showMemoryNotificationCustom(
      title: template.title,
      body: template.bodyForCount(3),
    );
    await Store.put(StoreKey.memoryNotificationDebugForce, false);
  } else {
    await container.read(memoryNotificationServiceProvider).showIfNewMemoriesNow();
  }
  await BackgroundWorkerBgHostApi().close();
  container.dispose();
}

class _MemoryNotificationTemplate {
  final String title;
  final String singleBody;
  final String pluralBody;

  const _MemoryNotificationTemplate({required this.title, required this.singleBody, required this.pluralBody});

  String bodyForCount(int count) {
    if (count == 1) {
      return singleBody;
    }
    return pluralBody.replaceAll("{count}", count.toString());
  }
}
