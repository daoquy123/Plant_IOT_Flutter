const { getDb } = require('../config/database');

function createConversation({ title, model, source, deviceId, imageUrl }, callback) {
  const db = getDb();
  const now = new Date().toISOString();
  const sql = `
    INSERT INTO chat_conversations (
      title,
      model,
      source,
      device_id,
      image_url,
      created_at,
      updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  `;

  db.run(
    sql,
    [
      title || 'Kiem tra suc khoe cay',
      model || 'resnet',
      source || 'esp32',
      deviceId || null,
      imageUrl || null,
      now,
      now,
    ],
    function onInsert(err) {
      if (err) return callback(err);
      callback(null, {
        id: this.lastID,
        title: title || 'Kiem tra suc khoe cay',
        model: model || 'resnet',
        source: source || 'esp32',
        device_id: deviceId || null,
        image_url: imageUrl || null,
        created_at: now,
        updated_at: now,
      });
    }
  );
}

function insertMessage({ conversationId, role, content }, callback) {
  const db = getDb();
  const now = new Date().toISOString();
  const sql = `
    INSERT INTO chat_messages (
      conversation_id,
      session_id,
      role,
      content,
      created_at
    ) VALUES (?, ?, ?, ?, ?)
  `;

  db.run(
    sql,
    [
      conversationId,
      String(conversationId),
      role,
      content,
      now,
    ],
    function onMessage(err) {
      if (err) return callback(err);
      const messageId = this.lastID;
      db.run(
        'UPDATE chat_conversations SET updated_at = ? WHERE id = ?',
        [now, conversationId],
        (updateErr) => {
          if (updateErr) return callback(updateErr);
          callback(null, {
            id: messageId,
            conversation_id: conversationId,
            role,
            content,
            created_at: now,
          });
        }
      );
    }
  );
}

function getConversationWithMessages(conversationId, callback) {
  const db = getDb();
  db.get(
    'SELECT * FROM chat_conversations WHERE id = ?',
    [conversationId],
    (err, conversation) => {
      if (err) return callback(err);
      if (!conversation) return callback(null, null);
      db.all(
        'SELECT * FROM chat_messages WHERE conversation_id = ? ORDER BY id ASC',
        [conversationId],
        (msgErr, messages) => {
          if (msgErr) return callback(msgErr);
          callback(null, { conversation, messages });
        }
      );
    }
  );
}

module.exports = {
  createConversation,
  insertMessage,
  getConversationWithMessages,
};
