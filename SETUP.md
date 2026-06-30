# BeatFlow — Premium Offline Music Player
## Complete Setup Guide

---

## 📁 Project Structure

```
lib/
├── main.dart                          # App entry point, Hive init, BLoC providers
├── service_locator.dart               # Singleton DI container
│
├── core/
│   ├── constants/app_constants.dart   # App-wide constants, EQ presets, colors
│   ├── theme/app_theme.dart           # Material 3 dark/light theme system
│   └── router/app_router.dart         # GoRouter with named routes + transitions
│
├── domain/
│   └── entities/
│       ├── song_entity.dart           # Core song model (pure Dart)
│       ├── playlist_entity.dart       # Playlist model + PlaylistType enum
│       └── player_state_entity.dart   # Full player state + RepeatMode
│
├── data/
│   ├── models/
│   │   ├── song_model.dart            # Hive @HiveType model for songs
│   │   ├── song_model.g.dart          # Generated Hive adapter (pre-generated)
│   │   ├── playlist_model.dart        # Hive model for playlists
│   │   ├── playlist_model.g.dart      # Generated adapter
│   │   ├── settings_model.dart        # Hive model for all settings
│   │   └── settings_model.g.dart      # Generated adapter
│   └── repositories/
│       └── song_repository.dart       # Hive + scanner integration, all CRUD
│
├── services/
│   ├── audio_handler.dart             # Background audio + media notification
│   ├── music_scanner_service.dart     # Device media store scanner
│   └── settings_service.dart         # Settings persistence (Hive)
│
├── presentation/
│   ├── splash/
│   │   └── splash_screen.dart         # Animated logo + app init
│   ├── home/
│   │   └── home_screen.dart           # Tab scaffold: Home/Songs/Albums/Artists/Playlists
│   ├── player/
│   │   ├── player_bloc.dart           # Audio player state management BLoC
│   │   └── now_playing_screen.dart    # Full player: disc, waveform, controls
│   ├── songs/
│   │   └── library_bloc.dart         # Library state: scan, sort, search, favorites
│   ├── playlists/
│   │   └── playlist_detail_screen.dart # Reorderable playlist view
│   ├── albums/
│   │   └── album_detail_screen.dart   # Track listing by album
│   ├── artists/
│   │   └── artist_detail_screen.dart  # Artist songs + album carousel
│   ├── search/
│   │   └── search_screen.dart         # Instant search with highlight
│   └── settings/
│       ├── settings_screen.dart       # Theme, colors, playback, library prefs
│       ├── settings_bloc.dart         # Theme/accent BLoC
│       └── equalizer_screen.dart      # 5-band EQ + effects + presets
│
└── widgets/
    ├── common/
    │   ├── mini_player.dart           # Persistent bottom player bar
    │   ├── song_artwork_widget.dart   # Cached album art with fallback
    │   └── song_tile.dart             # Reusable song list item + options sheet
    └── player/
        ├── waveform_visualizer.dart   # Animated music bars
        ├── queue_sheet.dart           # Reorderable queue bottom sheet
        ├── speed_sheet.dart           # Playback speed picker
        └── sleep_timer_sheet.dart     # Sleep timer set/cancel
```

---

## 🚀 Setup Steps

### 1. Create Flutter project
```bash
flutter create --org com.beatflow beatflow
cd beatflow
```

### 2. Copy all files from this project into your `beatflow/` directory

### 3. Add assets directory
```bash
mkdir -p assets/images assets/animations assets/fonts
```

Download Poppins font files from Google Fonts and place in `assets/fonts/`:
- `Poppins-Regular.ttf`
- `Poppins-Medium.ttf`
- `Poppins-SemiBold.ttf`
- `Poppins-Bold.ttf`

### 4. Install dependencies
```bash
flutter pub get
```

### 5. Run on Android device
```bash
flutter run --release
```

---

## 🔑 Key Architecture Decisions

| Layer | Technology | Reason |
|-------|-----------|--------|
| State | flutter_bloc | Predictable, testable, scalable |
| Audio | just_audio + audio_service | Gapless, background, notifications |
| Storage | Hive | Fast NoSQL, typed, Flutter-native |
| Navigation | go_router | Declarative, deep link ready |
| Scanner | on_audio_query | Native MediaStore access, fast |
| Permissions | permission_handler | Unified API for Android 10-14 |

---

## 🎵 Features Implemented

### Audio Engine
- ✅ Background playback (foreground service)
- ✅ Media notification with artwork, seek bar, controls
- ✅ Play / Pause / Next / Previous
- ✅ Shuffle (fisher-yates randomization)
- ✅ Repeat Off / Repeat All / Repeat One
- ✅ Playback speed 0.5x – 2.0x
- ✅ Gapless playback (ConcatenatingAudioSource)
- ✅ Sleep timer (configurable minutes)
- ✅ Queue management (add, remove, reorder)
- ✅ Handles corrupted files gracefully

### Library
- ✅ Auto-scan MP3, WAV, FLAC, M4A, AAC, OGG, OPUS, WMA
- ✅ Filters < 30s clips (ringtones, effects)
- ✅ Albums, Artists, Folders grouping
- ✅ Sort: Title, Artist, Duration, Date Added, Play Count
- ✅ Search with highlight
- ✅ Favorites toggle
- ✅ Play count + recently played tracking

### Playlists
- ✅ Create / Delete user playlists
- ✅ Drag & drop reorder
- ✅ Add / remove songs
- ✅ Auto-playlists: Recently Played, Most Played, Favorites

### UI / UX
- ✅ Material 3 with dynamic color
- ✅ Dark / Light / System theme
- ✅ 8 accent color options
- ✅ Animated splash screen
- ✅ Rotating vinyl disc on Now Playing
- ✅ Dynamic blurred background from album art
- ✅ Animated waveform visualizer
- ✅ Mini player with progress bar
- ✅ Hero transitions (artwork → now playing)
- ✅ Staggered list animations
- ✅ Search highlight text
- ✅ Glassmorphism cards

### Equalizer
- ✅ 5-band EQ (-15 to +15 dB)
- ✅ 8 presets: Normal, Rock, Pop, Classical, Jazz, Dance, Electronic, Hip-Hop
- ✅ Custom preset
- ✅ Bass Boost, Virtualizer, Reverb, Loudness Enhancer
- ✅ Enable/disable toggle

---

## 📱 Android Permissions

```xml
<!-- Required for Android 13+ -->
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />

<!-- Required for Android 12 and below -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />

<!-- Background audio -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

---

## ⚡ Performance Notes

- `on_audio_query` uses Android MediaStore directly — no file I/O loop
- Songs loaded from Hive (local DB) after first scan — instant cold start
- `SliverList` with `SliverChildBuilderDelegate` for lazy rendering
- `QueryArtworkWidget` caches artwork in memory
- `ConcatenatingAudioSource` with `useLazyPreparation: true` — loads next track just-in-time
- BLoC `buildWhen` filters prevent unnecessary rebuilds

---

## 🔧 Troubleshooting

**No songs found:**
- Ensure storage permission granted in device Settings → Apps → BeatFlow → Permissions
- On Android 13+, grant "Music and Audio" permission

**Background playback stops:**
- Disable battery optimization for BeatFlow in Settings

**Build fails:**
- Run `flutter clean && flutter pub get`
- Ensure `minSdkVersion 21` in `android/app/build.gradle`
