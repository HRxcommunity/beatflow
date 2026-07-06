// ╔══════════════════════════════════════════════════════════════╗
// ║  GroqConfig — Centralized API Key Manager                    ║
// ║  Priority: Settings key > Hardcoded fallback key             ║
// ╚══════════════════════════════════════════════════════════════╝

import '../../services/settings_service.dart';

// ─────────────────────────────────────────────────────────────
// 🔑  HARDCODED FALLBACK KEY — Yahan apni default key daalo
//     Agar user ne Settings mein key nahi daali to yeh use hogi
// ─────────────────────────────────────────────────────────────
const String _kFallbackGroqKey =
    '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';

const String kGroqEndpoint = 'https://api.groq.com/openai/v1/chat/completions';

class GroqConfig {
  GroqConfig._();
  static final instance = GroqConfig._();

  SettingsService? _settingsService;

  /// Call this once from ServiceLocator after SettingsService.init()
  void init(SettingsService service) => _settingsService = service;

  /// Returns settings key if user entered one, else hardcoded fallback.
  /// Sab Groq calls yahi use karein — direct _kGroqApiKey mat use karo.
  String get effectiveKey {
    final userKey = _settingsService?.settings.groqApiKey.trim() ?? '';
    return userKey.isNotEmpty ? userKey : _kFallbackGroqKey;
  }

  /// True if user has set their own key in settings
  bool get hasCustomKey {
    final userKey = _settingsService?.settings.groqApiKey.trim() ?? '';
    return userKey.isNotEmpty;
  }
}
