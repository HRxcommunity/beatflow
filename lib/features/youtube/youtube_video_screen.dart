import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/theme/app_theme.dart';

// ╔══════════════════════════════════════════════════════════════╗
// ║  YOUTUBE VIDEO SCREEN                                        ║
// ║  Embeds YouTube player using webview_flutter.                ║
// ║  Fix: youtube-nocookie.com + browser User-Agent bypasses     ║
// ║       Error 153 "Video player configuration error".          ║
// ╚══════════════════════════════════════════════════════════════╝

// Chrome 120 mobile UA — makes WebView look like a real browser to YouTube
const _kBrowserUA =
    'Mozilla/5.0 (Linux; Android 10; Mobile) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/120.0.0.0 Mobile Safari/537.36';

class YoutubeVideoScreen extends StatefulWidget {
  final String videoId;
  final String title;
  final String artist;

  const YoutubeVideoScreen({
    super.key,
    required this.videoId,
    required this.title,
    required this.artist,
  });

  @override
  State<YoutubeVideoScreen> createState() => _YoutubeVideoScreenState();
}

class _YoutubeVideoScreenState extends State<YoutubeVideoScreen> {
  late final WebViewController _webController;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initWebView();
  }

  void _initWebView() {
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // ── KEY FIX: spoof a real Chrome browser ───────────────────
      ..setUserAgent(_kBrowserUA)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (err) {
          debugPrint('[YTVideo] WebView error: ${err.description}');
        },
        // Allow YouTube navigation (e.g. "Watch on YouTube" link)
        onNavigationRequest: (req) {
          if (req.url.contains('youtube.com') ||
              req.url.contains('youtu.be') ||
              req.url.contains('youtube-nocookie.com')) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(
        Uri.parse(_buildEmbedUrl()),
        headers: {
          // Spoof referer so YouTube thinks we're coming from their own site
          'Referer': 'https://www.youtube.com/',
        },
      );
  }

  /// youtube-nocookie.com avoids tracking cookies AND is less strict
  /// about blocking embedded playback. Combined with Chrome UA it
  /// resolves Error 153 "Video player configuration error".
  String _buildEmbedUrl() {
    final id = Uri.encodeComponent(widget.videoId);
    return 'https://www.youtube-nocookie.com/embed/$id'
        '?autoplay=1'
        '&controls=1'
        '&modestbranding=1'
        '&rel=0'
        '&playsinline=1'
        '&enablejsapi=1';
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // ── Top bar ─────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          widget.artist,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: Colors.red.withOpacity(0.4), width: 1),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle_fill_rounded,
                            color: Colors.red, size: 12),
                        SizedBox(width: 4),
                        Text('YouTube',
                            style: TextStyle(
                                color: Colors.red,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── WebView ─────────────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _webController),
                if (_loading)
                  Container(
                    color: Colors.black,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                              color: AppTheme.accentViolet),
                          SizedBox(height: 16),
                          Text('Loading video...',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
