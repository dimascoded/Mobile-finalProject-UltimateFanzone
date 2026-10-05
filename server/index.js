'use strict';

const express = require('express');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const jwt = require('jsonwebtoken');
const auth = require('./auth');
const sync = require('./sync');

/**
 * B1: JWT_SECRET WAJIB ada, tanpa pengecualian.
 *
 * Sebelumnya ada fallback 'dev-only-secret', jadi siapa pun yang tahu string itu
 * bisa membuat token sendiri lalu menyamar sebagai pengguna mana saja. Sekarang
 * server berhenti total kalau env-nya belum diisi, jadi tidak mungkin diam-diam
 * jalan dengan kunci yang ditebak.
 *
 * Development: salin .env.example, isi JWT_SECRET, lalu jalankan dengan
 * `JWT_SECRET=rahasia-panjang node index.js` (atau pakai `node --env-file=.env`).
 */
const SECRET = process.env.JWT_SECRET;
if (!SECRET) {
  throw new Error(
    'JWT_SECRET wajib diset sebelum server dijalankan. ' +
      'Contoh: JWT_SECRET=$(openssl rand -hex 32) node index.js ' +
      '(lihat .env.example).'
  );
}

const app = express();

// B7: header keamanan dasar (HSTS, CSP, proteksi content sniffing). Server ini
// hanya melayani JSON, jadi CSP ketat tidak mengganggu.
app.use(helmet());

// B3/B7: express-rate-limit menghitung jatah per req.ip. Kalau server dibuka
// langsung ke internet, `X-Forwarded-For` tidak boleh dipercaya karena pemangku
// bisa memalsukannya untuk menghindari limit, jadi defaultnya 0. Di belakang
// reverse proxy (Nginx/Cloudflare), set TRUST_PROXY_HOPS sesuai jumlah proxy
// yang benar-benar ada di depan server.
app.set('trust proxy', Number(process.env.TRUST_PROXY_HOPS || 0));

app.use(express.json({ limit: '5mb' }));

const TOKEN_TTL = process.env.TOKEN_TTL || '7d';

function signToken(user) {
  return jwt.sign({ uid: user.id, email: user.email }, SECRET, {
    expiresIn: TOKEN_TTL,
  });
}

function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  if (!header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Header Authorization: Bearer <token> wajib' });
  }
  try {
    req.user = jwt.verify(header.slice(7), SECRET);
    return next();
  } catch (e) {
    return res.status(401).json({ error: 'Token tidak valid atau kedaluwarsa' });
  }
}

/**
 * B3: `wrap` sekarang async, jadi handler boleh `await` (bcrypt async tidak
 * memblokir event loop). Galat tetap diterjemahkan: HttpError -> statusnya,
 * apa pun else -> 500 tanpa membocorkan detail internal.
 */
const wrap = (fn) => (req, res, next) => {
  Promise.resolve(fn(req, res, next)).catch((e) => {
    if (e instanceof auth.HttpError) {
      return res.status(e.status).json({ error: e.message });
    }
    return next(e);
  });
};

/**
 * B3: batasi percobaan brute force. Tanpa ini, `POST /auth/login` bisa
 * dipanggil tanpa batas; bcrypt yang mahal justru dipakai sebagai alat
 * untuk membuat server sibuk.
 */
const authLimiter = rateLimit({
  windowMs: Number(process.env.AUTH_RATE_WINDOW_MS || 15 * 60 * 1000),
  limit: Number(process.env.AUTH_RATE_LIMIT || 10),
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: 'Terlalu banyak percobaan. Coba lagi beberapa menit lagi.' },
});

app.get('/health', (_req, res) => res.json({ ok: true, time: new Date().toISOString() }));

app.post('/auth/register', authLimiter, wrap(async (req, res) => {
  const user = await auth.register(req.body || {});
  res.status(201).json({ id: user.id, email: user.email });
}));

app.post('/auth/login', authLimiter, wrap(async (req, res) => {
  const user = await auth.login(req.body || {});
  res.json({ token: signToken(user) });
}));

app.post('/sync', requireAuth, wrap((req, res) => {
  res.json(sync.push(req.user.uid, req.body));
}));

app.get('/sync', requireAuth, wrap((req, res) => {
  res.json(sync.pull(req.user.uid));
}));

// Error handler terakhir. B6: galat dari express.json (body rusak atau melebihi
// 5 MB) punya `status` sendiri dan harus dibalas apa adanya, bukan jadi 500.
app.use((err, _req, res, _next) => {
  if (err && typeof err.status === 'number' && err.status >= 400 && err.status < 500) {
    return res.status(err.status).json({ error: err.message });
  }
  console.error(err);
  return res.status(500).json({ error: 'Kesalahan server' });
});

if (require.main === module) {
  const port = Number(process.env.PORT || 3000);
  app.listen(port, '0.0.0.0', () => {
    console.log(`Smart Football Fan API berjalan di http://0.0.0.0:${port}`);
    // B7: di produksi, server ini hanya boleh dipasang di belakang reverse
    // proxy yang mengakhiri TLS. Tanpa HTTPS, token JWT terbaca polos oleh
    // siapa pun yang menyadap paket di jaringan.
    if (process.env.NODE_ENV === 'production') {
      console.log(
        'Mode produksi: pastikan HTTPS di terminate oleh reverse proxy.'
      );
    }
  });
}

module.exports = app;
