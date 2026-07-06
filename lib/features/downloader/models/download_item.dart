// lib/features/downloader/models/download_item.dart

enum DownloadStatus { pending, preparing, downloading, completed, failed, cancelled }
enum DownloadType   { videoWithAudio, audioOnly }
enum SourcePlatform {
  youtube, instagram, tiktok, twitter,
  facebook, reddit, vimeo, dailymotion, direct, unknown,
}

// ── Extension: display strings ─────────────────────────────────────
extension SourcePlatformExt on SourcePlatform {
  String get displayName => switch (this) {
    SourcePlatform.youtube     => 'YouTube',
    SourcePlatform.instagram   => 'Instagram',
    SourcePlatform.tiktok      => 'TikTok',
    SourcePlatform.twitter     => 'Twitter / X',
    SourcePlatform.facebook    => 'Facebook',
    SourcePlatform.reddit      => 'Reddit',
    SourcePlatform.vimeo       => 'Vimeo',
    SourcePlatform.dailymotion => 'Dailymotion',
    SourcePlatform.direct      => 'Direct Link',
    SourcePlatform.unknown     => 'Video',
  };

  String get emoji => switch (this) {
    SourcePlatform.youtube     => '▶️',
    SourcePlatform.instagram   => '📸',
    SourcePlatform.tiktok      => '🎵',
    SourcePlatform.twitter     => '𝕏',
    SourcePlatform.facebook    => '📘',
    SourcePlatform.reddit      => '🔴',
    SourcePlatform.vimeo       => '🎬',
    SourcePlatform.dailymotion => '📺',
    SourcePlatform.direct      => '🔗',
    SourcePlatform.unknown     => '🌐',
  };
}

// ── Quality option ─────────────────────────────────────────────────
class DownloadQualityOption {
  final String label;         // "1080p", "720p", "Audio MP3"
  final String url;           // actual download URL
  final int?   fileSizeBytes; // nullable, estimated
  final bool   isAudioOnly;
  final String mimeType;      // "video/mp4", "audio/mpeg"
  final String fileExtension; // "mp4", "mp3", "m4a"

  const DownloadQualityOption({
    required this.label,
    required this.url,
    required this.isAudioOnly,
    required this.mimeType,
    required this.fileExtension,
    this.fileSizeBytes,
  });

  Map<String, dynamic> toJson() => {
    'label': label, 'url': url, 'fileSizeBytes': fileSizeBytes,
    'isAudioOnly': isAudioOnly, 'mimeType': mimeType,
    'fileExtension': fileExtension,
  };

  factory DownloadQualityOption.fromJson(Map<String, dynamic> j) =>
      DownloadQualityOption(
        label        : j['label'] as String,
        url          : j['url']   as String,
        fileSizeBytes: j['fileSizeBytes'] as int?,
        isAudioOnly  : j['isAudioOnly']  as bool,
        mimeType     : j['mimeType']     as String,
        fileExtension: j['fileExtension'] as String,
      );
}

// ── VideoInfo (fetched before download starts) ─────────────────────
class VideoInfo {
  final String title;
  final String author;
  final String? thumbnailUrl;
  final SourcePlatform platform;
  final int durationSecs;
  final List<DownloadQualityOption> qualities;

  const VideoInfo({
    required this.title,
    required this.author,
    required this.platform,
    required this.durationSecs,
    required this.qualities,
    this.thumbnailUrl,
  });
}

// ── Main download item ─────────────────────────────────────────────
class DownloadItem {
  final String id;
  final String originalUrl;
  final String title;
  final String? thumbnailUrl;
  final SourcePlatform platform;

  String filePath;
  DownloadStatus status;
  double progress;
  String? errorMessage;
  DateTime createdAt;
  DateTime? completedAt;
  DownloadType downloadType;
  String qualityLabel;
  int fileSizeBytes;
  int downloadedBytes;
  // BUG-DL03 FIX: store the exact URL + extension used so retry can
  // re-use them instead of re-fetching and always picking qualities.first
  String retryUrl;
  String retryExt;

  DownloadItem({
    required this.id,
    required this.originalUrl,
    required this.title,
    required this.platform,
    required this.filePath,
    required this.status,
    required this.progress,
    required this.createdAt,
    required this.downloadType,
    required this.qualityLabel,
    required this.fileSizeBytes,
    required this.downloadedBytes,
    this.thumbnailUrl,
    this.errorMessage,
    this.completedAt,
    this.retryUrl  = '',
    this.retryExt  = 'mp4',
  });

  Map<String, dynamic> toJson() => {
    'id'             : id,
    'originalUrl'    : originalUrl,
    'title'          : title,
    'thumbnailUrl'   : thumbnailUrl,
    'platform'       : platform.name,
    'filePath'       : filePath,
    'status'         : status.name,
    'progress'       : progress,
    'errorMessage'   : errorMessage,
    'createdAt'      : createdAt.toIso8601String(),
    'completedAt'    : completedAt?.toIso8601String(),
    'downloadType'   : downloadType.name,
    'qualityLabel'   : qualityLabel,
    'fileSizeBytes'  : fileSizeBytes,
    'downloadedBytes': downloadedBytes,
    'retryUrl'       : retryUrl,
    'retryExt'       : retryExt,
  };

  factory DownloadItem.fromJson(Map<String, dynamic> j) => DownloadItem(
    id           : j['id']          as String,
    originalUrl  : j['originalUrl'] as String,
    title        : j['title']       as String,
    thumbnailUrl : j['thumbnailUrl'] as String?,
    platform     : SourcePlatform.values.firstWhere(
        (p) => p.name == (j['platform'] as String),
        orElse: () => SourcePlatform.unknown),
    filePath     : j['filePath']     as String,
    status       : DownloadStatus.values.firstWhere(
        (s) => s.name == (j['status'] as String),
        orElse: () => DownloadStatus.failed),
    progress     : (j['progress'] as num).toDouble(),
    errorMessage : j['errorMessage'] as String?,
    createdAt    : DateTime.parse(j['createdAt'] as String),
    completedAt  : j['completedAt'] != null
        ? DateTime.parse(j['completedAt'] as String) : null,
    downloadType : DownloadType.values.firstWhere(
        (t) => t.name == (j['downloadType'] as String),
        orElse: () => DownloadType.videoWithAudio),
    qualityLabel  : j['qualityLabel']   as String,
    fileSizeBytes : (j['fileSizeBytes'] as int?) ?? 0,
    downloadedBytes: (j['downloadedBytes'] as int?) ?? 0,
    retryUrl      : (j['retryUrl'] as String?) ?? '',
    retryExt      : (j['retryExt'] as String?) ?? 'mp4',
  );
}
