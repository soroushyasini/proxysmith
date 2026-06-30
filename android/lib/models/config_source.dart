/// A selectable subscription source preset.
class ConfigSource {
  final String label;
  final String? url; // null = custom URL, user provides their own inline
  final bool isUserDefined;
  final String? id; // stable id for user-defined sources (for edit/delete)

  const ConfigSource({
    required this.label,
    this.url,
    this.isUserDefined = false,
    this.id,
  });

  bool get isCustom => url == null;

  Map<String, dynamic> toJson() => {
        'label': label,
        'url': url,
        'id': id,
      };

  factory ConfigSource.fromJson(Map<String, dynamic> json) => ConfigSource(
        label: json['label'] as String,
        url: json['url'] as String,
        isUserDefined: true,
        id: json['id'] as String,
      );
}

/// The built-in presets shown in the CONFIG SOURCE dropdown.
/// First entry is preselected by default.
/// To add or change built-in sources later, edit only this list.
const List<ConfigSource> kBuiltInSources = [
  ConfigSource(
    label: 'Epodonios (recommended)',
    url: 'https://raw.githubusercontent.com/Epodonios/v2ray-configs/refs/heads/main/All_Configs_Sub.txt',
  ),
  ConfigSource(
    label: 'barry-far',
    url: 'https://raw.githubusercontent.com/barry-far/V2ray-Config/refs/heads/main/All_Configs_Sub.txt',
  ),
  ConfigSource(
    label: 'EbraSha',
    url: 'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/V2Ray-Config-By-EbraSha-All-Type.txt',
  ),
];

/// The literal "Custom URL" entry, always last in the dropdown.
const ConfigSource kCustomUrlSource = ConfigSource(label: 'Custom URL', url: null);
