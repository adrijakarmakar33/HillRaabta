import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../mesh/message_model.dart';

enum LocalMessageStatus { received, sending, sent, failed }

class StoredMessage {
  final MeshMessage message;
  final LocalMessageStatus status;

  const StoredMessage({required this.message, required this.status});
}

class StoredFile {
  final int id;
  final String groupId;
  final String senderId;
  final String senderName;
  final String path;
  final DateTime timestamp;

  const StoredFile({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.senderName,
    required this.path,
    required this.timestamp,
  });
}

class ChatStore {
  ChatStore._();
  static final ChatStore instance = ChatStore._();

  Database? _db;

  Future<Database> _database() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, 'hill_raabta.db'),
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            senderId TEXT,
            senderName TEXT,
            groupId TEXT,
            content TEXT,
            type TEXT,
            ttl INTEGER,
            timestamp TEXT,
            status TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE received_files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            groupId TEXT,
            senderId TEXT,
            senderName TEXT,
            path TEXT,
            timestamp TEXT
          )
        ''');

        await _createMapTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Forward-only minimal migrations
        if (oldVersion < 2) {
          await _createMapTables(db);
        }
      },
    );
    return _db!;
  }

  static Future<void> _createMapTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS kv_settings (
        k TEXT PRIMARY KEY,
        v TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS saved_places (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        lat REAL,
        lng REAL,
        createdAt TEXT
      )
    ''');
  }

  Future<void> upsertMessage(StoredMessage item) async {
    final db = await _database();
    await db.insert(
      'messages',
      {
        ...item.message.toJson(),
        'status': item.status.name,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateMessageStatus(String id, LocalMessageStatus status) async {
    final db = await _database();
    await db.update(
      'messages',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<StoredMessage>> loadMessages(String groupId) async {
    final db = await _database();
    final rows = await db.query(
      'messages',
      where: 'groupId = ?',
      whereArgs: [groupId],
      orderBy: 'timestamp ASC',
    );
    return rows.map((row) {
      final msg = MeshMessage.fromJson({
        'id': row['id'],
        'senderId': row['senderId'],
        'senderName': row['senderName'],
        'groupId': row['groupId'],
        'content': row['content'],
        'type': row['type'],
        'ttl': row['ttl'],
        'timestamp': row['timestamp'],
      });
      final statusRaw = (row['status'] as String?) ?? 'received';
      final status = LocalMessageStatus.values.firstWhere(
        (s) => s.name == statusRaw,
        orElse: () => LocalMessageStatus.received,
      );
      return StoredMessage(message: msg, status: status);
    }).toList();
  }

  Future<void> addReceivedFile({
    required String groupId,
    required String senderId,
    required String senderName,
    required String path,
    required DateTime timestamp,
  }) async {
    final db = await _database();
    await db.insert('received_files', {
      'groupId': groupId,
      'senderId': senderId,
      'senderName': senderName,
      'path': path,
      'timestamp': timestamp.toIso8601String(),
    });
  }

  Future<List<StoredFile>> loadReceivedFiles(String groupId) async {
    final db = await _database();
    final rows = await db.query(
      'received_files',
      where: 'groupId = ?',
      whereArgs: [groupId],
      orderBy: 'timestamp DESC',
    );
    return rows
        .map(
          (row) => StoredFile(
            id: row['id'] as int,
            groupId: row['groupId'] as String,
            senderId: row['senderId'] as String,
            senderName: row['senderName'] as String,
            path: row['path'] as String,
            timestamp: DateTime.parse(row['timestamp'] as String),
          ),
        )
        .toList();
  }

  // -------- Map offline support --------

  Future<void> setSetting(String key, String value) async {
    final db = await _database();
    await db.insert(
      'kv_settings',
      {'k': key, 'v': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await _database();
    final rows = await db.query(
      'kv_settings',
      where: 'k = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['v'] as String?;
  }

  Future<int> addSavedPlace({
    required String name,
    required double lat,
    required double lng,
  }) async {
    final db = await _database();
    return await db.insert('saved_places', {
      'name': name,
      'lat': lat,
      'lng': lng,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<int> upsertSavedPlace({
    required String name,
    required double lat,
    required double lng,
  }) async {
    final db = await _database();
    final trimmed = name.trim();
    final rows = await db.query('saved_places');
    for (final row in rows) {
      final existing = (row['name'] as String?) ?? '';
      if (existing.toLowerCase() == trimmed.toLowerCase()) {
        final id = row['id'] as int;
        await db.update(
          'saved_places',
          {
            'lat': lat,
            'lng': lng,
            'createdAt': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        return id;
      }
    }
    return addSavedPlace(name: trimmed, lat: lat, lng: lng);
  }

  Future<List<Map<String, Object?>>> listSavedPlaces() async {
    final db = await _database();
    return await db.query(
      'saved_places',
      orderBy: 'createdAt DESC',
    );
  }

  Future<void> deleteSavedPlace(int id) async {
    final db = await _database();
    await db.delete('saved_places', where: 'id = ?', whereArgs: [id]);
  }
}
