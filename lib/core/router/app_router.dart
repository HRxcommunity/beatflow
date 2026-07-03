import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/splash/splash_screen.dart';
import '../../presentation/home/home_screen.dart';
import '../../presentation/player/now_playing_screen.dart';
import '../../presentation/player/video_player_screen.dart';
import '../../presentation/playlists/playlist_detail_screen.dart';
import '../../presentation/albums/album_detail_screen.dart';
import '../../presentation/artists/artist_detail_screen.dart';
import '../../presentation/search/search_screen.dart';
import '../../presentation/settings/settings_screen.dart';
import '../../presentation/settings/equalizer_screen.dart';
import '../../features/together/presentation/together_screen.dart';
import '../../features/ai_vocab/ai_vocab_chat_screen.dart';
import '../../features/ai_vocab/vocab_notif_settings_screen.dart';
import '../../features/browser/hrx_browse_screen.dart';
import '../../features/youtube/youtube_video_screen.dart';
import '../../features/study_ai/study_ai_screen.dart';
import '../../features/social/presentation/social_screen.dart';

import '../../domain/entities/song_entity.dart';

class AppRouter {
  static const splash     = '/';
  static const home       = '/home';
  static const nowPlaying = '/now-playing';
  static const videoPlayer = '/video-player';
  static const playlist   = '/playlist';
  static const album      = '/album';
  static const artist     = '/artist';
  static const search     = '/search';
  static const settings   = '/settings';
  static const equalizer  = '/equalizer';
  static const together   = '/together';
  static const aiVocab    = '/ai-vocab';
  static const vocabNotifSetup = '/ai-vocab/notif-setup';
  static const studyAi    = '/study-ai';
  static const browser    = '/browser';
  static const youtubeVideo = '/youtube-video';
  static const social       = '/social';

  static final router = GoRouter(
    initialLocation: splash,
    routes: [
      GoRoute(
        path: splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: nowPlaying,
        builder: (context, state) => const NowPlayingScreen(),
      ),
      GoRoute(
        path: videoPlayer,
        builder: (context, state) {
          final song = state.extra as SongEntity;
          return VideoPlayerScreen(song: song);
        },
      ),
      GoRoute(
        path: youtubeVideo,
        builder: (context, state) {
          final extra = state.extra as Map<String, String>;
          return YoutubeVideoScreen(
            videoId: extra['videoId']!,
            title:   extra['title']!,
            artist:  extra['artist']!,
          );
        },
      ),
      GoRoute(
        path: '$playlist/:id',
        builder: (context, state) => PlaylistDetailScreen(
          playlistId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '$album/:name',
        builder: (context, state) {
          final songs = state.extra as List<SongEntity>? ?? [];
          return AlbumDetailScreen(
            albumName: state.pathParameters['name']!,
            songs: songs,
          );
        },
      ),
      GoRoute(
        path: '$artist/:name',
        builder: (context, state) {
          return ArtistDetailScreen(
            artistName: state.pathParameters['name']!,
          );
        },
      ),
      GoRoute(
        path: search,
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: equalizer,
        builder: (context, state) => const EqualizerScreen(),
      ),
      GoRoute(
        path: together,
        builder: (context, state) => const TogetherScreen(),
      ),
      GoRoute(
        path: aiVocab,
        builder: (context, state) => const AIVocabChatScreen(),
      ),
      GoRoute(
        path: vocabNotifSetup,
        builder: (context, state) => const VocabNotifSettingsScreen(),
      ),
      GoRoute(
        path: studyAi,
        builder: (context, state) => const StudyAiScreen(),
      ),
      GoRoute(
        path: social,
        builder: (context, state) => const SocialScreen(),
      ),
      GoRoute(
        path: browser,
        builder: (context, state) {
          final extra = state.extra;
          var startPrivate = false;
          String? initialUrl;
          if (extra is Map) {
            startPrivate = extra['private'] == true;
            initialUrl = extra['url'] as String?;
          }
          return HRxBrowseScreen(
            startPrivate: startPrivate,
            initialUrl: initialUrl,
          );
        },
      ),

    ],
  );
}
