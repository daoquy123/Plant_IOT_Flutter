import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/chat_conversation.dart';
import '../models/chat_message.dart';

class ChatDatabase {
  static const _dbName = 'smart_garden_chat.db';
  static const _messagesTable = 'messages';
  static const _conversationsTable = 'conversations';

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _createConversationsTable(db);
        await _createMessagesTable(db, withConversationId: true);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createConversationsTable(db);
          await db.execute(
            'ALTER TABLE $_messagesTable ADD COLUMN conversation_id INTEGER',
          );

          final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $_messagesTable'),
          );
          if (count != null && count > 0) {
            final now = DateTime.now().millisecondsSinceEpoch;
            final convId = await db.insert(_conversationsTable, {
              'title': 'Cuộc trò chuyện cũ',
              'model': 'resnet',
              'created_at': now,
              'updated_at': now,
            });
            await db.update(
              _messagesTable,
              {'conversation_id': convId},
            );
          }
        }
      },
    );
    return _db!;
  }

  Future<void> _createConversationsTable(Database db) async {
    await db.execute('''
      CREATE TABLE $_conversationsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        model TEXT NOT NULL DEFAULT 'resnet',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createMessagesTable(
    Database db, {
    required bool withConversationId,
  }) async {
    await db.execute('''
      CREATE TABLE $_messagesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ${withConversationId ? 'conversation_id INTEGER NOT NULL,' : ''}
        text TEXT NOT NULL,
        sender_type TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        local_image_path TEXT
      )
    ''');
  }

  Future<List<ChatConversation>> loadConversations() async {
    final db = await database;
    final rows = await db.query(
      _conversationsTable,
      orderBy: 'updated_at DESC',
    );
    return rows.map((e) => ChatConversation.fromMap(e)).toList();
  }

  Future<ChatConversation> createConversation({
    String title = 'Cuộc trò chuyện mới',
    String model = 'resnet',
  }) async {
    final db = await database;
    final now = DateTime.now();
    final id = await db.insert(_conversationsTable, {
      'title': title,
      'model': model,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });
    return ChatConversation(
      id: id,
      title: title,
      model: model,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> updateConversation({
    required int id,
    String? title,
    String? model,
    DateTime? updatedAt,
  }) async {
    final db = await database;
    final patch = <String, Object?>{};
    if (title != null) patch['title'] = title;
    if (model != null) patch['model'] = model;
    patch['updated_at'] =
        (updatedAt ?? DateTime.now()).millisecondsSinceEpoch;
    if (patch.isEmpty) return;
    await db.update(
      _conversationsTable,
      patch,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteConversation(int id) async {
    final db = await database;
    await db.delete(
      _messagesTable,
      where: 'conversation_id = ?',
      whereArgs: [id],
    );
    await db.delete(
      _conversationsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<ChatMessage>> loadMessages(int conversationId) async {
    final db = await database;
    final rows = await db.query(
      _messagesTable,
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC',
    );
    return rows.map((e) => ChatMessage.fromMap(e)).toList();
  }

  Future<ChatMessage> insertMessage({
    required int conversationId,
    required String text,
    required SenderType senderType,
    String? localImagePath,
  }) async {
    final db = await database;
    final now = DateTime.now();
    final id = await db.insert(_messagesTable, {
      'conversation_id': conversationId,
      'text': text,
      'sender_type': senderType == SenderType.user ? 'user' : 'ai',
      'created_at': now.millisecondsSinceEpoch,
      'local_image_path': localImagePath,
    });
    await updateConversation(id: conversationId, updatedAt: now);
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      text: text,
      senderType: senderType,
      createdAt: now,
      localImagePath: localImagePath,
    );
  }

  Future<int> countMessages(int conversationId) async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM $_messagesTable WHERE conversation_id = ?',
        [conversationId],
      ),
    );
    return count ?? 0;
  }
}
