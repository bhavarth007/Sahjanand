/* ═══════════════════════════════════════════════════════════════
   job_cards.js — Job Card Voucher CRUD
   ═══════════════════════════════════════════════════════════════ */
;(function() {
'use strict';

const JC_API = (typeof window.API !== 'undefined') ? window.API : (window.location.hostname === 'localhost' ? 'http://localhost:8000' : '');
let jcLoaded = false;
let jcCards = [];
let jcEditingId = null;

// Fixed CMP TYPE rows for Program Matching
const CMP_TYPES = ['BEAM & COLOR', 'FDR-1', 'FDR-2', 'FDR-3', 'FDR-4', 'FDR-5', 'FDR-6', 'FDR-7', 'FDR-8'];

// Simple text fields to save
const JC_FIELDS = ['job_name','j_card_no','jc_date','quality','design_no','g_pick','repeat_mtr','repeat_pcs','start_date','end_date','op_name','remark','supervisor_sign'];

function initJobCards() {
  if (jcLoaded) return;
  jcLoaded = true;
  loadJobCards();
}

async function loadJobCards() {
  const token = localStorage.getItem('sahjanand_token');
  const grid = document.getElementById('jcCardGrid');
  if (!grid) return;
  try {
    const res = await fetch(`${JC_API}/api/job-cards/`, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) { grid.innerHTML = '<div class="jc-empty">No job cards yet. Click "+ New Job Card" to create one.</div>'; return; }
    jcCards = await res.json();
    renderJobCardList();
  } catch (e) {
    grid.innerHTML = '<div class="jc-empty">No job cards yet.</div>';
  }
}

function renderJobCardList() {
  const grid = document.getElementById('jcCardGrid');
  if (!grid) return;
  if (!jcCards.length) {
    grid.innerHTML = '<div class="jc-empty">No job cards yet. Click "+ New Job Card" to create one.</div>';
    return;
  }
  grid.innerHTML = jcCards.map((c, i) => {
    const title = `${c.job_name || 'Job'} — J.CARD NO.: ${c.j_card_no || '—'}`;
    const sub = [c.quality, c.design_no].filter(Boolean).join(' | ');
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
      </div>`;
  }).join('');
}

// ── Render Program Matching table ──
function renderProgramTable(data) {
  const body = document.getElementById('jcProgramBody');
  if (!body) return;
  const rows = data || CMP_TYPES.map(t => ({ cmp_type: t, color_name: '', yarn_beam_name: '', weight_mtr: '' }));
  body.innerHTML = rows.map((r, i) => `
    <tr>
      <td class="jc-td-fixed">${esc(r.cmp_type)}</td>
      <td><input type="text" class="jc-cell" data-pm="${i}" data-k="color_name" value="${esc(r.color_name)}" /></td>
      <td><input type="text" class="jc-cell" data-pm="${i}" data-k="yarn_beam_name" value="${esc(r.yarn_beam_name)}" /></td>
      <td><input type="text" class="jc-cell" data-pm="${i}" data-k="weight_mtr" value="${esc(r.weight_mtr)}" /></td>
    </tr>`).join('');
}

// ── Render Taka table ──
function renderTakaTable(data) {
  const body = document.getElementById('jcTakaBody');
  if (!body) return;
  let rows = data && data.length ? data : [emptyTaka(), emptyTaka(), emptyTaka()];
  body.innerHTML = rows.map((r, i) => takaRowHtml(r, i)).join('');
}

function emptyTaka() { return { taka_no:'', cut:'', pcs:'', mtr:'', weight:'', color:'', remark:'' }; }

function takaRowHtml(r, i) {
  return `
    <tr data-taka-row="${i}">
      <td><input type="text" class="jc-cell" data-tk="${i}" data-k="taka_no" value="${esc(r.taka_no)}" /></td>
      <td><input type="text" class="jc-cell" data-tk="${i}" data-k="cut" value="${esc(r.cut)}" /></td>
      <td><input type="text" class="jc-cell" data-tk="${i}" data-k="pcs" value="${esc(r.pcs)}" /></td>
      <td><input type="text" class="jc-cell" data-tk="${i}" data-k="mtr" value="${esc(r.mtr)}" /></td>
      <td><input type="text" class="jc-cell" data-tk="${i}" data-k="weight" value="${esc(r.weight)}" /></td>
      <td><input type="text" class="jc-cell" data-tk="${i}" data-k="color" value="${esc(r.color)}" /></td>
      <td><input type="text" class="jc-cell" data-tk="${i}" data-k="remark" value="${esc(r.remark)}" /></td>
      <td><button class="jc-btn-delete" style="width:26px;height:26px;" onclick="removeTakaRow(this)" title="Remove"><i class="fa-solid fa-xmark"></i></button></td>
    </tr>`;
}

function addTakaRow() {
  const body = document.getElementById('jcTakaBody');
  if (!body) return;
  const i = body.querySelectorAll('tr').length;
  body.insertAdjacentHTML('beforeend', takaRowHtml(emptyTaka(), i));
}

function removeTakaRow(btn) {
  const tr = btn.closest('tr');
  if (tr) tr.remove();
}

// ── Collect table data ──
function collectProgramData() {
  const rows = [];
  document.querySelectorAll('#jcProgramBody tr').forEach((tr, i) => {
    const cmp = tr.querySelector('.jc-td-fixed')?.textContent || CMP_TYPES[i] || '';
    const get = (k) => tr.querySelector(`[data-k="${k}"]`)?.value || '';
    rows.push({ cmp_type: cmp, color_name: get('color_name'), yarn_beam_name: get('yarn_beam_name'), weight_mtr: get('weight_mtr') });
  });
  return rows;
}

function collectTakaData() {
  const rows = [];
  document.querySelectorAll('#jcTakaBody tr').forEach((tr) => {
    const get = (k) => tr.querySelector(`[data-k="${k}"]`)?.value || '';
    const row = { taka_no: get('taka_no'), cut: get('cut'), pcs: get('pcs'), mtr: get('mtr'), weight: get('weight'), color: get('color'), remark: get('remark') };
    // Only include non-empty rows
    if (Object.values(row).some(v => v.trim())) rows.push(row);
  });
  return rows;
}

async function getNextJCardNo() {
  const token = localStorage.getItem('sahjanand_token');
  try {
    const res = await fetch(`${JC_API}/api/job-cards/next-number`, { headers: { Authorization: `Bearer ${token}` } });
    if (res.ok) {
      const data = await res.json();
      return data.next_number || '1';
    }
  } catch (e) {}
  // Fallback: compute from loaded cards
  if (!jcCards.length) return '1';
  let max = 0;
  jcCards.forEach(c => {
    const num = parseInt(c.j_card_no, 10);
    if (!isNaN(num) && num > max) max = num;
  });
  return String(max + 1);
}

async function openNewJobCard() {
  jcEditingId = null;
  clearJobCardForm();
  renderProgramTable(null);
  renderTakaTable(null);
  // Auto-generate J.Card No from backend
  const jcNoEl = document.getElementById('jc_j_card_no');
  if (jcNoEl) {
    jcNoEl.value = await getNextJCardNo();
    jcNoEl.readOnly = true;
  }
  // Set today's date as default
  const today = new Date().toISOString().split('T')[0];
  const dateEl = document.getElementById('jc_jc_date');
  if (dateEl && !dateEl.value) dateEl.value = today;
  document.getElementById('jcFormPanel').style.display = 'block';
  document.getElementById('jcFormTitle').textContent = 'New Job Card Voucher';
}

function editJobCard(id) {
  const card = jcCards.find(c => c.id === id);
  if (!card) return;
  jcEditingId = id;
  document.getElementById('jcFormPanel').style.display = 'block';
  document.getElementById('jcFormTitle').textContent = 'Edit Job Card Voucher';

  JC_FIELDS.forEach(f => {
    const el = document.getElementById('jc_' + f);
    if (el) el.value = card[f] || '';
  });
  // Make J.Card No readonly
  const jcNoEl = document.getElementById('jc_j_card_no');
  if (jcNoEl) jcNoEl.readOnly = true;
  document.getElementById('jcImageUrl').value = card.image_url || '';
  const preview = document.getElementById('jcImagePreview');
  preview.innerHTML = card.image_url ? `<img src="${esc(card.image_url)}" style="max-height:80px;border-radius:8px;" />` : '';

  // Parse and render tables
  let pm = null, tk = null;
  try { pm = card.program_matching ? JSON.parse(card.program_matching) : null; } catch {}
  try { tk = card.taka_rows ? JSON.parse(card.taka_rows) : null; } catch {}
  renderProgramTable(pm);
  renderTakaTable(tk);
}

function openJobCardDetail(id) { editJobCard(id); }

function closeJobCardForm() {
  document.getElementById('jcFormPanel').style.display = 'none';
  jcEditingId = null;
}

function clearJobCardForm() {
  JC_FIELDS.forEach(f => {
    const el = document.getElementById('jc_' + f);
    if (el) el.value = '';
  });
  document.getElementById('jcImageUrl').value = '';
  document.getElementById('jcImagePreview').innerHTML = '';
}

async function uploadJobCardImage(input) {
  const file = input.files[0];
  if (!file) return;
  const token = localStorage.getItem('sahjanand_token');
  const formData = new FormData();
  formData.append('file', file);
  const preview = document.getElementById('jcImagePreview');
  preview.innerHTML = '<span style="color:#888;font-size:.8rem;">Uploading...</span>';
  try {
    const res = await fetch(`${JC_API}/api/chat/upload`, { method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: formData });
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

async function saveJobCard() {
  const imageUrl = document.getElementById('jcImageUrl').value;
  if (!imageUrl) { alert('Please upload an image first. Image is required.'); return; }

  const token = localStorage.getItem('sahjanand_token');
  const body = { image_url: imageUrl };
  JC_FIELDS.forEach(f => {
    const el = document.getElementById('jc_' + f);
    if (el && el.value.trim()) body[f] = el.value.trim();
  });
  body.program_matching = JSON.stringify(collectProgramData());
  body.taka_rows = JSON.stringify(collectTakaData());

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

async function deleteJobCard(id) {
  if (!confirm('Delete this job card?')) return;
  const token = localStorage.getItem('sahjanand_token');
  try {
    await fetch(`${JC_API}/api/job-cards/${id}`, { method: 'DELETE', headers: { Authorization: `Bearer ${token}` } });
    jcLoaded = false;
    initJobCards();
  } catch {}
}

function esc(s) { const d = document.createElement('div'); d.textContent = s || ''; return d.innerHTML; }

window.initJobCards = initJobCards;
window.openNewJobCard = openNewJobCard;
window.editJobCard = editJobCard;
window.openJobCardDetail = openJobCardDetail;
window.closeJobCardForm = closeJobCardForm;
window.uploadJobCardImage = uploadJobCardImage;
window.saveJobCard = saveJobCard;
window.deleteJobCard = deleteJobCard;
window.addTakaRow = addTakaRow;
window.removeTakaRow = removeTakaRow;

})();
