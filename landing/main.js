/**
 * NexChat Landing - SQLite في المتصفح (sql.js)
 * nexchat.site
 * عداد الزوار والتحميلات بدون باك إند - تخزين محلي
 */

(function () {
  'use strict';

  const IDB_NAME = 'nexchat-landing';
  const IDB_STORE = 'sqlite';
  const IDB_KEY = 'stats.db';
  const IDB_VERSION = 2;

  function getEl(id) { return document.getElementById(id); }

  function formatNum(n) {
    if (n >= 1000000) return (n / 1000000).toFixed(1) + 'M';
    if (n >= 1000) return (n / 1000).toFixed(1) + 'K';
    return String(n);
  }

  function openIdb() {
    return new Promise((resolve, reject) => {
      const req = indexedDB.open(IDB_NAME, IDB_VERSION);
      req.onerror = () => reject(req.error);
      req.onupgradeneeded = (e) => {
        const db = e.target.result;
        if (!db.objectStoreNames.contains(IDB_STORE)) {
          db.createObjectStore(IDB_STORE);
        }
      };
      req.onsuccess = () => resolve(req.result);
    });
  }

  function idbGet() {
    return openIdb().then((db) => {
      return new Promise((resolve, reject) => {
        const tx = db.transaction(IDB_STORE, 'readonly');
        const getReq = tx.objectStore(IDB_STORE).get(IDB_KEY);
        getReq.onsuccess = () => { db.close(); resolve(getReq.result || null); };
        getReq.onerror = () => { db.close(); reject(getReq.error); };
      });
    });
  }

  function idbPut(data) {
    return openIdb().then((db) => {
      return new Promise((resolve, reject) => {
        const tx = db.transaction(IDB_STORE, 'readwrite');
        tx.objectStore(IDB_STORE).put(data, IDB_KEY);
        tx.oncomplete = () => { db.close(); resolve(); };
        tx.onerror = () => { db.close(); reject(tx.error); };
      });
    });
  }

  function initDb(SQL, saved) {
    const db = saved ? new SQL.Database(saved) : new SQL.Database();
    db.run(`
      CREATE TABLE IF NOT EXISTS stats (
        key TEXT PRIMARY KEY,
        value INTEGER NOT NULL DEFAULT 0
      )
    `);
    const row = db.exec("SELECT value FROM stats WHERE key = 'visitors'");
    if (!row.length || !row[0].values.length) {
      db.run("INSERT OR REPLACE INTO stats (key, value) VALUES ('visitors', 0), ('downloads', 0)");
    }
    return db;
  }

  function getStats(db) {
    const v = db.exec("SELECT value FROM stats WHERE key = 'visitors'");
    const d = db.exec("SELECT value FROM stats WHERE key = 'downloads'");
    return {
      visitors: v.length && v[0].values.length ? v[0].values[0][0] : 0,
      downloads: d.length && d[0].values.length ? d[0].values[0][0] : 0
    };
  }

  function increment(db, key) {
    db.run("UPDATE stats SET value = value + 1 WHERE key = ?", [key]);
  }

  function saveDb(db) {
    return idbPut(db.export());
  }

  function updateUI(visitors, downloads) {
    const vEl = getEl('statVisitors');
    const dEl = getEl('statDownloads');
    const row = getEl('statsRow');
    if (vEl) vEl.textContent = formatNum(visitors);
    if (dEl) dEl.textContent = formatNum(downloads);
    if (row) row.removeAttribute('aria-hidden');
  }

  document.addEventListener('DOMContentLoaded', async function () {
    const row = getEl('statsRow');
    if (!row) return;

    if (typeof initSqlJs === 'undefined') {
      const vEl = getEl('statVisitors');
      const dEl = getEl('statDownloads');
      if (vEl) vEl.textContent = '0';
      if (dEl) dEl.textContent = '0';
      row.removeAttribute('aria-hidden');
      return;
    }

    try {
      const SQL = await initSqlJs({
        locateFile: (file) => 'https://cdn.jsdelivr.net/npm/sql.js@1.10.2/dist/' + file
      });

      const saved = await idbGet();
      const db = initDb(SQL, saved);

      let { visitors, downloads } = getStats(db);
      increment(db, 'visitors');
      visitors = getStats(db).visitors;
      await saveDb(db);
      updateUI(visitors, downloads);

      const btn = getEl('downloadBtn');
      if (btn) {
        btn.addEventListener('click', async function () {
          increment(db, 'downloads');
          const s = getStats(db);
          await saveDb(db);
          updateUI(s.visitors, s.downloads);
        });
      }
    } catch (e) {
      console.warn('SQLite init failed:', e);
      updateUI(0, 0);
    }
  });
})();
