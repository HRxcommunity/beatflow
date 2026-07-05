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

  // BUG-Y02 FIX: was 14s — Piped futures outlived the 12s race window by 2s,
  // leaving orphaned HTTP requests holding completer refs. 10s < 12s race timeout.
  static const _kTimeout   = Duration(seconds: 10);
  static const _cobaltInstances = [
    'https://cobalt-api.kwiatekmiki.com',      // no auth required
    'https://cobalt.api.timelessnesses.me',    // no auth required
    'https://cobalt-us.kwiatekmiki.com',       // no auth required
  ];
  // ignore: unused_field
  static const _kCobaltApi = 'https://api.cobalt.tools/'; // kept for compat

  // Piped instances — expanded list, tried in order
  // Piped instances — refreshed 2026-07.
  // Check https://piped-instances.kavin.rocks for live status.
  static const _pipedInstances = [
    'https://pipedapi.adminforge.de',       // DE — usually reliable
    'https://watchapi.whatever.social',     // US
    'https://api.piped.yt',                 // US
    'https://piped-api.privacy.com.de',     // DE
    'https://api.piped.projectsegfau.lt',   // EU
    'https://pipedapi.tokhmi.xyz',          // US
    'https://piped.bus-hit.me',             // CA — note: some instances use this path
    'https://piped-api.codepoint.media',    // AU
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
    debugPrint('[YouTube] Racing ${_cobaltInstances.length} Cobalt + InnerTube iOS + ${_pipedInstances.length} Piped for $videoId...');
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

  // ── Parallel race: Cobalt + InnerTube iOS + all Piped instances ──
  // FIX v6: Added InnerTube iOS client as an extra parallel source.
  // Fires all requests simultaneously; resolves with the first non-null URL.
  // Timeout of 12 sec (up from 10) to give InnerTube iOS enough time.
  Future<String?> _raceStreamUrl(String videoId) {
    final completer = Completer<String?>();
    final futures = <Future<String?>>[
      _cobaltAudioUrl(videoId),
      _innerTubeIosStreamUrl(videoId), // FIX v6: new parallel source
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
      const Duration(seconds: 12), // FIX v6: extended for more sources
      onTimeout: () => null,
    );
  }

  // ── InnerTube iOS client — extra stream fallback ──────────────
  // The iOS client doesn't require a PO token (unlike ANDROID post-2024).
  // URLs are still googlevideo.com signed CDN links → may 403 on CGNAT if the
  // outgoing IP flips between this request and ExoPlayer's media request.
  // Included here because it's free and fast; Cobalt/Piped HLS are still
  // preferred for CGNAT-safe proxied delivery.
  Future<String?> _innerTubeIosStreamUrl(String videoId) async {
    try {
      const clientVersion = '19.29.1';
      const deviceModel   = 'iPhone16,2';

      final resp = await http.post(
        Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'),
        headers: {
          'Content-Type':              'application/json',
          'User-Agent':
              'com.google.ios.youtube/$clientVersion ($deviceModel; U; CPU iOS 17_5_1 like Mac OS X)',
          'X-YouTube-Client-Name':    '5',
          'X-YouTube-Client-Version': clientVersion,
          'Origin':                   'https://www.youtube.com',
        },
        body: jsonEncode({
          'videoId': videoId,
          'context': {
            'client': {
              'clientName':    'IOS',
              'clientVersion': clientVersion,
              'deviceModel':   deviceModel,
              'hl':            'en',
              'gl':            'US',
            },
          },
        }),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        debugPrint('[YouTube] InnerTube iOS returned ${resp.statusCode}');
        return null;
      }

      final data          = jsonDecode(resp.body) as Map<String, dynamic>;
      final streamingData = data['streamingData'] as Map<String, dynamic>?;
      if (streamingData == null) {
        debugPrint('[YouTube] InnerTube iOS: no streamingData');
        return null;
      }

      // Prefer audio-only adaptive formats (highest bitrate first)
      final adaptive     = List<Map>.from((streamingData['adaptiveFormats'] as List?) ?? []);
      final audioStreams  = adaptive
          .where((f) => (f['mimeType'] as String? ?? '').startsWith('audio/'))
          .toList();

      if (audioStreams.isNotEmpty) {
        audioStreams.sort((a, b) {
          final ba = (a['bitrate'] as num?)?.toInt() ?? 0;
          final bb = (b['bitrate'] as num?)?.toInt() ?? 0;
          return bb.compareTo(ba);
        });
        final url = audioStreams.first['url'] as String?;
        if (url != null && url.isNotEmpty) {
          debugPrint('[YouTube] InnerTube iOS audio ✓');
          return url;
        }
      }

      // Fallback: muxed format
      final formats = List<Map>.from((streamingData['formats'] as List?) ?? []);
      if (formats.isNotEmpty) {
        final url = formats.last['url'] as String?;
        if (url != null && url.isNotEmpty) {
          debugPrint('[YouTube] InnerTube iOS muxed ✓');
          return url;
        }
      }

      debugPrint('[YouTube] InnerTube iOS: no usable URL');
      return null;
    } catch (e) {
      debugPrint('[YouTube] InnerTube iOS error: $e');
      return null;
    }
  }

  // ── Cobalt API — primary stream strategy ────────────────────────
  // Tries all _cobaltInstances sequentially until one succeeds.
  //
  // FIX v6:
  //  - 'audioFormat: best' → 'audioFormat: mp3'  (some instances reject "best")
  //  - Added 'stream' to accepted statuses (new in Cobalt 10.x)
  //  - Tries multiple community instances when official API returns 400/401
  //  - If you have a Cobalt API key, add header: 'Authorization': 'Api-Key YOUR_KEY'
  Future<String?> _cobaltAudioUrl(String videoId) async {
    for (final instance in _cobaltInstances) {
      try {
        final resp = await http.post(
          Uri.parse('$instance/'),
          headers: {
            'Accept':       'application/json',
            'Content-Type': 'application/json',
            // 'Authorization': 'Api-Key YOUR_KEY',  // uncomment if you have a key
          },
          body: jsonEncode({
            'url':          'https://www.youtube.com/watch?v=$videoId',
            'downloadMode': 'audio',
            'audioFormat':  'mp3',   // FIX: 'best' rejected by some instances
          }),
        ).timeout(const Duration(seconds: 10));

        if (resp.statusCode != 200) {
          debugPrint('[YouTube] Cobalt $instance returned ${resp.statusCode}');
          continue; // try next instance
        }

        final data   = jsonDecode(resp.body) as Map<String, dynamic>;
        final status = data['status'] as String?;
        final url    = data['url']    as String?;

        // FIX: added 'stream' — used by Cobalt 10.x for non-redirected proxied URLs
        if ((status == 'redirect' || status == 'tunnel' || status == 'stream') &&
            url != null && url.isNotEmpty) {
          debugPrint('[YouTube] Cobalt $instance ✓ status=$status');
          return url;
        }

        // BUG-Y04 FIX: Cobalt returns 'picker' for live streams / age-restricted
        // content when multiple format choices exist. Previously fell through to
        // null, forcing the race to slower sources. Now extracts first audio URL.
        if (status == 'picker') {
          final items = (data['items'] as List?) ?? [];
          if (items.isNotEmpty) {
            final pickerUrl = items.first['url'] as String?;
            if (pickerUrl != null && pickerUrl.isNotEmpty) {
              debugPrint('[YouTube] Cobalt $instance ✓ status=picker (first item)');
              return pickerUrl;
            }
          }
        }

        final errorCode = data['error']?['code'] as String?;
        debugPrint('[YouTube] Cobalt $instance: status=$status error=$errorCode');
      } catch (e) {
        debugPrint('[YouTube] Cobalt $instance error: $e');
      }
    }
    return null;
  }

  // ── URL verification ─────────────────────────────────────────────
  // Quick HEAD request to detect 403/410 IP-lock before ExoPlayer tries it.
  Future<bool> _verifyUrl(String url) async {
    // ROOT CAUSE FIX: Google Video CDN (googlevideo.com) returns HTTP 405
    // "Method Not Allowed" for HEAD requests — it only accepts GET with
    // Range headers. Without this fix, valid stream URLs were incorrectly
    // marked as broken and discarded, forcing fallback to slower sources.
    //
    // Treatment:
    //   < 400  → URL is reachable and returns content           → valid
    //   405    → Server exists, URL is valid, HEAD not supported → valid
    //   4xx/5xx (except 405) → actual error                     → invalid
    try {
      final resp = await http.head(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 405) return true; // CDN valid, HEAD unsupported
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
