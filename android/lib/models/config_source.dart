/// A selectable subscription source preset.
class ConfigSource {
  final String label;
  final String? url; // null = custom URL, user provides their own

  const ConfigSource({required this.label, this.url});

  bool get isCustom => url == null;
}

/// The list shown in the CONFIG SOURCE dropdown.
/// First entry is preselected by default.
/// To add or change sources later, edit only this list.
const List<ConfigSource> kConfigSources = [
  ConfigSource(
    label: 'barry-far (recommended)',
    url: 'https://raw.githubusercontent.com/barry-far/V2ray-Config/refs/heads/main/All_Configs_Sub.txt',
  ),
  ConfigSource(
    label: 'EbraSha — all types',
    url: 'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/V2Ray-Config-By-EbraSha-All-Type.txt',
  ),
  ConfigSource(
    label: 'EbraSha — extracted configs',
    url: 'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/all_extracted_configs.txt',
  ),
  ConfigSource(label: 'Custom URL', url: null),
];
