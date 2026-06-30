import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../domain/entities/song_entity.dart';
import '../../domain/entities/playlist_entity.dart';
import '../../data/repositories/song_repository.dart';
import '../../services/music_scanner_service.dart';
import '../../services/settings_service.dart';

// ─── Events ───────────────────────────────────────────────────

abstract class LibraryEvent extends Equatable {
  const LibraryEvent();
  @override
  List<Object?> get props => [];
}

class LibraryLoad extends LibraryEvent {}
class LibraryRescan extends LibraryEvent {}

class LibraryToggleFavorite extends LibraryEvent {
  final int songId;
  const LibraryToggleFavorite(this.songId);
  @override
  List<Object?> get props => [songId];
}

class LibrarySearch extends LibraryEvent {
  final String query;
  const LibrarySearch(this.query);
  @override
  List<Object?> get props => [query];
}

class LibrarySortChanged extends LibraryEvent {
  final SortOrder sortOrder;
  const LibrarySortChanged(this.sortOrder);
  @override
  List<Object?> get props => [sortOrder];
}

class LibraryCreatePlaylist extends LibraryEvent {
  final String name;
  final String? description;
  const LibraryCreatePlaylist(this.name, {this.description});
  @override
  List<Object?> get props => [name];
}

class LibraryDeletePlaylist extends LibraryEvent {
  final String id;
  const LibraryDeletePlaylist(this.id);
  @override
  List<Object?> get props => [id];
}

class LibraryAddSongToPlaylist extends LibraryEvent {
  final String playlistId;
  final int songId;
  const LibraryAddSongToPlaylist(this.playlistId, this.songId);
  @override
  List<Object?> get props => [playlistId, songId];
}

class LibraryRemoveSongFromPlaylist extends LibraryEvent {
  final String playlistId;
  final int songId;
  const LibraryRemoveSongFromPlaylist(this.playlistId, this.songId);
  @override
  List<Object?> get props => [playlistId, songId];
}

class LibraryReorderPlaylist extends LibraryEvent {
  final String playlistId;
  final int oldIndex;
  final int newIndex;
  const LibraryReorderPlaylist(this.playlistId, this.oldIndex, this.newIndex);
  @override
  List<Object?> get props => [playlistId, oldIndex, newIndex];
}

// ─── State ────────────────────────────────────────────────────

enum SortOrder { titleAsc, titleDesc, artistAsc, durationAsc, dateAddedDesc, playCountDesc }
enum LibraryStatus { initial, loading, loaded, scanning, error }

class LibraryState extends Equatable {
  final LibraryStatus status;
  final List<SongEntity> allSongs;
  final List<SongEntity> filteredSongs;
  final List<SongEntity> recentlyPlayed;
  final List<SongEntity> mostPlayed;
  final List<SongEntity> favorites;
  final Map<String, List<SongEntity>> albums;
  final Map<String, List<SongEntity>> artists;
  final Map<String, List<SongEntity>> folders;
  final List<PlaylistEntity> playlists;
  final SortOrder sortOrder;
  final String searchQuery;
  final ScanProgress? scanProgress;
  final String? error;

  const LibraryState({
    this.status = LibraryStatus.initial,
    this.allSongs = const [],
    this.filteredSongs = const [],
    this.recentlyPlayed = const [],
    this.mostPlayed = const [],
    this.favorites = const [],
    this.albums = const {},
    this.artists = const {},
    this.folders = const {},
    this.playlists = const [],
    this.sortOrder = SortOrder.titleAsc,
    this.searchQuery = '',
    this.scanProgress,
    this.error,
  });

