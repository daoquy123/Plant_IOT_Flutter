const nodemailer = require('nodemailer');
const { config } = require('../config/env');

let transporter;

function isEmailConfigured() {
  return Boolean(
    config.EMAIL_HOST
      && config.EMAIL_HOST_USER
      && config.EMAIL_HOST_PASSWORD
      && config.DEFAULT_FROM_EMAIL
      && config.REPORT_EMAIL_TO,
  );
}

function getTransporter() {
  if (!isEmailConfigured()) {
    throw new Error('Email is not configured (check EMAIL_* and REPORT_EMAIL_TO in .env)');
  }
  if (!transporter) {
    transporter = nodemailer.createTransport({
      host: config.EMAIL_HOST,
      port: config.EMAIL_PORT,
      secure: config.EMAIL_PORT === 465,
      auth: {
        user: config.EMAIL_HOST_USER,
        pass: config.EMAIL_HOST_PASSWORD,
      },
    });
  }
  return transporter;
}

async function sendMail({ subject, text, html }) {
  const transport = getTransporter();
  const info = await transport.sendMail({
    from: config.DEFAULT_FROM_EMAIL,
    to: config.REPORT_EMAIL_TO,
    subject,
    text,
    html,
  });
  return info;
}

module.exports = {
  isEmailConfigured,
  sendMail,
};
