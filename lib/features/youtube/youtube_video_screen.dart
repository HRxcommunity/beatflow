import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../core/theme/app_theme.dart';

// ╔══════════════════════════════════════════════════════════════╗
// ║  YOUTUBE VIDEO SCREEN                                        ║
// ║  Embeds the YouTube IFrame Player via a self-contained HTML  ║
// ║  wrapper page. Fixes all Android WebView black-screen,       ║
// ║  infinite-loading, and autoplay issues.                      ║
// ╚══════════════════════════════════════════════════════════════╝

// ── WHY HTML WRAPPER (not direct embed URL) ──────────────────────────────
// 1. IFrame API onReady → YTFlutter.postMessage('ready') lets Flutter know
//    the player is truly ready before hiding the loading overlay.
//    Direct embed URL + onPageFinished fires too early (HTML loaded ≠ player
//    ready) → black screen behind prematurely-hidden spinner.
// 2. player.playVideo() called explicitly in onReady → guaranteed autoplay
//    even when Android WebView's media policy blocks <autoplay> HTML attribute.
// 3. loadHtmlString(baseUrl:'https://www.youtube.com') sets the document
//    origin to youtube.com — no Referer header spoofing needed.
// 4. JS channel (YTFlutter) bridges player events (ready / state / error)
//    to Flutter for accurate loading and error detection.
// ─────────────────────────────────────────────────────────────────────────

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
  WebViewController? _webController;
  bool _loading = true;
  bool _hasError = false;
  Timer? _loadTimeout;

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

  Future<void> _initWebView() async {
    // ── Create controller ────────────────────────────────────────
    final ctrl = WebViewController();

    // ── CRITICAL FIX: Disable user-gesture requirement for media ─
    //
    // ROOT CAUSE OF BLACK SCREEN:
    // Android WebView (Chromium) blocks ALL media autoplay that does not
    // originate from a user touch/click gesture by default. This applies
    // even when the embed URL contains autoplay=1, or when the YT player
    // calls video.play() programmatically.
    //
    // Without this call, the YouTube IFrame player initialises, the page
    // loads, the controls become visible, but the <video> element refuses
    // to play → the video frame stays black until the user manually taps
    // the play button INSIDE the iframe.
    //
    // setMediaPlaybackRequiresUserGesture(false) disables that policy for
    // this specific WebView instance, letting YouTube's player.playVideo()
    // and the autoplay flag work as intended.
    if (ctrl.platform is AndroidWebViewController) {
      await (ctrl.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
      debugPrint('[YTVideo] ✓ setMediaPlaybackRequiresUserGesture(false)');
    }

    if (!mounted) return;

    ctrl
      // Unrestricted JS — required for IFrame Player API to work at all
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // BLACK FIX: prevent white flash before YouTube dark UI renders
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(_kBrowserUA)
      // JS channel — receives player events (ready / state / error) from
      // the HTML wrapper so we know exactly when to hide the loading overlay
      ..addJavaScriptChannel('YTFlutter', onMessageReceived: _onYTMessage)
      ..setNavigationDelegate(NavigationDelegate(
        // Do NOT hide loading overlay here. onPageFinished fires when the
        // HTML page's DOM is ready — at this point YouTube's JS is still
        // downloading and initialising. Hiding the overlay now would show
        // a blank black frame while the player loads.
        onPageFinished: (url) {
          debugPrint('[YTVideo] Page HTML loaded (player JS still loading): $url');
        },
        onWebResourceError: (err) {
          debugPrint('[YTVideo] Resource error: ${err.description} '
              '(code=${err.errorCode}, mainFrame=${err.isForMainFrame})');
          // Only treat main-frame navigation errors as fatal
          if (err.isForMainFrame == true && mounted) {
            _loadTimeout?.cancel();
            setState(() { _loading = false; _hasError = true; });
          }
        },
        // FIX: expanded allow-list covers all domains the YouTube player needs
        onNavigationRequest: (req) {
          final url = req.url;
          if (url.contains('youtube.com')         ||
              url.contains('youtube-nocookie.com') ||
              url.contains('youtu.be')             ||
              url.contains('googlevideo.com')      ||  // video/audio streams
              url.contains('ytimg.com')            ||  // thumbnails, sprites
              url.contains('ggpht.com')            ||  // channel avatars
              url.contains('gstatic.com')          ||  // player assets
              url.contains('googleapis.com')) {
            return NavigationDecision.navigate;
          }
          // Block everything else (e.g. external "Watch on YouTube" links)
          debugPrint('[YTVideo] Blocked navigation: $url');
          return NavigationDecision.prevent;
        },
      ))
      // Load our self-contained HTML page.
      // baseUrl = 'https://www.youtube.com' sets the document.origin to
      // youtube.com so the IFrame Player API communicates correctly without
      // any Referer header tricks.
      ..loadHtmlString(
        _buildPlayerHtml(widget.videoId),
        baseUrl: 'https://www.youtube.com',
      );

    // Fallback timeout: if the IFrame API never fires onReady (e.g. the
    // video has embedding disabled), hide the spinner after 8 seconds so
    // the user sees the YouTube player's own error message instead of our
    // loading overlay forever.
    _loadTimeout = Timer(const Duration(seconds: 8), () {
      if (mounted && _loading) {
        debugPrint('[YTVideo] Load timeout — showing player (may show YT error)');
        setState(() => _loading = false);
      }
    });

    if (mounted) setState(() => _webController = ctrl);
  }

  // Receives events from the HTML wrapper via YTFlutter.postMessage()
  void _onYTMessage(JavaScriptMessage msg) {
    final data = msg.message;
    debugPrint('[YTVideo] JS→Flutter: $data');

    if (data == 'ready' || data.startsWith('state:')) {
      // Player is initialised and (if state=1) playing — safe to reveal
      if (mounted && _loading) {
        _loadTimeout?.cancel();
        setState(() { _loading = false; _hasError = false; });
      }
    } else if (data.startsWith('error:')) {
      // YouTube player error codes:
      //   2  = invalid parameter
      //   5  = HTML5 player error
      //   100 = video not found / private
      //   101 / 150 = embedding disabled by owner
      final code = data.substring(6);
      debugPrint('[YTVideo] YouTube player error code: $code');
      // Hide loader and let YouTube show its own error UI (embedding
      // disabled shows a message inside the iframe, not a blank screen)
      if (mounted && _loading) {
        _loadTimeout?.cancel();
        setState(() => _loading = false);
      }
    }
  }

  /// Builds a self-contained HTML page that hosts the YouTube IFrame
  /// Player API for the given [videoId].
  ///
  /// Key implementation notes:
  /// • Uses YT.Player (IFrame API) not a raw <iframe src> embed, so we
  ///   get the onReady callback and can call playVideo() programmatically.
  /// • <meta name="referrer" content="origin"> makes all requests from
  ///   this page include Referer: https://www.youtube.com (same as the
  ///   baseUrl origin), satisfying YouTube's referer check without any
  ///   Flutter-side header spoofing.
  /// • playerVars.origin: 'https://www.youtube.com' tells YouTube's embed
  ///   which origin to expect for postMessage — matches our loadHtmlString
  ///   baseUrl so cross-origin postMessage handshake succeeds.
  String _buildPlayerHtml(String videoId) {
    // Sanitise videoId so it can be safely embedded in the script block.
    // YouTube video IDs are 11 chars of [A-Za-z0-9_-] — reject anything else.
    final id = videoId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '');
    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1.0,maximum-scale=1.0,user-scalable=no">
  <meta name="referrer" content="origin">
  <title>YouTube Player</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      width: 100%;
      height: 100%;
      background: #000;
      overflow: hidden;
    }
    #player {
      width: 100%;
      height: 100%;
    }
    iframe {
      display: block;
      width: 100% !important;
      height: 100% !important;
      border: none;
    }
  </style>
