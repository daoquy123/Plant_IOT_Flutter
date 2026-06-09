const express = require('express');
const { runHealthCheck } = require('../../services/healthCheckService');
const { getConversationWithMessages } = require('../../services/chatService');

const router = express.Router();

router.post('/health-check', async (req, res, next) => {
  try {
    const model = (req.body?.model || 'resnet').toString().trim() || 'resnet';
    const deviceId = (req.body?.device_id || 'esp32_garden_main').toString().trim();
    const payload = await runHealthCheck({
      publishCameraCommand: req.app.locals.publishCameraCommand,
      io: req.app.locals.io,
      model,
      deviceId,
    });
    return res.json({
      success: true,
      reply: payload.reply,
      lcd: payload.lcd,
      conversation_id: payload.conversation.id,
      image_url: payload.image_url,
    });
  } catch (err) {
    return next(err);
  }
});

router.get('/conversations/:id', (req, res, next) => {
  const conversationId = Number(req.params.id);
  if (!Number.isInteger(conversationId) || conversationId <= 0) {
    return res.status(400).json({ success: false, message: 'Invalid conversation id.' });
  }
  getConversationWithMessages(conversationId, (err, data) => {
    if (err) return next(err);
    if (!data) {
      return res.status(404).json({ success: false, message: 'Conversation not found.' });
    }
    return res.json({ success: true, ...data });
  });
});

module.exports = router;