  LibraryState copyWith({
    LibraryStatus? status,
    List<SongEntity>? allSongs,
    List<SongEntity>? filteredSongs,
    List<SongEntity>? recentlyPlayed,
    List<SongEntity>? mostPlayed,
    List<SongEntity>? favorites,
    Map<String, List<SongEntity>>? albums,
    Map<String, List<SongEntity>>? artists,
    Map<String, List<SongEntity>>? folders,
    List<PlaylistEntity>? playlists,
    SortOrder? sortOrder,
    String? searchQuery,
    ScanProgress? scanProgress,
    String? error,
  }) {
    return LibraryState(
      status: status ?? this.status,
      allSongs: allSongs ?? this.allSongs,
      filteredSongs: filteredSongs ?? this.filteredSongs,
      recentlyPlayed: recentlyPlayed ?? this.recentlyPlayed,
      mostPlayed: mostPlayed ?? this.mostPlayed,
      favorites: favorites ?? this.favorites,
      albums: albums ?? this.albums,
      artists: artists ?? this.artists,
      folders: folders ?? this.folders,
      playlists: playlists ?? this.playlists,
      sortOrder: sortOrder ?? this.sortOrder,
      searchQuery: searchQuery ?? this.searchQuery,
      scanProgress: scanProgress,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [
    status, allSongs.length, filteredSongs.length,
    sortOrder, searchQuery, scanProgress, error,
    playlists.length, favorites.length,
  ];
}

// ─── BLoC ─────────────────────────────────────────────────────

class LibraryBloc extends Bloc<LibraryEvent, LibraryState> {
  final SongRepository _repo;
  final SettingsService _settings;
  StreamSubscription? _scanSub;

  LibraryBloc({required SongRepository repo, required SettingsService settings})
      : _repo = repo,
        _settings = settings,
        super(const LibraryState()) {
    on<LibraryLoad>(_onLoad);
    on<LibraryRescan>(_onRescan);
    on<LibraryToggleFavorite>(_onToggleFavorite);
    on<LibrarySearch>(_onSearch);
    on<LibrarySortChanged>(_onSortChanged);
    on<LibraryCreatePlaylist>(_onCreatePlaylist);
    on<LibraryDeletePlaylist>(_onDeletePlaylist);
    on<LibraryAddSongToPlaylist>(_onAddSongToPlaylist);
    on<LibraryRemoveSongFromPlaylist>(_onRemoveSongFromPlaylist);
    on<LibraryReorderPlaylist>(_onReorderPlaylist);
  }

  Future<void> _onLoad(LibraryLoad e, Emitter<LibraryState> emit) async {
    emit(state.copyWith(status: LibraryStatus.loading));
    try {
      final songs = await _repo.getAllSongs();
      _emitLoadedState(emit, songs);
    } catch (err) {
      emit(state.copyWith(status: LibraryStatus.error, error: err.toString()));
    }
  }

  Future<void> _onRescan(LibraryRescan e, Emitter<LibraryState> emit) async {
    emit(state.copyWith(status: LibraryStatus.scanning));

    // Listen to scan progress and re-emit state updates
    _scanSub?.cancel();
    _scanSub = _repo.scanner.progressStream.listen((progress) {
      if (!isClosed) {
        emit(state.copyWith(
          status: LibraryStatus.scanning,
          scanProgress: progress,
        ));
      }
    });

    final songs = await _repo.rescanLibrary(
      filterShortClips: _settings.settings.filterShortClips,
    );
    _scanSub?.cancel();
    _emitLoadedState(emit, songs);
  }

  void _emitLoadedState(Emitter<LibraryState> emit, List<SongEntity> songs) {
    final sorted = _sort(songs, state.sortOrder);
    emit(state.copyWith(
      status: LibraryStatus.loaded,
      allSongs: sorted,
      filteredSongs: sorted,
      recentlyPlayed: _repo.getRecentlyPlayed(),
      mostPlayed: _repo.getMostPlayed(),
      favorites: _repo.getFavorites(),
      albums: _repo.getAlbums(),
      artists: _repo.getArtists(),
      folders: _repo.getFolders(),
      playlists: _repo.getAllPlaylists(),
      searchQuery: '',
    ));
  }

  Future<void> _onToggleFavorite(
      LibraryToggleFavorite e, Emitter<LibraryState> emit) async {
    await _repo.toggleFavorite(e.songId);
    final updated = state.allSongs.map((s) {
      if (s.id == e.songId) return s.copyWith(isFavorite: !s.isFavorite);
      return s;
    }).toList();
    emit(state.copyWith(
      allSongs: updated,
      filteredSongs: _filterAndSort(updated, state.searchQuery, state.sortOrder),
      favorites: _repo.getFavorites(),
    ));
  }

  void _onSearch(LibrarySearch e, Emitter<LibraryState> emit) {
    final results = e.query.isEmpty
        ? state.allSongs
        : _repo.search(e.query);
    emit(state.copyWith(
      filteredSongs: _sort(results, state.sortOrder),
      searchQuery: e.query,
    ));
  }

  void _onSortChanged(LibrarySortChanged e, Emitter<LibraryState> emit) {
    emit(state.copyWith(
      sortOrder: e.sortOrder,
      filteredSongs: _filterAndSort(state.allSongs, state.searchQuery, e.sortOrder),
    ));
  }

  Future<void> _onCreatePlaylist(
      LibraryCreatePlaylist e, Emitter<LibraryState> emit) async {
    await _repo.createPlaylist(e.name, description: e.description);
    emit(state.copyWith(playlists: _repo.getAllPlaylists()));
  }

  Future<void> _onDeletePlaylist(
      LibraryDeletePlaylist e, Emitter<LibraryState> emit) async {
    await _repo.deletePlaylist(e.id);
    emit(state.copyWith(playlists: _repo.getAllPlaylists()));
  }

  Future<void> _onAddSongToPlaylist(
      LibraryAddSongToPlaylist e, Emitter<LibraryState> emit) async {
    await _repo.addSongToPlaylist(e.playlistId, e.songId);
    emit(state.copyWith(playlists: _repo.getAllPlaylists()));
  }

  Future<void> _onRemoveSongFromPlaylist(
      LibraryRemoveSongFromPlaylist e, Emitter<LibraryState> emit) async {
    await _repo.removeSongFromPlaylist(e.playlistId, e.songId);
    emit(state.copyWith(playlists: _repo.getAllPlaylists()));
  }

  Future<void> _onReorderPlaylist(
      LibraryReorderPlaylist e, Emitter<LibraryState> emit) async {
    await _repo.reorderPlaylistSongs(e.playlistId, e.oldIndex, e.newIndex);
    emit(state.copyWith(playlists: _repo.getAllPlaylists()));
  }

  // ─── Helpers ──────────────────────────────────────────────────

  List<SongEntity> _sort(List<SongEntity> songs, SortOrder order) {
    final list = List<SongEntity>.from(songs);
    switch (order) {
      case SortOrder.titleAsc:
        list.sort((a, b) => a.title.compareTo(b.title));
      case SortOrder.titleDesc:
        list.sort((a, b) => b.title.compareTo(a.title));
      case SortOrder.artistAsc:
        list.sort((a, b) => a.artist.compareTo(b.artist));
      case SortOrder.durationAsc:
        list.sort((a, b) => a.duration.compareTo(b.duration));
      case SortOrder.dateAddedDesc:
        list.sort((a, b) {
          final da = a.dateAdded ?? DateTime(0);
          final db = b.dateAdded ?? DateTime(0);
          return db.compareTo(da);
        });
      case SortOrder.playCountDesc:
        list.sort((a, b) => b.playCount.compareTo(a.playCount));
    }
    return list;
  }

  List<SongEntity> _filterAndSort(
      List<SongEntity> songs, String query, SortOrder order) {
    var result = query.isEmpty
        ? songs
        : songs.where((s) =>
            s.title.toLowerCase().contains(query.toLowerCase()) ||
            s.artist.toLowerCase().contains(query.toLowerCase())).toList();
    return _sort(result, order);
  }

  @override
  Future<void> close() {
    _scanSub?.cancel();
    return super.close();
  }
}
