import 'dart:convert';

import '../../auth/data/identity_store.dart';
import 'chain_anchor_service.dart';

/// Penyimpanan lokal riwayat anchor per pengguna.
///
/// Memakai pola kunci yang sama dengan data per-pengguna lain:
/// `chain_anchors_<userId>`. Tidak ada sinkronisasi Supabase pada fase ini.
/// Semua kunci berawalan [keyPrefix] ikut dihapus oleh `clearUserData` saat
/// logout (lihat `AuthRepository.userKeyPrefixes`).
class AnchorStore {
  AnchorStore(this._store, this._currentUserId);

  final IdentityStore _store;
  final String? Function() _currentUserId;

  static const keyPrefix = 'chain_anchors_';
  static const maxRecords = 50;

  static String keyFor(String userId) => '$keyPrefix$userId';

  String? _key() {
    final userId = _currentUserId();
    if (userId == null || userId.trim().isEmpty) return null;
    return keyFor(userId);
  }

  /// Baca riwayat pengguna aktif, terbaru lebih dulu. Data rusak diabaikan.
  List<AnchorRecord> load() {
    final key = _key();
    if (key == null) return const [];
    final raw = _store.get(key);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final records = <AnchorRecord>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        try {
          records.add(AnchorRecord.fromJson(Map<String, dynamic>.from(entry)));
        } catch (_) {
          continue;
        }
      }
      return records;
    } catch (_) {
      return const [];
    }
  }

  /// Tambah record terbaru di depan; maksimal [maxRecords] tersimpan.
  Future<void> add(AnchorRecord record) async {
    final key = _key();
    if (key == null) {
      throw StateError('Pengguna belum masuk; anchor tidak bisa disimpan.');
    }
    final records = load().where((r) => r.txHash != record.txHash).toList()
      ..insert(0, record);
    await _write(key, records);
  }

  /// Ganti record dengan [txHash] yang sama; tambahkan bila belum ada.
  Future<void> update(AnchorRecord record) async {
    final key = _key();
    if (key == null) {
      throw StateError('Pengguna belum masuk; anchor tidak bisa disimpan.');
    }
    final records = load();
    final index = records.indexWhere((r) => r.txHash == record.txHash);
    if (index < 0) {
      await add(record);
      return;
    }
    records[index] = record;
    await _write(key, records);
  }

  Future<void> _write(String key, List<AnchorRecord> records) {
    final trimmed = records.take(maxRecords).map((r) => r.toJson()).toList();
    return _store.put(key, jsonEncode(trimmed));
  }
}
