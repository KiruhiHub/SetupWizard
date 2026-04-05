import './css/style.css';

/* ── Step 1 ─────────────────────────────────────── */
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

/* ── Step 2 ─────────────────────────────────────── */
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

/* ── Step 3 ─────────────────────────────────────── */
const pLabel = { gunluk: '🏠', yazilimci: '💻', ozel: '🎛️' };
const sLabel = { windows: '🪟', macos: '🍎', kde: '🐧' };

const elP = document.getElementById('sum-profile');
const elS = document.getElementById('sum-style');
const elC = document.getElementById('sum-cloud');

if (elP) elP.textContent = pLabel[localStorage.getItem('selectedProfile')] || '—';
if (elS) elS.textContent = sLabel[localStorage.getItem('selectedStyle')]   || '—';

let selectedCloud = 'none';
let qrRefreshTimer = null;

/* Cloud card click → open QR modal */
document.querySelectorAll('.cloud-card').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.cloud-card').forEach(b => b.classList.remove('selected'));
    btn.classList.add('selected');
    selectedCloud = btn.dataset.cloud;
    openQR(selectedCloud);
  });
});

/* Skip */
document.getElementById('btn-skip')?.addEventListener('click', () => {
  document.querySelectorAll('.cloud-card').forEach(b => b.classList.remove('selected'));
  selectedCloud = 'none';
  if (elC) elC.innerHTML = '<i class="fa-solid fa-cloud-slash" style="opacity:.5"></i>';
});

/* ── QR Modal ────────────────────────────────────── */
const modal      = document.getElementById('qr-modal');
const qrFrame    = document.getElementById('qr-frame');
const qrSpinner  = document.getElementById('qr-spinner');
const qrHint     = document.getElementById('qr-hint');
const qrTitle    = document.getElementById('qr-modal-title');

const cloudMeta = {
  google:   { label: 'Google Drive', icon: 'fa-brands fa-google',  color: '#4285f4' },
  icloud:   { label: 'iCloud',       icon: 'fa-brands fa-apple',   color: '#a0a0b8' },
  onedrive: { label: 'OneDrive',     icon: 'fa-solid fa-cloud',    color: '#0078d4' },
};

function openQR(provider) {
  if (!modal) return;
  modal.classList.remove('hidden');

  const meta = cloudMeta[provider] || { label: provider, icon: 'fa-solid fa-cloud', color: '#fff' };
  if (qrTitle) qrTitle.innerHTML =
    `<i class="${meta.icon}" style="color:${meta.color}"></i>&nbsp;${meta.label}`;

  renderQR(provider);
  clearInterval(qrRefreshTimer);
  qrRefreshTimer = setInterval(() => renderQR(provider), 5 * 60 * 1000);
}

async function renderQR(provider) {
  if (!qrFrame) return;

  // Show spinner
  qrFrame.innerHTML = '';
  const spinner = document.createElement('div');
  spinner.className = 'qr-spinner';
  qrFrame.appendChild(spinner);

  try {
    const url = await window.go.main.App.RcloneAuthorize(provider);

    qrFrame.innerHTML = '';
    const wrap = document.createElement('div');
    wrap.style.cssText = 'padding:8px;background:#fff;border-radius:10px';
    qrFrame.appendChild(wrap);

    new QRCode(wrap, {
      text: url,
      width: 176,
      height: 176,
      colorDark: '#0c0e14',
      colorLight: '#ffffff',
      correctLevel: QRCode.CorrectLevel.H,
    });

    if (qrHint) qrHint.innerHTML =
      '<i class="fa-solid fa-mobile-screen"></i>&nbsp;Telefonunla tara';

  } catch (err) {
    qrFrame.innerHTML = '';
    const errEl = document.createElement('p');
    errEl.style.cssText = 'color:#f87171;font-size:.75rem;text-align:center;padding:1rem';
    errEl.textContent = 'Bağlantı hatası';
    qrFrame.appendChild(errEl);
    console.error('[QR]', err);
  }
}

/* Close modal */
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
  clearInterval(qrRefreshTimer);
  if (modal) modal.classList.add('hidden');
}

/* Close on overlay click */
modal?.addEventListener('click', e => { if (e.target === modal) closeQR(); });

/* ── Launch ──────────────────────────────────────── */
document.getElementById('btn-finish')?.addEventListener('click', async () => {
  const profile = localStorage.getItem('selectedProfile') || 'gunluk';
  const drivers = localStorage.getItem('driversEnabled')  || 'false';
  const apps    = JSON.parse(localStorage.getItem('selectedApps') || '[]');
  try {
    const r = await window.go.main.App.RunSetup(profile, drivers, selectedCloud, apps, 'false');
    console.info('[ArchInit]', r);
  } catch (err) {
    console.error('[ArchInit]', err);
  }
});
