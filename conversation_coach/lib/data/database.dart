import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'secure_keystore.dart';

/// Encryption at rest — SQLCipher for the database, with the key held in the OS
/// keystore (Tech Spec §8). The schema follows the logical data model (§7).
class AppDatabase {
  final SecureKeystore keystore;
  Database? _db;

  AppDatabase(this.keystore);

  Database get db {
    final d = _db;
    if (d == null) {
      throw StateError('AppDatabase.open() must be called first.');
    }
    return d;
  }

  Future<Directory> _baseDir() async =>
      getApplicationDocumentsDirectory();

  Future<String> databasePath() async {
    final dir = await _baseDir();
    return p.join(dir.path, 'conversation_coach.db');
  }

  Future<void> open() async {
    if (_db != null) return;
    final path = await databasePath();
    final key = await keystore.databaseKey();
    _db = await openDatabase(
      path,
      password: key, // SQLCipher encryption key
      version: 3,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createSchema,
      onUpgrade: _migrate,
    );
  }

  Future<void> _migrate(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // F-MOD-06 — per-session token accounting.
      await db.execute(
          'ALTER TABLE analyses ADD COLUMN inputTokens INTEGER NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE analyses ADD COLUMN outputTokens INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 3) {
      // "Your next steps" — personal follow-up actions + the follow-up email.
      await db.execute('ALTER TABLE analyses ADD COLUMN nextStepsJson TEXT');
    }
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        displayName TEXT NOT NULL,
        settingsJson TEXT
      )''');

    await db.execute('''
      CREATE TABLE rubrics (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        dimensions TEXT NOT NULL
      )''');

    await db.execute('''
      CREATE TABLE goals (
        id TEXT PRIMARY KEY,
        userId TEXT,
        name TEXT NOT NULL,
        description TEXT,
        rubricId TEXT NOT NULL,
        isTemplate INTEGER NOT NULL DEFAULT 0
      )''');

    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        userId TEXT NOT NULL,
        title TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        durationSec INTEGER NOT NULL DEFAULT 0,
        language TEXT NOT NULL,
        goalId TEXT NOT NULL,
        context TEXT,
        consentRecorded INTEGER NOT NULL DEFAULT 0,
        providerConfigSnapshot TEXT,
        status TEXT NOT NULL
      )''');

    await db.execute('''
      CREATE TABLE recordings (
        id TEXT PRIMARY KEY,
        sessionId TEXT NOT NULL,
        encryptedPath TEXT NOT NULL,
        sampleRate INTEGER NOT NULL,
        channels INTEGER NOT NULL,
        source TEXT NOT NULL,
        channelMap TEXT,
        markedMomentsMs TEXT,
        FOREIGN KEY(sessionId) REFERENCES sessions(id) ON DELETE CASCADE
      )''');

    await db.execute('''
      CREATE TABLE speakers (
        id TEXT PRIMARY KEY,
        sessionId TEXT NOT NULL,
        label TEXT NOT NULL,
        isUser INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(sessionId) REFERENCES sessions(id) ON DELETE CASCADE
      )''');

    await db.execute('''
      CREATE TABLE segments (
        id TEXT PRIMARY KEY,
        sessionId TEXT NOT NULL,
        speakerId TEXT NOT NULL,
        startMs INTEGER NOT NULL,
        endMs INTEGER NOT NULL,
        text TEXT NOT NULL,
        textEmotion TEXT,
        intentTag TEXT,
        prosodyFeaturesJson TEXT,
        embeddingRef TEXT,
        FOREIGN KEY(sessionId) REFERENCES sessions(id) ON DELETE CASCADE
      )''');

    await db.execute('''
      CREATE TABLE analyses (
        id TEXT PRIMARY KEY,
        sessionId TEXT NOT NULL,
        headline TEXT,
        summary TEXT,
        topicsJson TEXT,
        decisionsJson TEXT,
        actionItemsJson TEXT,
        openQuestionsJson TEXT,
        strengthsJson TEXT,
        improvementsJson TEXT,
        nextStepsJson TEXT,
        dynamicsJson TEXT,
        scoreOverall REAL NOT NULL DEFAULT 0,
        scoreByDimensionJson TEXT,
        emotionArcJson TEXT,
        modelUsed TEXT,
        promptVersion TEXT,
        createdAt INTEGER NOT NULL,
        inputTokens INTEGER NOT NULL DEFAULT 0,
        outputTokens INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(sessionId) REFERENCES sessions(id) ON DELETE CASCADE
      )''');

    await db.execute('''
      CREATE TABLE recommendations (
        id TEXT PRIMARY KEY,
        sessionId TEXT NOT NULL,
        priority INTEGER NOT NULL,
        text TEXT NOT NULL,
        evidenceRefs TEXT,
        whatToTryInstead TEXT,
        FOREIGN KEY(sessionId) REFERENCES sessions(id) ON DELETE CASCADE
      )''');

    await db.execute('''
      CREATE TABLE qa_threads (
        id TEXT PRIMARY KEY,
        sessionId TEXT NOT NULL,
        FOREIGN KEY(sessionId) REFERENCES sessions(id) ON DELETE CASCADE
      )''');

    await db.execute('''
      CREATE TABLE qa_messages (
        id TEXT PRIMARY KEY,
        threadId TEXT NOT NULL,
        role TEXT NOT NULL,
        text TEXT NOT NULL,
        citationsJson TEXT,
        createdAt INTEGER NOT NULL,
        FOREIGN KEY(threadId) REFERENCES qa_threads(id) ON DELETE CASCADE
      )''');

    await db.execute('''
      CREATE TABLE provider_configs (
        id TEXT PRIMARY KEY,
        provider TEXT NOT NULL,
        model TEXT NOT NULL,
        endpointUrl TEXT,
        apiKeyRef TEXT,
        paramsJson TEXT,
        perTaskOverridesJson TEXT
      )''');

    // Durable key/value app settings (preferred provider, retention, language,
    // and a record of any temporary fallback so it can be reverted later).
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )''');

    await db.execute('''
      CREATE TABLE consent_records (
        id TEXT PRIMARY KEY,
        sessionId TEXT NOT NULL,
        method TEXT NOT NULL,
        jurisdictionNote TEXT,
        timestamp INTEGER NOT NULL,
        FOREIGN KEY(sessionId) REFERENCES sessions(id) ON DELETE CASCADE
      )''');

    await db.execute(
        'CREATE INDEX idx_segments_session ON segments(sessionId, startMs)');
    await db.execute(
        'CREATE INDEX idx_sessions_created ON sessions(createdAt DESC)');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Deletes the database file entirely — part of the real "wipe everything"
  /// path (F-DAT-02).
  Future<void> deleteFile() async {
    await close();
    final path = await databasePath();
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
