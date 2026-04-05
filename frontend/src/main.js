import './css/style.css';

/* ── Step 1 ─────────────────────────────────────────────────── */
window.pick = (el) => {
  document.querySelectorAll('.pcard').forEach(c => c.classList.remove('active'));
  el.classList.add('active');
};

document.getElementById('btn-next')?.addEventListener('click', () => {
  const active = document.querySelector('.pcard.active');
  if (!active) return;
  localStorage.setItem('selectedProfile', active.dataset.profile);
  localStorage.setItem('driversEnabled',
    String(document.getElementById('google-toggle')?.checked ?? true));
  window.location.href = 'page1.html';
});

/* ── Step 2 ─────────────────────────────────────────────────── */
document.querySelectorAll('.os-card').forEach(card => {
  const go = () => {
    document.querySelectorAll('.os-card').forEach(c => c.classList.remove('selected'));
    card.classList.add('selected');
    localStorage.setItem('selectedStyle', card.dataset.style);
    setTimeout(() => { window.location.href = 'page2.html'; }, 220);
  };
  card.addEventListener('click', go);
  card.addEventListener('keydown', e => {
    if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); go(); }
  });
});

/* ── Step 3 — Cloud seçimi ──────────────────────────────────── */
const pLabel = { gunluk: '🏠', yazilimci: '💻', ozel: '🎛️' };
const sLabel = { windows: '🪟', macos: '🍎', kde: '🐧' };

const elP = document.getElementById('sum-profile');
const elS = document.getElementById('sum-style');
const elC = document.getElementById('sum-cloud');

if (elP) elP.textContent = pLabel[localStorage.getItem('selectedProfile')] || '—';
if (elS) elS.textContent = sLabel[localStorage.getItem('selectedStyle')]   || '—';

let selectedCloud = 'none';
let qrTimer = null;

// Geri butonu
document.getElementById('btn-back')?.addEventListener('click', () => {
  location.href = 'page1.html';
});

// Cloud kart seçimi → QR modal aç
document.querySelectorAll('.cloud-card').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.cloud-card').forEach(b => b.classList.remove('selected'));
    btn.classList.add('selected');
    selectedCloud = btn.dataset.cloud;
    openQR(selectedCloud);
  });
});

// Atla
document.getElementById('btn-skip')?.addEventListener('click', () => {
  document.querySelectorAll('.cloud-card').forEach(b => b.classList.remove('selected'));
  selectedCloud = 'none';
  if (elC) elC.innerHTML = '<i class="fa-solid fa-cloud-slash" style="opacity:.5"></i>';
});

/* ── QR Modal ───────────────────────────────────────────────── */
const cloudMeta = {
  google:   { label: 'Google Drive', icon: 'fa-brands fa-google',  color: '#4285f4' },
  icloud:   { label: 'iCloud',       icon: 'fa-brands fa-apple',   color: '#a0a0b8' },
  onedrive: { label: 'OneDrive',     icon: 'fa-solid fa-cloud',    color: '#0078d4' },
};

function openQR(provider) {
  const modal = document.getElementById('qr-modal');
  if (!modal) return;
  modal.classList.remove('hidden');

  const meta = cloudMeta[provider] || { label: provider, icon: 'fa-solid fa-cloud', color: '#fff' };
  const title = document.getElementById('qr-modal-title');
  if (title) title.innerHTML = `<i class="${meta.icon}" style="color:${meta.color}"></i>&nbsp;${meta.label}`;

  renderQR(provider);
  clearInterval(qrTimer);
  qrTimer = setInterval(() => renderQR(provider), 5 * 60 * 1000);
}

async function renderQR(provider) {
  const frame = document.getElementById('qr-frame');
  if (!frame) return;

  frame.innerHTML = '<div class="qr-spinner"></div>';

  try {
    const url = await window.go.main.App.RcloneAuthorize(provider);
    frame.innerHTML = '';
    const wrap = document.createElement('div');
    wrap.style.cssText = 'padding:8px;background:#fff;border-radius:10px';
    frame.appendChild(wrap);
    new QRCode(wrap, {
      text: url, width: 176, height: 176,
      colorDark: '#0c0e14', colorLight: '#ffffff',
      correctLevel: QRCode.CorrectLevel.H,
    });
  } catch (err) {
    frame.innerHTML = `<p style="color:#f87171;font-size:.75rem;padding:1rem;text-align:center">Bağlantı hatası</p>`;
    console.error('[QR]', err);
  }
}

document.getElementById('qr-close')?.addEventListener('click', closeQR);
document.getElementById('qr-confirm')?.addEventListener('click', () => {
  if (elC) {
    const meta = cloudMeta[selectedCloud];
    elC.innerHTML = meta
      ? `<i class="${meta.icon}" style="color:${meta.color}"></i>`
      : selectedCloud;
  }
  closeQR();
});

