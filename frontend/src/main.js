import './css/style.css';
// Wails generated bindings — window.go yerine bunları kullan
import { ApplyKDETheme, RcloneAuthorize, RunSetup } from '../wailsjs/go/main/App.js';

/* ═══════════════════════════════════════════════════
   STEP 1 — Profil seçimi (index.html)
   ═══════════════════════════════════════════════════ */
window.pick = (el) => {
  document.querySelectorAll('.pcard').forEach(c => c.classList.remove('active'));
  el.classList.add('active');
};

document.getElementById('btn-next')?.addEventListener('click', () => {
  const active = document.querySelector('.pcard.active');
  if (!active) return;

  const profile = active.dataset.profile;
  localStorage.setItem('selectedProfile', profile);
  localStorage.setItem('driversEnabled',
    String(document.getElementById('google-toggle')?.checked ?? true));

  if (profile === 'ozel') {
    document.getElementById('modal-custom')?.classList.remove('hidden');
    return;
  }
  window.location.href = 'page1.html';
});

// Özel profil — uygulama toggle
document.querySelectorAll('.app-toggle').forEach(btn => {
  btn.addEventListener('click', () => btn.classList.toggle('selected'));
});

document.getElementById('btn-custom-confirm')?.addEventListener('click', () => {
  const selected = [...document.querySelectorAll('.app-toggle.selected')]
    .map(b => b.dataset.app);
  localStorage.setItem('selectedApps', JSON.stringify(selected));
  document.getElementById('modal-custom')?.classList.add('hidden');
  window.location.href = 'page1.html';
});

document.getElementById('btn-custom-cancel')?.addEventListener('click', () => {
  document.getElementById('modal-custom')?.classList.add('hidden');
});

/* ═══════════════════════════════════════════════════
   STEP 2 — Masaüstü seçimi (page1.html)
   ═══════════════════════════════════════════════════ */
document.querySelectorAll('.os-card').forEach(card => {
  const go = () => {
    document.querySelectorAll('.os-card').forEach(c => c.classList.remove('selected'));
    card.classList.add('selected');
    const style = card.dataset.style;
    localStorage.setItem('selectedStyle', style);

    // KDE Plasma varsa gerçek zamanlı tema uygula
    ApplyKDETheme(style).catch(() => {
      // KDE yoksa veya hata varsa sessizce geç
    });

    setTimeout(() => { window.location.href = 'page2.html'; }, 350);
  };
  card.addEventListener('click', go);
  card.addEventListener('keydown', e => {
    if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); go(); }
  });
});

/* ═══════════════════════════════════════════════════
   STEP 3 — Bulut + Başlat (page2.html)
   ═══════════════════════════════════════════════════ */
const pLabel = { gunluk: '🏠 Günlük', yazilimci: '💻 Yazılımcı', ozel: '🎛️ Özel' };
const sLabel = { windows: '🪟 Windows', macos: '🍎 macOS', kde: '🐧 KDE' };

const elP = document.getElementById('sum-profile');
const elS = document.getElementById('sum-style');
const elC = document.getElementById('sum-cloud');

if (elP) elP.textContent = pLabel[localStorage.getItem('selectedProfile')] || '—';
if (elS) elS.textContent = sLabel[localStorage.getItem('selectedStyle')]   || '—';

let selectedCloud = 'none';
let qrTimer       = null;

document.getElementById('btn-back')?.addEventListener('click', () => {
  location.href = 'page1.html';
});

/* Cloud kart → QR modal */
document.querySelectorAll('.cloud-card').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.cloud-card').forEach(b => b.classList.remove('selected'));
    btn.classList.add('selected');
    selectedCloud = btn.dataset.cloud;
    openQR(selectedCloud);
  });
});

document.getElementById('btn-skip')?.addEventListener('click', () => {
  document.querySelectorAll('.cloud-card').forEach(b => b.classList.remove('selected'));
  selectedCloud = 'none';
  if (elC) elC.innerHTML = '<i class="fa-solid fa-cloud-slash" style="opacity:.5"></i>';
});

