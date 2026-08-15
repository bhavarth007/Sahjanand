/* ═══════════════════════════════════════════════════════════════
   job_cards.js — Job Card Voucher CRUD
   ═══════════════════════════════════════════════════════════════ */
;(function() {
'use strict';

const JC_API = (typeof window.API !== 'undefined') ? window.API : (window.location.hostname === 'localhost' ? 'http://localhost:8000' : '');
let jcLoaded = false;
let jcCards = [];
let jcEditingId = null;

// ── Init ──
function initJobCards() {
  if (jcLoaded) return;
  jcLoaded = true;
  loadJobCards();
}

// ── Load all job cards ──
async function loadJobCards() {
  const token = localStorage.getItem('sahjanand_token');
  const grid = document.getElementById('jcCardGrid');
  if (!grid) return;

  try {
    const res = await fetch(`${JC_API}/api/job-cards/`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) { grid.innerHTML = '<div class="jc-empty">No job cards yet. Click "+ New Job Card" to create one.</div>'; return; }
    jcCards = await res.json();
    renderJobCardList();
  } catch (e) {
    console.warn('[job-cards]', e);
    grid.innerHTML = '<div class="jc-empty">No job cards yet.</div>';
  }
}

// ── Render list ──
function renderJobCardList() {
  const grid = document.getElementById('jcCardGrid');
  if (!grid) return;

  if (!jcCards.length) {
    grid.innerHTML = '<div class="jc-empty">No job cards yet. Click "+ New Job Card" to create one.</div>';
    return;
  }

  grid.innerHTML = jcCards.map((c, i) => {
    const title = `${c.job_name || 'Job'} — J.CARD NO.: ${c.j_card_no || '—'}`;
    const sub = [c.p_name, c.quality, c.design_no].filter(Boolean).join(' | ');
    const date = c.jc_date || c.start_date || '';
    return `
      <div class="jc-row" onclick="openJobCardDetail(${c.id})">
        <div class="jc-row-num">${i + 1}</div>
        <div class="jc-row-img">
          ${c.image_url ? `<img src="${esc(c.image_url)}" alt="JC" />` : '<i class="fa-solid fa-image" style="color:#ccc;font-size:1.2rem;"></i>'}
        </div>
        <div class="jc-row-info">
          <div class="jc-row-title">${esc(title)}</div>
          <div class="jc-row-sub">${esc(sub)}</div>
          ${date ? `<div class="jc-row-date"><i class="fa-regular fa-calendar"></i> ${esc(date)}</div>` : ''}
        </div>
        <div class="jc-row-actions">
          <button class="jc-btn-edit" onclick="event.stopPropagation();editJobCard(${c.id})" title="Edit"><i class="fa-solid fa-pen"></i></button>
          <button class="jc-btn-delete" onclick="event.stopPropagation();deleteJobCard(${c.id})" title="Delete"><i class="fa-solid fa-trash"></i></button>
        </div>
      </div>
    `;
  }).join('');
}

// ── Open form for new ──
function openNewJobCard() {
  jcEditingId = null;
  clearJobCardForm();
  document.getElementById('jcFormPanel').style.display = 'block';
  document.getElementById('jcFormTitle').textContent = 'New Job Card Voucher';
}

// ── Open form for edit ──
function editJobCard(id) {
  const card = jcCards.find(c => c.id === id);
  if (!card) return;
  jcEditingId = id;
  document.getElementById('jcFormPanel').style.display = 'block';
  document.getElementById('jcFormTitle').textContent = 'Edit Job Card Voucher';

  // Fill form
  const fields = ['job_name','j_card_no','p_name','so_no','quality','design_no','total_card','g_pick','jc_date','j_ord_no','repeat_mtr','repeat_pcs','total_pcs','weight_per_pcs','start_date','end_date','op_name','remark','supervisor_sign'];
  fields.forEach(f => {
    const el = document.getElementById('jc_' + f);
    if (el) el.value = card[f] || '';
  });
  document.getElementById('jcImageUrl').value = card.image_url || '';
  const preview = document.getElementById('jcImagePreview');
  if (card.image_url) {
    preview.innerHTML = `<img src="${esc(card.image_url)}" style="max-height:80px;border-radius:8px;" />`;
  } else {
    preview.innerHTML = '';
  }
}

// ── View detail ──
function openJobCardDetail(id) {
  editJobCard(id);
}

// ── Close form ──
function closeJobCardForm() {
  document.getElementById('jcFormPanel').style.display = 'none';
  jcEditingId = null;
}

// ── Clear form ──
function clearJobCardForm() {
  const fields = ['job_name','j_card_no','p_name','so_no','quality','design_no','total_card','g_pick','jc_date','j_ord_no','repeat_mtr','repeat_pcs','total_pcs','weight_per_pcs','start_date','end_date','op_name','remark','supervisor_sign'];
  fields.forEach(f => {
    const el = document.getElementById('jc_' + f);
    if (el) el.value = '';
  });
  document.getElementById('jcImageUrl').value = '';
  document.getElementById('jcImagePreview').innerHTML = '';
}

// ── Upload image ──
async function uploadJobCardImage(input) {
  const file = input.files[0];
  if (!file) return;
  const token = localStorage.getItem('sahjanand_token');
  const formData = new FormData();
  formData.append('file', file);

  const preview = document.getElementById('jcImagePreview');
  preview.innerHTML = '<span style="color:#888;font-size:.8rem;">Uploading...</span>';

  try {
    const res = await fetch(`${JC_API}/api/chat/upload`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: formData,
    });
    if (res.ok) {
      const data = await res.json();
      const url = data.url || data.media_url || '';
      document.getElementById('jcImageUrl').value = url;
      preview.innerHTML = `<img src="${esc(url)}" style="max-height:80px;border-radius:8px;" /> <span style="color:green;font-size:.75rem;">Uploaded</span>`;
    } else {
      preview.innerHTML = '<span style="color:red;font-size:.8rem;">Upload failed</span>';
    }
  } catch {
    preview.innerHTML = '<span style="color:red;font-size:.8rem;">Upload failed</span>';
  }
  input.value = '';
}

// ── Save job card ──
async function saveJobCard() {
  const imageUrl = document.getElementById('jcImageUrl').value;
  if (!imageUrl) {
    alert('Please upload an image first. Image is required.');
    return;
  }

  const token = localStorage.getItem('sahjanand_token');
  const fields = ['job_name','j_card_no','p_name','so_no','quality','design_no','total_card','g_pick','jc_date','j_ord_no','repeat_mtr','repeat_pcs','total_pcs','weight_per_pcs','start_date','end_date','op_name','remark','supervisor_sign'];
  const body = { image_url: imageUrl };
  fields.forEach(f => {
    const el = document.getElementById('jc_' + f);
    if (el && el.value.trim()) body[f] = el.value.trim();
  });

  const url = jcEditingId ? `${JC_API}/api/job-cards/${jcEditingId}` : `${JC_API}/api/job-cards/`;
  const method = jcEditingId ? 'PATCH' : 'POST';

  try {
    const res = await fetch(url, {
      method,
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      alert(err.detail || 'Failed to save job card.');
      return;
    }
    closeJobCardForm();
    jcLoaded = false;
    initJobCards();
  } catch {
    alert('Network error. Please try again.');
  }
}

// ── Delete ──
async function deleteJobCard(id) {
  if (!confirm('Delete this job card?')) return;
  const token = localStorage.getItem('sahjanand_token');
  try {
    await fetch(`${JC_API}/api/job-cards/${id}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token}` },
    });
    jcLoaded = false;
    initJobCards();
  } catch {}
}

function esc(s) { const d = document.createElement('div'); d.textContent = s || ''; return d.innerHTML; }

// ── Expose ──
window.initJobCards = initJobCards;
window.openNewJobCard = openNewJobCard;
window.editJobCard = editJobCard;
window.openJobCardDetail = openJobCardDetail;
window.closeJobCardForm = closeJobCardForm;
window.uploadJobCardImage = uploadJobCardImage;
window.saveJobCard = saveJobCard;
window.deleteJobCard = deleteJobCard;

})();
