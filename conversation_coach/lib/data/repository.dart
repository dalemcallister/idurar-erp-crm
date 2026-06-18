import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'database.dart';
import 'models/analysis.dart';
import 'models/consent_record.dart';
import 'models/goal.dart';
import 'models/provider_config.dart';
import 'models/qa.dart';
import 'models/recommendation.dart';
import 'models/recording.dart';
import 'models/segment.dart';
import 'models/session.dart';
import 'models/speaker.dart';

/// Single data-access surface over the encrypted database. UI and services talk
/// to this, never to raw SQL.
class Repository {
  final AppDatabase _appDb;
  Repository(this._appDb);

  Database get _db => _appDb.db;

  // ---- Goals & rubrics -----------------------------------------------------

  Future<void> upsertRubric(Rubric r) => _db.insert(
        'rubrics',
        r.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<Rubric?> rubric(String id) async {
    final rows = await _db.query('rubrics', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Rubric.fromMap(rows.first);
  }

  Future<List<Rubric>> rubrics() async =>
      (await _db.query('rubrics')).map(Rubric.fromMap).toList();

  Future<void> upsertGoal(Goal g) => _db.insert(
        'goals',
        g.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<Goal>> goals() async =>
      (await _db.query('goals', orderBy: 'isTemplate DESC, name'))
          .map(Goal.fromMap)
          .toList();

  Future<Goal?> goal(String id) async {
    final rows = await _db.query('goals', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Goal.fromMap(rows.first);
  }

  // ---- Sessions ------------------------------------------------------------

  Future<void> upsertSession(Session s) => _db.insert(
        'sessions',
        s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<Session?> session(String id) async {
    final rows = await _db.query('sessions', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Session.fromMap(rows.first);
  }

  /// Searchable list of past sessions (Design §5 — Sessions area).
  Future<List<Session>> sessions({String query = ''}) async {
    final rows = query.isEmpty
        ? await _db.query('sessions', orderBy: 'createdAt DESC')
        : await _db.query('sessions',
            where: 'title LIKE ? OR context LIKE ?',
            whereArgs: ['%$query%', '%$query%'],
            orderBy: 'createdAt DESC');
    return rows.map(Session.fromMap).toList();
  }

  Future<void> updateSessionStatus(String id, SessionStatus status) =>
      _db.update('sessions', {'status': status.name},
          where: 'id = ?', whereArgs: [id]);

  // ---- Recordings ----------------------------------------------------------

  Future<void> upsertRecording(Recording r) => _db.insert(
        'recordings',
        r.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<Recording?> recordingForSession(String sessionId) async {
    final rows = await _db
        .query('recordings', where: 'sessionId = ?', whereArgs: [sessionId]);
    return rows.isEmpty ? null : Recording.fromMap(rows.first);
  }

  // ---- Speakers ------------------------------------------------------------

  Future<void> upsertSpeaker(Speaker s) => _db.insert(
        'speakers',
        s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<Speaker>> speakers(String sessionId) async =>
      (await _db.query('speakers', where: 'sessionId = ?', whereArgs: [sessionId]))
          .map(Speaker.fromMap)
          .toList();

  Future<Map<String, Speaker>> speakerMap(String sessionId) async {
    final list = await speakers(sessionId);
    return {for (final s in list) s.id: s};
  }

  // ---- Segments ------------------------------------------------------------

  Future<void> upsertSegment(Segment s) => _db.insert(
        'segments',
        s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> upsertSegments(List<Segment> segments) async {
    final batch = _db.batch();
    for (final s in segments) {
      batch.insert('segments', s.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Segment>> segments(String sessionId) async =>
      (await _db.query('segments',
              where: 'sessionId = ?', whereArgs: [sessionId], orderBy: 'startMs'))
          .map(Segment.fromMap)
          .toList();

  // ---- Analysis & recommendations -----------------------------------------

  Future<void> upsertAnalysis(Analysis a) => _db.insert(
        'analyses',
        a.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<Analysis?> analysisForSession(String sessionId) async {
    final rows = await _db.query('analyses',
        where: 'sessionId = ?',
        whereArgs: [sessionId],
        orderBy: 'createdAt DESC',
        limit: 1);
    debugPrint('[REPO] analysisForSession($sessionId) rows=${rows.length}');
    if (rows.isEmpty) return null;
    try {
      return Analysis.fromMap(rows.first);
    } catch (e, st) {
      debugPrint('[REPO] Analysis.fromMap FAILED: $e\n$st');
      rethrow;
    }
  }

  Future<List<Analysis>> allAnalyses() async =>
      (await _db.query('analyses', orderBy: 'createdAt'))
          .map(Analysis.fromMap)
          .toList();

  Future<void> replaceRecommendations(
      String sessionId, List<Recommendation> recs) async {
    await _db.delete('recommendations',
        where: 'sessionId = ?', whereArgs: [sessionId]);
    final batch = _db.batch();
    for (final r in recs) {
      batch.insert('recommendations', r.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<List<Recommendation>> recommendations(String sessionId) async =>
      (await _db.query('recommendations',
              where: 'sessionId = ?', whereArgs: [sessionId], orderBy: 'priority'))
          .map(Recommendation.fromMap)
          .toList();

  // ---- Consent -------------------------------------------------------------

  Future<void> upsertConsent(ConsentRecord c) => _db.insert(
        'consent_records',
        c.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  // ---- Q&A -----------------------------------------------------------------

  Future<QAThread> threadForSession(String sessionId) async {
    final rows = await _db
        .query('qa_threads', where: 'sessionId = ?', whereArgs: [sessionId]);
    if (rows.isNotEmpty) return QAThread.fromMap(rows.first);
    final thread = QAThread(id: 'qa-$sessionId', sessionId: sessionId);
    await _db.insert('qa_threads', thread.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return thread;
  }

  Future<void> addQAMessage(QAMessage m) => _db.insert(
        'qa_messages',
        m.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<QAMessage>> qaMessages(String threadId) async =>
      (await _db.query('qa_messages',
              where: 'threadId = ?', whereArgs: [threadId], orderBy: 'createdAt'))
          .map(QAMessage.fromMap)
          .toList();

  // ---- Provider configs ----------------------------------------------------

  Future<void> upsertProviderConfig(ProviderConfig c) => _db.insert(
        'provider_configs',
        c.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<ProviderConfig>> providerConfigs() async =>
      (await _db.query('provider_configs'))
          .map(ProviderConfig.fromMap)
          .toList();

  Future<void> deleteProviderConfig(String id) =>
      _db.delete('provider_configs', where: 'id = ?', whereArgs: [id]);

  // ---- App settings (durable key/value) ------------------------------------

  Future<String?> getSetting(String key) async {
    final rows = await _db
        .query('app_settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) => _db.insert(
        'app_settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> deleteSetting(String key) =>
      _db.delete('app_settings', where: 'key = ?', whereArgs: [key]);

  // ---- Deletion & retention (F-DAT-02 / F-DAT-03) --------------------------

  /// Per-session delete — removes the row (cascades to children) and the
  /// audio blob. Deletion is real.
  Future<void> deleteSession(String sessionId) async {
    final rec = await recordingForSession(sessionId);
    if (rec != null) {
      final f = File(rec.encryptedPath);
      if (await f.exists()) await f.delete();
    }
    await _db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  /// Retention: delete audio files older than [keepAudioDays] while keeping the
  /// transcript and analysis (F-DAT-03).
  Future<int> applyAudioRetention(int keepAudioDays) async {
    if (keepAudioDays <= 0) return 0;
    final cutoff = DateTime.now()
        .subtract(Duration(days: keepAudioDays))
        .millisecondsSinceEpoch;
    final old = await _db.rawQuery('''
      SELECT r.id AS rid, r.encryptedPath AS path
      FROM recordings r JOIN sessions s ON s.id = r.sessionId
      WHERE s.createdAt < ?''', [cutoff]);
    var purged = 0;
    for (final row in old) {
      final path = row['path'] as String;
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
        purged++;
      }
      await _db.delete('recordings',
          where: 'id = ?', whereArgs: [row['rid']]);
    }
    return purged;
  }
}
