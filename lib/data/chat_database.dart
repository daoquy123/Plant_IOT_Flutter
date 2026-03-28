import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/chat_message.dart';

class ChatDatabase {
  static const _dbName = 'smart_garden_chat.db';
  static const _table = 'messages';

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            sender_type TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            local_image_path TEXT
          )
        ''');
      },
    );
    return _db!;
  }

  Future<List<ChatMessage>> loadMessages() async {
    final db = await database;
    final rows = await db.query(_table, orderBy: 'created_at ASC');
    return rows.map((e) => ChatMessage.fromMap(e)).toList();
  }

  Future<ChatMessage> insertMessage({
    required String text,
    required SenderType senderType,
    String? localImagePath,
  }) async {
    final db = await database;
    final now = DateTime.now();
    final id = await db.insert(_table, {
      'text': text,
      'sender_type': senderType == SenderType.user ? 'user' : 'ai',
      'created_at': now.millisecondsSinceEpoch,
      'local_image_path': localImagePath,
    });
    return ChatMessage(
      id: id,
      text: text,
      senderType: senderType,
      createdAt: now,
      localImagePath: localImagePath,
    );
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete(_table);
  }
}
