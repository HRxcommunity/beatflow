// lib/services/update_service.dart
//
// BeatFlow OTA Update System
// ──────────────────────────
// GitHub Releases pe latest release check karta hai.
// Agar nayi version mili → UpdateInfo return karta hai jisme
// APK direct download URL bhi hota hai.
//
// SETUP:
//   1. AppConstants.githubOwner  → apna GitHub username
//   2. AppConstants.githubRepo   → apna repo name (default: 'beatflow')
//   3. Push karo: git tag v1.1.0 && git push --tags
//   4. GitHub Actions automatically APK build karke release pe attach kar dega.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../core/constants/app_constants.dart';

// ─────────────────────────────────────────────────────────────────────────────

/// Update ki saari info — available hai ya nahi, changelog, download URL.
class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String downloadUrl;   // Direct APK URL ya release page URL
  final String changelog;     // Release notes (Markdown supported)
  final bool isRequired;      // [REQUIRED] tag release notes mein → force update

  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.downloadUrl,
    required this.changelog,
    this.isRequired = false,
  });

  /// True if latestVersion > currentVersion
  bool get hasUpdate => _isNewer(latestVersion, currentVersion);

  // Semantic version compare: "1.2.0" vs "1.1.9"
  static bool _isNewer(String latest, String current) {
    final l = _parts(latest);
    final c = _parts(current);
    for (int i = 0; i < 3; i++) {
      final li = i < l.length ? l[i] : 0;
      final ci = i < c.length ? c[i] : 0;
      if (li > ci) return true;
      if (li < ci) return false;
    }
    return false;
  }

  static List<int> _parts(String v) =>
      v.replaceAll(RegExp(r'[^0-9.]'), '').split('.').map((s) => int.tryParse(s) ?? 0).toList();
}

// ─────────────────────────────────────────────────────────────────────────────

/// Singleton service — GitHub Releases API se update check karta hai.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static String get _apiUrl =>
      'https://api.github.com/repos/'
      '${AppConstants.githubOwner}/${AppConstants.githubRepo}'
      '/releases/latest';

  bool _checking = false; // double-fire prevent karta hai

  /// Checks GitHub for a newer release.
  /// Returns [UpdateInfo] if update available, null otherwise.
  Future<UpdateInfo?> checkForUpdate() async {
    if (_checking) return null;
    _checking = true;

    try {
      // Pehle app ki current version padho
      final pkg = await PackageInfo.fromPlatform();
      final current = pkg.version; // pubspec.yaml se (e.g. "1.0.0")

      // GitHub Releases API call
      final res = await http
          .get(
            Uri.parse(_apiUrl),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        debugPrint('[OTA] GitHub API → HTTP ${res.statusCode}');
        return null;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;

      // Drafts aur pre-releases skip karo
      final isDraft      = data['draft']      as bool? ?? false;
      final isPrerelease = data['prerelease'] as bool? ?? false;
      if (isDraft || isPrerelease) {
        debugPrint('[OTA] Latest release is draft/prerelease — skipping');
        return null;
      }

      final tag      = (data['tag_name'] as String? ?? '').trim();
      final body     = (data['body']     as String? ?? '').trim();
      final htmlUrl  =  data['html_url'] as String? ?? '';

      // APK asset dhundo — nahi mila to release page kholo
      final assets = data['assets'] as List<dynamic>? ?? [];
      String apkUrl = htmlUrl;
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String? ?? htmlUrl;
          break;
        }
      }

      // [REQUIRED] release notes mein → baad mein dismiss nahi kar sakta
      final required  = body.contains('[REQUIRED]');
      final changelog = body
          .replaceAll('[REQUIRED]', '')
          .trim()
          .replaceAll(RegExp(r'\n{3,}'), '\n\n'); // extra blank lines hata

      final info = UpdateInfo(
        latestVersion:  tag.replaceAll(RegExp(r'^v'), ''),
        currentVersion: current,
        downloadUrl:    apkUrl,
        changelog:      changelog.isEmpty ? 'Bug fixes & improvements.' : changelog,
        isRequired:     required,
      );

      debugPrint('[OTA] current=$current latest=${info.latestVersion} '
          'hasUpdate=${info.hasUpdate} required=$required');

      return info.hasUpdate ? info : null;
    } catch (e, st) {
      debugPrint('[OTA] checkForUpdate error: $e\n$st');
      return null;
    } finally {
      _checking = false;
    }
  }
}
