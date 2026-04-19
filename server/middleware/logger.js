const fs = require('fs');
const path = require('path');
const morgan = require('morgan');

const logPath = path.resolve(__dirname, '../logs/server.log');
const logStream = fs.createWriteStream(logPath, { flags: 'a' });

const line =
  ':remote-addr - :remote-user [:date[clf]] ":method :url HTTP/:http-version" :status :res[content-length] - :response-time ms';

const accessStream = {
  write(message) {
    logStream.write(message);
    process.stdout.write(message);
  },
};

const requestLogger = morgan(line, {
  stream: accessStream,
});

module.exports = { requestLogger };
