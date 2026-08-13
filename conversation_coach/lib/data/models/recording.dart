/// Where the audio came from.
enum AudioSource { builtin, usb }

/// Recording(id, sessionId, encryptedPath, sampleRate, channels,
///           source[builtin|usb], channelMap) — Tech Spec §7.
///
/// The captured audio is stored locally and encrypted at rest (F-CAP-09); the
/// key lives in the OS keystore. [encryptedPath] points at the on-disk blob.
class Recording {
  final String id;
  final String sessionId;
  final String encryptedPath;
  final int sampleRate;
  final int channels;
  final AudioSource source;

  /// Maps a channel index to a speaker label where hardware separation exists
  /// (e.g. a two-transmitter DJI kit) — F-CAP-03. Empty for mono/mixed audio.
  final Map<int, String> channelMap;

  /// "Mark moment" timestamps (ms) the user flagged during recording (F-CAP-06).
  final List<int> markedMomentsMs;

  const Recording({
    required this.id,
    required this.sessionId,
    required this.encryptedPath,
    required this.sampleRate,
    required this.channels,
    required this.source,
    this.channelMap = const {},
    this.markedMomentsMs = const [],
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'sessionId': sessionId,
        'encryptedPath': encryptedPath,
        'sampleRate': sampleRate,
        'channels': channels,
        'source': source.name,
        'channelMap': channelMap.entries
            .map((e) => '${e.key}:${e.value}')
            .join(','),
        'markedMomentsMs':
            markedMomentsMs.map((e) => e.toString()).join(','),
      };

  factory Recording.fromMap(Map<String, dynamic> m) {
    final cm = <int, String>{};
    final raw = (m['channelMap'] as String?) ?? '';
    if (raw.isNotEmpty) {
      for (final pair in raw.split(',')) {
        final idx = pair.indexOf(':');
        if (idx > 0) {
          cm[int.parse(pair.substring(0, idx))] = pair.substring(idx + 1);
        }
      }
    }
    final marks = ((m['markedMomentsMs'] as String?) ?? '')
        .split(',')
        .where((e) => e.isNotEmpty)
        .map(int.parse)
        .toList();
    return Recording(
      id: m['id'] as String,
      sessionId: m['sessionId'] as String,
      encryptedPath: m['encryptedPath'] as String,
      sampleRate: m['sampleRate'] as int,
      channels: m['channels'] as int,
      source: AudioSource.values
          .firstWhere((s) => s.name == m['source'], orElse: () => AudioSource.builtin),
      channelMap: cm,
      markedMomentsMs: marks,
    );
  }
}
