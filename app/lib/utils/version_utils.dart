bool isNewerVersion(String candidate, String current) {
  final left = _parts(candidate);
  final right = _parts(current);
  for (var index = 0; index < 3; index++) {
    if (left[index] != right[index]) return left[index] > right[index];
  }
  return false;
}

List<int> _parts(String version) {
  final match = RegExp(
    r'^(?:v)?(\d+)\.(\d+)\.(\d+)',
  ).firstMatch(version.trim());
  if (match == null) return const [0, 0, 0];
  return [
    for (var index = 1; index <= 3; index++) int.parse(match.group(index)!),
  ];
}
