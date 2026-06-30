// ╔══════════════════════════════════════════════════════════════╗
// ║  Groq API Service — SSC CGL Vocab AI                        ║
// ╚══════════════════════════════════════════════════════════════╝

import 'dart:convert';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────
// 🔑  APNI GROQ API KEY YAHAN DAALO
//     Free key milti hai: https://console.groq.com
// ─────────────────────────────────────────────────────────────
const String _kGroqApiKey = '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';

const String _kGroqEndpoint = 'https://api.groq.com/openai/v1/chat/completions';
const String _kModel        = 'llama-3.3-70b-versatile';
const int    _kMaxTokens    = 1024;

/// Single chat message — role: 'user' | 'assistant' | 'system'
class ChatMessage {
  final String role;
  final String content;
  const ChatMessage({required this.role, required this.content});

  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// System prompt — AI ek friendly Hinglish vocab teacher hai
const String _kSystemPrompt = '''
Tu BeatFlow ka AI Vocab Buddy hai — SSC CGL ki taiyaari karne wale students ke liye bana hai.

TERA KAAM:
1. User se Hinglish mein baat kar (Hindi + English mix, casual tone)
2. SSC CGL level ke English vocabulary words sikhao
3. Har word ke liye:
   - Pronunciation guide (simple phonetic)
   - Hindi meaning ek clear line mein
   - English definition (simple words mein)
   - 2 example sentences (ek English, ek Hinglish)
   - Word family (noun/verb/adj/adverb forms agar hain)
   - Memory trick ya mnemonic (Hindi mein bhi chal sakta)
   - SSC mein commonly asked hai ya nahi — batao

4. Agar user koi word pooche: seedha explain karo
5. Agar user "quiz" bole: 5 MCQ type questions daal SSC pattern mein
6. Agar user "word of the day" bole: ek important SSC CGL word chunno
7. Agar user "list" bole: topic-wise vocab list daal (synonyms, antonyms, one-word substitution)
8. Conversation natural rakho — boring lecture mat karo

STYLE:
- Fun aur engaging raho
- Emojis use karo thoda
- "Dekho bhai", "yaar", "acha" — natural Hinglish phrases
- Words ko context se connect karo (current affairs, songs, daily life)
- Kabhi kabhi confidence boost karo student ko

SSC CGL FOCUS AREAS:
- One-word substitutions
- Synonyms/Antonyms
- Idioms and phrases
- Spellings
- Fill in the blanks type usage

Always ready raho — koi bhi word pooche ya baat karo vocab ke baare mein!
''';

class GroqService {
  GroqService._();
  static final instance = GroqService._();

  /// Groq API call — full conversation history bhejo context ke liye
  Future<String> sendMessage(List<ChatMessage> history) async {
    if (_kGroqApiKey == 'YOUR_GROQ_API_KEY_HERE') {
      return '⚠️ Groq API key set nahi ki!\n\n'
          'groq_service.dart mein apni key daalo.\n'
          'Free key: https://console.groq.com';
    }

    final messages = [
      ChatMessage(role: 'system', content: _kSystemPrompt),
      ...history,
    ];

    try {
      final response = await http.post(
        Uri.parse(_kGroqEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_kGroqApiKey',
        },
        body: jsonEncode({
          'model': _kModel,
          'messages': messages.map((m) => m.toJson()).toList(),
          'max_tokens': _kMaxTokens,
          'temperature': 0.7,
          'stream': false,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final content = data['choices'][0]['message']['content'] as String;
        return content.trim();
      } else if (response.statusCode == 401) {
        return '❌ Invalid API key! console.groq.com par check karo.';
      } else if (response.statusCode == 429) {
        return '⏳ Rate limit ho gaya. Thodi der baad try karo!';
      } else {
        final err = jsonDecode(response.body);
        return '❌ Error ${response.statusCode}: ${err['error']?['message'] ?? 'Unknown error'}';
      }
    } on Exception catch (e) {
      return '❌ Network error: $e\nInternet connection check karo.';
    }
  }
}
