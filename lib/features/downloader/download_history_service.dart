// lib/features/downloader/download_history_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'models/download_item.dart';

class DownloadHistoryService {
  static final instance = DownloadHistoryService._();
  DownloadHistoryService._();

  static const _boxName  = 'downloader_history';
  static const _itemsKey = 'items_v1';
  static const _maxItems = 200;

  Box<String>? _box;
  List<DownloadItem> _items = [];

  List<DownloadItem> get items => List.unmodifiable(_items);

  // ── Init ────────────────────────────────────────────────────────
  Future<void> init() async {
    try {
      _box = await Hive.openBox<String>(_boxName);
      _load();
    } catch (e) {
      debugPrint('[DownloadHistory] init error: $e');
      _items = [];
    }
  }

  void _load() {
    try {
      final raw = _box?.get(_itemsKey);
      if (raw == null || raw.isEmpty) { _items = []; return; }
      final list = jsonDecode(raw) as List<dynamic>;
      _items = list
          .whereType<Map<String, dynamic>>()
          .map(DownloadItem.fromJson)
          .toList();
    } catch (e) {
      debugPrint('[DownloadHistory] load error: $e');
      _items = [];
    }
  }

  Future<void> _save() async {
    try {
      // Trim oldest items if over limit
      if (_items.length > _maxItems) {
        _items = _items.sublist(_items.length - _maxItems);
      }
      await _box?.put(_itemsKey, jsonEncode(_items.map((i) => i.toJson()).toList()));
    } catch (e) {
      debugPrint('[DownloadHistory] save error: $e');
    }
  }

  // ── CRUD ────────────────────────────────────────────────────────
  Future<void> addItem(DownloadItem item) async {
    _items.insert(0, item);
    await _save();
  }

  Future<void> updateItem(DownloadItem item) async {
    final idx = _items.indexWhere((i) => i.id == item.id);
    if (idx != -1) {
      _items[idx] = item;
      await _save();
    }
  }

  Future<void> deleteItem(String id) async {
    _items.removeWhere((i) => i.id == id);
    await _save();
  }

  Future<void> clearAll() async {
    _items.clear();
    await _save();
  }

  // ── Queries ─────────────────────────────────────────────────────
  List<DownloadItem> getCompleted() => _items
      .where((i) =>
          i.status == DownloadStatus.completed ||
          i.status == DownloadStatus.failed ||
          i.status == DownloadStatus.cancelled)
      .toList();

  List<DownloadItem> getActive() => _items
      .where((i) =>
          i.status == DownloadStatus.pending ||
          i.status == DownloadStatus.preparing ||
          i.status == DownloadStatus.downloading)
      .toList();
}