function closeQR() {
  clearInterval(qrTimer);
  document.getElementById('qr-modal')?.classList.add('hidden');
}

document.getElementById('qr-modal')?.addEventListener('click', e => {
  if (e.target === document.getElementById('qr-modal')) closeQR();
});

/* ── Kurulum başlat ─────────────────────────────────────────── */
document.getElementById('btn-finish')?.addEventListener('click', startSetup);

async function startSetup() {
  const profile = localStorage.getItem('selectedProfile') || 'gunluk';
  const drivers = localStorage.getItem('driversEnabled')  || 'false';
  const apps    = JSON.parse(localStorage.getItem('selectedApps') || '[]');

  // Ekranı değiştir
  document.getElementById('screen-select')?.classList.add('hidden');
  const installScreen = document.getElementById('screen-install');
  installScreen?.classList.remove('hidden');

  const logBox    = document.getElementById('log-box');
  const bar       = document.getElementById('install-bar');
  const statusEl  = document.getElementById('install-status');
  const pctEl     = document.getElementById('install-pct');

  let lineCount = 0;
  const ESTIMATED_LINES = 120; // yaklaşık toplam log satırı

  // Log satırı ekle
  function appendLog(line) {
    if (!logBox) return;
    lineCount++;

    const div = document.createElement('div');

    // Renk sınıfı
    if (line.startsWith('[OK]'))   div.className = 'log-ok';
    else if (line.startsWith('[ERR]') || line.startsWith('[FAIL')) div.className = 'log-err';
    else if (line.startsWith('[!!]')) div.className = 'log-warn';
    else if (line.startsWith('══'))  div.className = 'log-sec';
    else if (line.startsWith('[DONE]')) div.className = 'log-done';

    div.textContent = line;
    logBox.appendChild(div);
    logBox.scrollTop = logBox.scrollHeight;

    // Progress bar güncelle
    const pct = Math.min(Math.round((lineCount / ESTIMATED_LINES) * 95), 95);
    if (bar)    bar.style.width = pct + '%';
    if (pctEl)  pctEl.textContent = pct + '%';
    if (statusEl && line.startsWith('[>>]')) {
      statusEl.textContent = line.replace('[>>]', '').trim();
    }
  }

  // Wails event dinleyicileri
  const { EventsOn, EventsOff } = await import('../wailsjs/runtime/runtime.js');

  EventsOn('setup:log', ({ line }) => appendLog(line));

  EventsOn('setup:finished', ({ success, error }) => {
    EventsOff('setup:log');
    EventsOff('setup:finished');

    // Bar %100
    if (bar)   bar.style.width = '100%';
    if (pctEl) pctEl.textContent = '100%';

    // Done state göster
    const doneBox  = document.getElementById('install-done');
    const doneIcon = document.getElementById('done-icon');
    const doneMsg  = document.getElementById('done-msg');

    if (doneBox) doneBox.classList.remove('hidden');

    if (success) {
      if (doneIcon) doneIcon.textContent = '✅';
      if (doneMsg)  doneMsg.textContent  = 'Kurulum tamamlandı! Sistemi yeniden başlatmanız önerilir.';
      document.getElementById('install-title').textContent = 'Tamamlandı!';
      document.getElementById('install-icon').textContent  = '✅';
    } else {
      if (doneIcon) doneIcon.textContent = '⚠️';
      if (doneMsg)  doneMsg.textContent  = `Bazı paketler kurulamadı. Log dosyasını inceleyin.\n${error || ''}`;
      document.getElementById('install-title').textContent = 'Tamamlandı (uyarılarla)';
      document.getElementById('install-icon').textContent  = '⚠️';
    }
  });

  // Kurulumu başlat
  try {
    appendLog('[>>] Kurulum başlatılıyor...');
    const result = await window.go.main.App.RunSetup(
      profile, drivers, selectedCloud, apps, 'false'
    );
    appendLog(`[OK] ${result}`);
  } catch (err) {
    appendLog(`[ERR] Kurulum başlatılamadı: ${err}`);
    console.error('[Setup]', err);

    // Hata durumunda done göster
    const doneBox  = document.getElementById('install-done');
    const doneIcon = document.getElementById('done-icon');
    const doneMsg  = document.getElementById('done-msg');
    if (doneBox)  doneBox.classList.remove('hidden');
    if (doneIcon) doneIcon.textContent = '❌';
    if (doneMsg)  doneMsg.textContent  = `Hata: ${err}`;
  }
}

// Done butonu
document.getElementById('btn-done')?.addEventListener('click', () => {
  location.href = 'index.html';
});
