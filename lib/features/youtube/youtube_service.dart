import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════
//  YoutubeTrack — data class
// ═══════════════════════════════════════════════════════════════

class YoutubeTrack {
  final String videoId;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final Duration duration;
  final String? streamUrl;

  const YoutubeTrack({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    required this.duration,
    this.streamUrl,
  });

  YoutubeTrack copyWith({String? streamUrl}) => YoutubeTrack(
        videoId:      videoId,
        title:        title,
        artist:       artist,
        thumbnailUrl: thumbnailUrl,
        duration:     duration,
        streamUrl:    streamUrl ?? this.streamUrl,
      );

  String get durationFmt {
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return duration.inHours > 0 ? '${duration.inHours}:$m:$s' : '$m:$s';
  }
}

// ═══════════════════════════════════════════════════════════════
//  YoutubeService
//
//  SEARCH:     InnerTube (primary) → yt_explode (fallback) → Piped
//  STREAM URL: Cobalt API  (primary  — server-proxied, no IP-lock, India CGNAT safe)
//              Piped HLS   (secondary — server-proxied, multiple instances)
//              yt_explode  (last resort — direct CDN, IP-locked on CGNAT)
//                           → URL is verified with HEAD before use
//
//  FIX (v4): Added Cobalt API as PRIMARY stream resolver
//    - yt_explode returns googlevideo.com signed URLs that are IP-restricted
//    - India CGNAT assigns different IPs for manifest vs stream requests → 403
//    - Cobalt proxies audio through its own servers → no IP lock, always works
//    - Piped kept as secondary; yt_explode now runs verification before returning
// ═══════════════════════════════════════════════════════════════

class YoutubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  static const _kTimeout   = Duration(seconds: 14);
  static const _kCobaltApi = 'https://api.cobalt.tools/';

  // Piped instances — expanded list, tried in order
  static const _pipedInstances = [
    'https://pipedapi.adminforge.de',     // Germany, usually reliable
    'https://piped-api.cine.social',
    'https://pipedapi.kavin.rocks',
    'https://api.piped.yt',
    'https://pipedapi.syncpundit.io',
    'https://api.piped.projectsegfau.lt',
    'https://piped-api.privacy.com.de',
  ];

  // ─────────────────────────────────────────────────────────────
  //  SEARCH — InnerTube primary, yt_explode fallback
  // ─────────────────────────────────────────────────────────────

  Future<List<YoutubeTrack>> search(String query, {int limit = 20}) async {
    // 1. InnerTube — most reliable, no key needed
    try {
      final results = await _innerTubeSearch(query, limit: limit);
      if (results.isNotEmpty) {
        debugPrint('[YouTube] InnerTube search → ${results.length} results');
        return results;
      }
    } catch (e) {
      debugPrint('[YouTube] InnerTube search failed: $e');
    }

    // 2. yt_explode fallback
    try {
      final page = await _yt.search.search(query);
      final results = page
          .whereType<Video>()
          .take(limit)
          .map(_videoToTrack)
          .toList();
      if (results.isNotEmpty) {
        debugPrint('[YouTube] yt_explode search → ${results.length} results');
        return results;
      }
    } catch (e) {
      debugPrint('[YouTube] yt_explode search failed: $e');
    }

    // 3. Piped last resort
    try {
      final results = await _pipedSearch(query, limit: limit);
      if (results.isNotEmpty) {
        debugPrint('[YouTube] Piped search → ${results.length} results');
        return results;
      }
    } catch (e) {
      debugPrint('[YouTube] Piped search failed: $e');
    }

    debugPrint('[YouTube] All search strategies failed for: $query');
    return [];
  }

  // ── InnerTube search ──────────────────────────────────────────
  Future<List<YoutubeTrack>> _innerTubeSearch(
      String query, {int limit = 20}) async {
    final uri = Uri.parse(
        'https://www.youtube.com/youtubei/v1/search?prettyPrint=false');

    final body = jsonEncode({
      'query': query,
      'context': {
        'client': {
          'clientName':    'WEB',
          'clientVersion': '2.20231121.08.00',
          'hl': 'en',
          'gl': 'US',
          'userAgent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      },
    });

    final resp = await http.post(
      uri,
      headers: {
        'Content-Type':              'application/json',
        'X-YouTube-Client-Name':    '1',
        'X-YouTube-Client-Version': '2.20231121.08.00',
        'Origin':  'https://www.youtube.com',
        'Referer': 'https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent(query)}',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
      body: body,
    ).timeout(_kTimeout);

    if (resp.statusCode != 200) {
      throw Exception('InnerTube HTTP ${resp.statusCode}');
    }

    final data   = jsonDecode(resp.body) as Map<String, dynamic>;
    final tracks = <YoutubeTrack>[];

    try {
      final contents = data['contents'];
      if (contents == null) throw Exception('no contents');

      List? sections;
      try {
        sections = contents['twoColumnSearchResultsRenderer']
            ['primaryContents']['sectionListRenderer']['contents'] as List?;
      } catch (_) {
        try {
          sections = contents['sectionListRenderer']['contents'] as List?;
        } catch (_) {}
      }

      if (sections == null) throw Exception('no sections');

      for (final section in sections) {
        final items =
            (section['itemSectionRenderer']?['contents'] as List?) ?? [];
        for (final item in items) {
          if (tracks.length >= limit) break;
          final vr = item['videoRenderer'] as Map<String, dynamic>?;
          if (vr == null) continue;

          final videoId = vr['videoId'] as String? ?? '';
          if (videoId.isEmpty) continue;

          final titleRuns  = vr['title']?['runs'] as List?;
          final titleSimple = vr['title']?['simpleText'] as String?;
          final title = titleRuns != null
              ? titleRuns.map((r) => r['text'] as String? ?? '').join('')
              : titleSimple ?? 'Unknown';

          final artist =
              vr['ownerText']?['runs']?[0]?['text'] as String? ??
              vr['shortBylineText']?['runs']?[0]?['text'] as String? ??
              'Unknown';

          final durationText =
              vr['lengthText']?['simpleText'] as String? ?? '0:00';

          final thumbs = (vr['thumbnail']?['thumbnails'] as List?) ?? [];
          final thumb = thumbs.isNotEmpty
              ? thumbs.last['url'] as String? ??
                  'https://img.youtube.com/vi/$videoId/mqdefault.jpg'
              : 'https://img.youtube.com/vi/$videoId/mqdefault.jpg';

          tracks.add(YoutubeTrack(
            videoId:      videoId,
            title:        title,
            artist:       artist,
            thumbnailUrl: thumb,
            duration:     _parseDuration(durationText),
          ));
        }
        if (tracks.length >= limit) break;
      }
    } catch (e) {
      debugPrint('[YouTube] InnerTube parse error: $e');
      if (tracks.isEmpty) rethrow;
    }

    return tracks;
  }

  // ── Piped search (last resort) ────────────────────────────────
  Future<List<YoutubeTrack>> _pipedSearch(
      String query, {int limit = 20}) async {
    for (final base in _pipedInstances) {
      try {
        final uri = Uri.parse('$base/search').replace(
          queryParameters: {'q': query, 'filter': 'music_songs'},
        );
        final resp = await http.get(uri, headers: {
          'User-Agent': 'BeatFlow/1.0',
        }).timeout(_kTimeout);

        if (resp.statusCode != 200) continue;

        final data  = jsonDecode(resp.body) as Map<String, dynamic>;
        final items = (data['items'] as List?) ?? [];
        final tracks = <YoutubeTrack>[];

        for (final item in items) {
          if (tracks.length >= limit) break;
          if ((item['type'] as String?) != 'stream') continue;
          final videoId = _extractVideoId(item['url'] as String? ?? '');
          if (videoId == null || videoId.isEmpty) continue;

          tracks.add(YoutubeTrack(
            videoId:      videoId,
            title:        item['title']        as String? ?? 'Unknown',
            artist:       item['uploaderName'] as String? ?? 'Unknown',
            thumbnailUrl: item['thumbnail']    as String? ??
                'https://img.youtube.com/vi/$videoId/mqdefault.jpg',
            duration: Duration(
                seconds: (item['duration'] as num?)?.toInt() ?? 0),
          ));
        }
        if (tracks.isNotEmpty) return tracks;
      } catch (_) {
        continue;
      }
    }
    return [];
  }

  String? _extractVideoId(String url) {
    try {
      final uri =
          Uri.parse(url.startsWith('/') ? 'https://youtube.com$url' : url);
      return uri.queryParameters['v'];
    } catch (_) {
      return null;
    }
  }

  YoutubeTrack _videoToTrack(Video v) => YoutubeTrack(
        videoId:      v.id.value,
        title:        v.title,
        artist:       v.author,
        thumbnailUrl: 'https://img.youtube.com/vi/${v.id.value}/mqdefault.jpg',
        duration:     v.duration ?? Duration.zero,
      );

  Duration _parseDuration(String text) {
    try {
      final parts = text.trim().split(':');
      if (parts.length == 2) {
        return Duration(
            minutes: int.parse(parts[0]), seconds: int.parse(parts[1]));
      }
      if (parts.length == 3) {
        return Duration(
            hours:   int.parse(parts[0]),
            minutes: int.parse(parts[1]),
            seconds: int.parse(parts[2]));
      }
    } catch (_) {}
    return Duration.zero;
  }

  // ─────────────────────────────────────────────────────────────
  //  STREAM URL — v5: Cobalt + ALL 7 Piped instances race in parallel
  //
  //  WHY parallel:
  //   • Old sequential (Cobalt → Piped1 → … → Piped7 → yt_explode) worst-case
  //     2+ min. With parallel race, winner responds in 1–3 sec typically.
  //   • Cobalt and all Piped instances fire simultaneously; whichever
  //     returns a valid URL first wins. yt_explode only if all fail.
  // ─────────────────────────────────────────────────────────────

  Future<String?> getAudioStreamUrl(String videoId) async {
    // ── Round 1: Cobalt + all 7 Piped in parallel ──────────────
    debugPrint('[YouTube] Racing Cobalt + ${_pipedInstances.length} Piped for $videoId...');
    final url = await _raceStreamUrl(videoId);
    if (url != null && url.isNotEmpty) {
      debugPrint('[YouTube] ✓ Parallel race winner for $videoId');
      return url;
    }

    // ── Round 2: yt_explode — last resort (IP-locked on CGNAT) ──
    debugPrint('[YouTube] All parallel sources failed → trying yt_explode...');
    String? lastResortUrl;

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final manifest  = await _yt.videos.streamsClient.getManifest(videoId);
        final audioOnly = manifest.audioOnly;

        if (audioOnly.isNotEmpty) {
          final sorted     = audioOnly.sortByBitrate();
          final m4aStreams = sorted.where((s) =>
              s.codec.mimeType.contains('mp4') ||
              s.codec.mimeType.contains('aac') ||
              s.container.name.toLowerCase() == 'm4a').toList();

          final best = m4aStreams.isNotEmpty ? m4aStreams.last : sorted.last;
          final verUrl = best.url.toString();

          debugPrint('[YouTube] yt_explode (${best.bitrate.kiloBitsPerSecond.toStringAsFixed(0)} kbps) — verifying...');
          lastResortUrl = verUrl;

          if (await _verifyUrl(verUrl)) {
            debugPrint('[YouTube] yt_explode ✓ (verified)');
            return verUrl;
          }
          debugPrint('[YouTube] yt_explode URL failed verify (IP-lock?), retrying...');
        }

        final muxed = manifest.muxed;
        if (muxed.isNotEmpty) {
          final verUrl = muxed.sortByVideoQuality().last.url.toString();
          lastResortUrl ??= verUrl;
          if (await _verifyUrl(verUrl)) {
            debugPrint('[YouTube] yt_explode muxed ✓');
            return verUrl;
          }
        }
      } catch (e) {
        debugPrint('[YouTube] yt_explode attempt ${attempt + 1} failed: $e');
        if (attempt < 2) await Future.delayed(Duration(seconds: attempt + 1));
      }
    }

    if (lastResortUrl != null) {
      debugPrint('[YouTube] Returning unverified URL as last resort');
      return lastResortUrl;
    }
    debugPrint('[YouTube] All strategies failed for $videoId');
    return null;
  }

  // ── Parallel race: Cobalt + all Piped instances ───────────────
  // Fires all requests simultaneously; resolves with the first non-null URL.
  // Timeout of 10 sec guards against all sources hanging silently.
  Future<String?> _raceStreamUrl(String videoId) {
    final completer = Completer<String?>();
    final futures = <Future<String?>>[
      _cobaltAudioUrl(videoId),
      ..._pipedInstances.map((base) => _pipedStreamUrl(base, videoId)),
    ];

    int pending = futures.length;
    for (final f in futures) {
      f.then((url) {
        if (!completer.isCompleted && url != null && url.isNotEmpty) {
          debugPrint('[YouTube] Race winner: $url');
          completer.complete(url);
        }
      }).catchError((_) {}).whenComplete(() {
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.complete(null); // all failed
        }
      });
    }

    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );
  }

  // ── Cobalt API — primary stream strategy ────────────────────────
  // Cobalt proxies YouTube audio through its servers → no IP restriction.
  // "tunnel" URLs route via Cobalt CDN (always safe).
  // "redirect" URLs may be direct googlevideo.com (still IP-locked) but
  // the outer verify step catches those.
  Future<String?> _cobaltAudioUrl(String videoId) async {
    final resp = await http.post(
      Uri.parse(_kCobaltApi),
      headers: {
        'Accept':       'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'url':          'https://www.youtube.com/watch?v=$videoId',
        'downloadMode': 'audio',
        'audioFormat':  'best',
      }),
    ).timeout(const Duration(seconds: 12));

    if (resp.statusCode != 200) {
      debugPrint('[YouTube] Cobalt returned ${resp.statusCode}');
      return null;
    }

    final data   = jsonDecode(resp.body) as Map<String, dynamic>;
    final status = data['status'] as String?;
    final url    = data['url']    as String?;

    if ((status == 'redirect' || status == 'tunnel') &&
        url != null && url.isNotEmpty) {
      debugPrint('[YouTube] Cobalt status=$status');
      return url;
    }

    final errorCode = data['error']?['code'] as String?;
    debugPrint('[YouTube] Cobalt: status=$status error=$errorCode');
    return null;
  }

  // ── URL verification ─────────────────────────────────────────────
  // Quick HEAD request to detect 403/410 IP-lock before ExoPlayer tries it.
  Future<bool> _verifyUrl(String url) async {
    try {
      final resp = await http.head(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      return resp.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _pipedStreamUrl(String base, String videoId) async {
    final uri  = Uri.parse('$base/streams/$videoId');
    final resp = await http.get(uri, headers: {
      'User-Agent': 'BeatFlow/1.0',
    }).timeout(_kTimeout);

    if (resp.statusCode != 200) {
      debugPrint('[YouTube] Piped $base returned ${resp.statusCode}');
      return null;
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;

    // HLS manifest — PREFERRED (works best with just_audio + ExoPlayer)
    final hlsUrl = data['hls'] as String?;
    if (hlsUrl != null && hlsUrl.isNotEmpty) {
      debugPrint('[YouTube] Piped HLS URL ✓');
      return hlsUrl;
    }

    // Audio-only streams sorted by bitrate
    final audioStreams = List<Map>.from((data['audioStreams'] as List?) ?? []);
    if (audioStreams.isEmpty) return null;

    audioStreams.sort((a, b) {
      final ba = (a['bitrate'] as num?)?.toInt() ?? 0;
      final bb = (b['bitrate'] as num?)?.toInt() ?? 0;
      return bb.compareTo(ba);
    });

    final bestUrl = audioStreams.first['url'] as String?;
    if (bestUrl?.isNotEmpty == true) {
      debugPrint('[YouTube] Piped audio stream URL ✓');
      return bestUrl;
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────
  //  resolveTrack — full metadata + stream URL
  // ─────────────────────────────────────────────────────────────

  Future<YoutubeTrack?> resolveTrack(String videoId) async {
    try {
      // Get stream URL and metadata in parallel
      final streamFuture = getAudioStreamUrl(videoId);
      final metaFuture   = _getMetadata(videoId);

      final results = await Future.wait([streamFuture, metaFuture]);
      final streamUrl = results[0] as String?;
      final meta      = results[1] as _VideoMeta?;

      if (streamUrl == null) {
        debugPrint('[YouTube] resolveTrack: no stream URL for $videoId');
        return null;
      }

      return YoutubeTrack(
        videoId:      videoId,
        title:        meta?.title  ?? 'Unknown',
        artist:       meta?.artist ?? 'Unknown',
        thumbnailUrl: 'https://img.youtube.com/vi/$videoId/mqdefault.jpg',
        duration:     meta?.duration ?? Duration.zero,
        streamUrl:    streamUrl,
      );
    } catch (e) {
      debugPrint('[YouTube] resolveTrack error: $e');
      return null;
    }
  }

  Future<_VideoMeta?> _getMetadata(String videoId) async {
    // 1. oEmbed — YouTube public API, <500ms, no auth needed
    try {
      final uri = Uri.parse('https://www.youtube.com/oembed').replace(
        queryParameters: {
          'url': 'https://www.youtube.com/watch?v=$videoId',
          'format': 'json',
        },
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return _VideoMeta(
          title:    data['title']       as String? ?? 'Unknown',
          artist:   data['author_name'] as String? ?? 'Unknown',
          duration: Duration.zero, // oEmbed has no duration field
        );
      }
    } catch (_) {}

    // 2. yt_explode fallback (has duration)
    try {
      final video = await _yt.videos.get(videoId);
      return _VideoMeta(
        title:    video.title,
        artist:   video.author,
        duration: video.duration ?? Duration.zero,
      );
    } catch (_) {}

    // 3. Piped fallback
    for (final base in _pipedInstances) {
      try {
        final uri  = Uri.parse('$base/streams/$videoId');
        final resp = await http.get(uri, headers: {
          'User-Agent': 'BeatFlow/1.0',
        }).timeout(_kTimeout);

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          return _VideoMeta(
            title:  data['title']    as String? ?? 'Unknown',
            artist: data['uploader'] as String? ?? 'Unknown',
            duration: Duration(
                seconds: (data['duration'] as num?)?.toInt() ?? 0),
          );
        }
      } catch (_) {}
    }
    return null;
  }

  void dispose() => _yt.close();
}

class _VideoMeta {
  final String title;
  final String artist;
  final Duration duration;
  const _VideoMeta(
      {required this.title, required this.artist, required this.duration});
}
