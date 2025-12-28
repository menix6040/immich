import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:immich_mobile/utils/hooks/app_settings_update_hook.dart';
import 'package:immich_mobile/widgets/settings/settings_slider_list_tile.dart';
import 'package:immich_mobile/widgets/settings/settings_sub_title.dart';
import 'package:immich_mobile/widgets/settings/settings_switch_list_tile.dart';

class MemoryMusicSetting extends HookConsumerWidget {
  const MemoryMusicSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabledSetting = useAppSettingsState(AppSettingsEnum.memoryMusicEnabled);
    final volumeSetting = useAppSettingsState(AppSettingsEnum.memoryMusicVolume);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSubTitle(title: "Memories music"),
        SettingsSwitchListTile(
          valueNotifier: enabledSetting,
          title: "Enable music in memories",
        ),
        SettingsSliderListTile(
          enabled: enabledSetting.value,
          valueNotifier: volumeSetting,
          text: "Volume: ${volumeSetting.value}%",
          maxValue: 100.0,
          noDivisons: 10,
          label: "${volumeSetting.value}%",
        ),
      ],
    );
  }
}