/* ── QR Modal ─────────────────────────────────────────────── */
const cloudMeta = {
  google:   { label: 'Google Drive', icon: 'fa-brands fa-google', color: '#4285f4' },
  icloud:   { label: 'iCloud',       icon: 'fa-brands fa-apple',  color: '#a0a0b8' },
  onedrive: { label: 'OneDrive',     icon: 'fa-solid fa-cloud',   color: '#0078d4' },
};

function openQR(provider) {
  const modal = document.getElementById('qr-modal');
  if (!modal) return;
  modal.classList.remove('hidden');

  const meta  = cloudMeta[provider] || { label: provider, icon: 'fa-solid fa-cloud', color: '#fff' };
  const title = document.getElementById('qr-modal-title');
  if (title) title.innerHTML =
    `<i class="${meta.icon}" style="color:${meta.color}"></i>&nbsp;${meta.label}`;

  renderQR(provider);
  clearInterval(qrTimer);
  qrTimer = setInterval(() => renderQR(provider), 5 * 60 * 1000);
}

async function renderQR(provider) {
  const frame = document.getElementById('qr-frame');
  if (!frame) return;

  frame.innerHTML = '<div class="qr-spinner"></div>';

  try {
    // Wails binding'i direkt kullan — window.go kontrolü gerekmez
    const url = await RcloneAuthorize(provider);

    frame.innerHTML = '';
    const wrap = document.createElement('div');
    wrap.style.cssText = 'padding:10px;background:#fff;border-radius:12px;display:inline-block';
    frame.appendChild(wrap);

    if (typeof QRCode === 'undefined') {
      frame.innerHTML =
        '<p style="color:#f87171;font-size:.72rem;padding:1rem;text-align:center">' +
        'QR kütüphanesi yüklenemedi.</p>';
      return;
    }

    new QRCode(wrap, {
      text: url,
      width: 180,
      height: 180,
      colorDark: '#0c0e14',
      colorLight: '#ffffff',
      correctLevel: QRCode.CorrectLevel.H,
    });

    // URL fallback
    const urlEl = document.createElement('p');
    urlEl.style.cssText =
      'font-size:.6rem;color:#5c6478;margin-top:.5rem;word-break:break-all;' +
      'text-align:center;max-width:200px';
    urlEl.textContent = url;
    frame.appendChild(urlEl);

  } catch (err) {
    console.error('[QR]', err);
    const msg = String(err).includes('rclone')
      ? 'rclone kurulu değil.<br><small>yay -S rclone</small>'
      : String(err);
    frame.innerHTML =
      `<p style="color:#f87171;font-size:.72rem;padding:1rem;text-align:center">${msg}</p>`;
  }
}

document.getElementById('qr-close')?.addEventListener('click', closeQR);
document.getElementById('qr-confirm')?.addEventListener('click', () => {
  const meta = cloudMeta[selectedCloud];
  if (elC) elC.innerHTML = meta
    ? `<i class="${meta.icon}" style="color:${meta.color}"></i>&nbsp;${meta.label}`
    : selectedCloud;
  closeQR();
});
document.getElementById('qr-modal')?.addEventListener('click', e => {
  if (e.target === document.getElementById('qr-modal')) closeQR();
});

function closeQR() {
  clearInterval(qrTimer);
  document.getElementById('qr-modal')?.classList.add('hidden');
}

/* ── Kurulumu başlat ──────────────────────────────────────── */
document.getElementById('btn-finish')?.addEventListener('click', async () => {
  const profile = localStorage.getItem('selectedProfile') || 'gunluk';
  const drivers = localStorage.getItem('driversEnabled')  || 'false';
  const apps    = JSON.parse(localStorage.getItem('selectedApps') || '[]');

  const btn = document.getElementById('btn-finish');
  if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i>'; }

  try {
    await RunSetup(profile, drivers, selectedCloud, apps, 'false');
    location.href = 'index.html';
  } catch (err) {
    console.error('[Setup]', err);
    if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-rocket"></i>'; }
    const errEl = document.createElement('p');
    errEl.style.cssText = 'color:#f87171;font-size:.75rem;width:100%;text-align:center;margin-top:.5rem';
    errEl.textContent = 'Hata: ' + err;
    document.querySelector('.summary-bar')?.after(errEl);
  }
});
