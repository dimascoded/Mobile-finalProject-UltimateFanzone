'use strict';

const express = require('express');
const jwt = require('jsonwebtoken');
const auth = require('./auth');
const sync = require('./sync');

// Jangan hardcode secret. Production wajib menyetel JWT_SECRET di environment.
const SECRET = process.env.JWT_SECRET;
if (!SECRET && process.env.NODE_ENV === 'production') {
  throw new Error('JWT_SECRET wajib diset di environment untuk production');
}

const app = express();
app.use(express.json({ limit: '5mb' }));

const TOKEN_TTL = process.env.TOKEN_TTL || '7d';

function signToken(user) {
  return jwt.sign({ uid: user.id, email: user.email }, SECRET || 'dev-only-secret', {
    expiresIn: TOKEN_TTL,
  });
}

function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  if (!header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Header Authorization: Bearer <token> wajib' });
  }
  try {
    req.user = jwt.verify(header.slice(7), SECRET || 'dev-only-secret');
    return next();
  } catch (e) {
    return res.status(401).json({ error: 'Token tidak valid atau kedaluwarsa' });
  }
}

const wrap = (fn) => (req, res, next) => {
  try {
    fn(req, res);
  } catch (e) {
    if (e instanceof auth.HttpError) return res.status(e.status).json({ error: e.message });
    next(e);
  }
};

app.get('/health', (_req, res) => res.json({ ok: true, time: new Date().toISOString() }));

app.post('/auth/register', wrap((req, res) => {
  const user = auth.register(req.body || {});
  res.status(201).json({ id: user.id, email: user.email });
}));

app.post('/auth/login', wrap((req, res) => {
  const user = auth.login(req.body || {});
  res.json({ token: signToken(user) });
}));

app.post('/sync', requireAuth, wrap((req, res) => {
  res.json(sync.push(req.user.uid, req.body));
}));

app.get('/sync', requireAuth, wrap((req, res) => {
  res.json(sync.pull(req.user.uid));
}));

// Error handler terakhir.
app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: 'Kesalahan server' });
});

if (require.main === module) {
  const port = Number(process.env.PORT || 3000);
  app.listen(port, '0.0.0.0', () => {
    console.log(`Smart Football Fan API berjalan di http://0.0.0.0:${port}`);
    if (!SECRET) console.warn('PERINGATAN: JWT_SECRET belum diset, memakai secret dev.');
  });
}

module.exports = app;