</head>
<body>
<div id="player"></div>
<script>
  // Load the YouTube IFrame Player API asynchronously
  (function() {
    var tag = document.createElement('script');
    tag.src = 'https://www.youtube.com/iframe_api';
    var firstTag = document.getElementsByTagName('script')[0];
    firstTag.parentNode.insertBefore(tag, firstTag);
  })();

  var ytPlayer;

  // Called automatically by the IFrame API script once it is loaded
  function onYouTubeIframeAPIReady() {
    ytPlayer = new YT.Player('player', {
      videoId: '$id',
      playerVars: {
        autoplay:       1,   // request autoplay (must also set mediaPlayback)
        controls:       1,   // show native YouTube controls
        playsinline:    1,   // play inline instead of full-screen on iOS/Android
        rel:            0,   // don't show related videos at end
        modestbranding: 1,   // minimise YouTube branding
        enablejsapi:    1,   // required for JS API calls (playVideo etc.)
        origin:         'https://www.youtube.com'
      },
      events: {
        onReady: function(event) {
          // Player is fully initialised — explicitly call playVideo()
          // because autoplay=1 may still be blocked at the embed level on
          // some browsers; calling this from onReady always works when
          // setMediaPlaybackRequiresUserGesture(false) is set in Flutter.
          event.target.playVideo();
          if (typeof YTFlutter !== 'undefined') {
            YTFlutter.postMessage('ready');
          }
        },
        onStateChange: function(event) {
          // YT.PlayerState: UNSTARTED=-1 ENDED=0 PLAYING=1 PAUSED=2 BUFFERING=3 CUED=5
          if (typeof YTFlutter !== 'undefined') {
            YTFlutter.postMessage('state:' + event.data);
          }
        },
        onError: function(event) {
          if (typeof YTFlutter !== 'undefined') {
            YTFlutter.postMessage('error:' + event.data);
          }
        }
      }
    });
  }
</script>
</body>
</html>''';
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _retry() {
    if (!mounted) return;
    setState(() { _loading = true; _hasError = false; _webController = null; });
    _initWebView();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _webController;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // ── App bar ─────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
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
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.4), width: 1),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle_fill_rounded, color: Colors.red, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'YouTube',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── WebView area ─────────────────────────────────────────
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The WebView — always in tree once ctrl is ready so it
                // keeps rendering even while loading overlay is visible
                if (ctrl != null)
                  WebViewWidget(controller: ctrl)
                else
                  const SizedBox.shrink(),

                // Loading overlay — hidden ONLY after IFrame API fires
                // onReady (not after onPageFinished, which is too early)
                if (_loading)
                  Container(
                    color: Colors.black,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: AppTheme.accentViolet),
                          SizedBox(height: 16),
                          Text(
                            'Loading video…',
                            style: TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Error state: shown only on main-frame WebView error
                if (_hasError && !_loading)
                  Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: Colors.red, size: 48),
                          const SizedBox(height: 12),
                          const Text(
                            'Failed to load video',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: _retry,
                            icon: const Icon(Icons.refresh_rounded,
                                color: Colors.red, size: 18),
                            label: const Text(
                              'Retry',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
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
