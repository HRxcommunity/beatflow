import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/song_entity.dart';
import '../../domain/entities/playlist_entity.dart';
import '../models/song_model.dart';
import '../models/playlist_model.dart';
import '../../services/music_scanner_service.dart';

class SongRepository {
  static const _songsBox = 'songs';
  static const _playlistsBox = 'playlists';

  late Box<SongModel> _songs;
  late Box<PlaylistModel> _playlists;
  final MusicScannerService _scanner;
  final _uuid = const Uuid();

  MusicScannerService get scanner => _scanner;

  SongRepository({MusicScannerService? scanner})
      : _scanner = scanner ?? MusicScannerService();

  Future<void> init() async {
    _songs = await Hive.openBox<SongModel>(_songsBox);
    _playlists = await Hive.openBox<PlaylistModel>(_playlistsBox);
  }

  // ─── Songs ────────────────────────────────────────────────────

  Future<List<SongEntity>> getAllSongs() async {
    if (_songs.isEmpty) {
      return rescanLibrary();
    }
    return _songs.values.map((m) => m.toEntity()).toList();
  }

  Future<List<SongEntity>> rescanLibrary({bool filterShortClips = true}) async {
    final songs = await _scanner.scanDeviceSongs(filterShortClips: filterShortClips);

    // Preserve play count & favorite from previous scan — snapshot BEFORE clear
    final Map<String, SongModel> previous = {};
    for (final m in _songs.values) {
      previous[m.data] = m;
    }

    await _songs.clear();

    final List<SongEntity> result = [];
    for (final s in songs) {
      final prev = previous[s.data];
      final enriched = prev != null
          ? s.copyWith(playCount: prev.playCount, isFavorite: prev.isFavorite)
          : s;
      await _songs.put(s.id, SongModel.fromEntity(enriched));
      result.add(enriched);
    }
    return result;
  }

  Future<void> toggleFavorite(int songId) async {
    final model = _songs.get(songId);
    if (model != null) {
      model.isFavorite = !model.isFavorite;
      await model.save();
    }
  }

  Future<void> incrementPlayCount(int songId) async {
    final model = _songs.get(songId);
    if (model != null) {
      model.playCount++;
      model.lastPlayed = DateTime.now();
      await model.save();
    }
  }

  List<SongEntity> getFavorites() => _songs.values
      .where((m) => m.isFavorite)
      .map((m) => m.toEntity())
      .toList();

  List<SongEntity> getRecentlyPlayed() {
    final played = _songs.values
        .where((m) => m.lastPlayed != null)
        .toList()
      ..sort((a, b) => b.lastPlayed!.compareTo(a.lastPlayed!));
    return played.take(50).map((m) => m.toEntity()).toList();
  }

  List<SongEntity> getMostPlayed() {
    final list = _songs.values.where((m) => m.playCount > 0).toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    return list.take(50).map((m) => m.toEntity()).toList();
  }

  Map<String, List<SongEntity>> getAlbums() {
    final map = <String, List<SongEntity>>{};
    for (final m in _songs.values) {
      map.putIfAbsent(m.album, () => []).add(m.toEntity());
    }
    return map;
  }

  Map<String, List<SongEntity>> getArtists() {
    final map = <String, List<SongEntity>>{};
    for (final m in _songs.values) {
      map.putIfAbsent(m.artist, () => []).add(m.toEntity());
    }
    return map;
  }

  Map<String, List<SongEntity>> getFolders() {
    final map = <String, List<SongEntity>>{};
    for (final m in _songs.values) {
      final folder = m.folderPath ?? 'Unknown';
      map.putIfAbsent(folder, () => []).add(m.toEntity());
    }
    return map;
  }

  List<SongEntity> search(String query) {
    final q = query.toLowerCase();
    return _songs.values
        .where((m) =>
            m.title.toLowerCase().contains(q) ||
            m.artist.toLowerCase().contains(q) ||
            m.album.toLowerCase().contains(q))
        .map((m) => m.toEntity())
        .toList();
  }

  // ─── Playlists ────────────────────────────────────────────────

  List<PlaylistEntity> getAllPlaylists() =>
      _playlists.values.map((m) => m.toEntity()).toList();

  Future<PlaylistEntity> createPlaylist(String name,
      {String? description}) async {
    final entity = PlaylistEntity(
      id: _uuid.v4(),
      name: name,
      description: description,
      songIds: [],
      createdAt: DateTime.now(),
    );
    await _playlists.put(entity.id, PlaylistModel.fromEntity(entity));
    return entity;
  }

  Future<void> deletePlaylist(String id) async {
    await _playlists.delete(id);
  }

  Future<void> addSongToPlaylist(String playlistId, int songId) async {
    final model = _playlists.get(playlistId);
    if (model != null && !model.songIds.contains(songId)) {
      model.songIds = [...model.songIds, songId];
      model.updatedAt = DateTime.now();
      await model.save();
    }
  }

  Future<void> removeSongFromPlaylist(String playlistId, int songId) async {
    final model = _playlists.get(playlistId);
    if (model != null) {
      model.songIds = model.songIds.where((id) => id != songId).toList();
      model.updatedAt = DateTime.now();
      await model.save();
    }
  }

  Future<void> reorderPlaylistSongs(
      String playlistId, int oldIndex, int newIndex) async {
    final model = _playlists.get(playlistId);
    if (model != null) {
      final list = List<int>.from(model.songIds);
      final item = list.removeAt(oldIndex);
      list.insert(newIndex, item);
      model.songIds = list;
      await model.save();
    }
  }
}
