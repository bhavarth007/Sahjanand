/* ═══════════════════════════════════════════════════════════════
   job_cards.js — Job Card Voucher CRUD + Workflow Management
   ═══════════════════════════════════════════════════════════════ */
;(function() {
'use strict';

const JC_API = (typeof window.API !== 'undefined') ? window.API : (window.location.hostname === 'localhost' ? 'http://localhost:8000' : '');
let jcLoaded = false;
let jcCards = [];
let jcEditingId = null;
let jcCurrentTab = 'ALL';
let jcCurrentPage = 1;
let jcTotalPages = 1;
let jcProcessing = false; // prevent double-clicks
let jcSearchTerm = '';
let jcStatusFilter = 'ALL'; // ALL, COMPLETED, PENDING (for ALL tab only)

// Fixed CMP TYPE rows for Program Matching
const CMP_TYPES = ['BEAM & COLOR', 'FDR-1', 'FDR-2', 'FDR-3', 'FDR-4', 'FDR-5', 'FDR-6', 'FDR-7', 'FDR-8'];

// Simple text fields to save
const JC_FIELDS = ['job_name','j_card_no','jc_date','quality','design_no','g_pick','repeat_mtr','repeat_pcs','start_date','end_date','op_name','remark','supervisor_sign'];

// Tab labels for display
const TAB_LABELS = {
  'ALL': 'All Job Cards',
  'SUPERVISOR_CLEARANCE': 'Supervisor Clearance',
  'MANDING_DEPARTMENT': 'Manding Department',
  'BUTTA_CUTTING': 'Butta Cutting',
  'MILL': 'Mill',
  'BORDER': 'Border',
  'FINAL': 'Final Job Cards',
};

// ═══════════════════════════════════════════════════════════════
// INITIALIZATION
// ═══════════════════════════════════════════════════════════════
function initJobCards() {
  if (jcLoaded) return;
  jcLoaded = true;
  switchWorkflowTab('ALL');
}

// ═══════════════════════════════════════════════════════════════
// WORKFLOW TAB SWITCHING
// ═══════════════════════════════════════════════════════════════
function switchWorkflowTab(tab) {
  jcCurrentTab = tab;
  jcCurrentPage = 1;
  jcSearchTerm = '';
  const searchInput = document.getElementById('jcSearchInput');
  if (searchInput) searchInput.value = '';

  // Update active tab styling
  document.querySelectorAll('.jc-wf-tab').forEach(t => t.classList.remove('active'));
  const activeBtn = document.querySelector(`.jc-wf-tab[data-wf="${tab}"]`);
  if (activeBtn) activeBtn.classList.add('active');

  // Update title
  const titleEl = document.getElementById('jcTabTitle');
  if (titleEl) titleEl.textContent = TAB_LABELS[tab] || tab;

  // Show/hide New button (only on ALL tab)
  const newBtn = document.getElementById('jcNewBtn');
  if (newBtn) newBtn.style.display = (tab === 'ALL') ? '' : 'none';

  // Show/hide status sub-filters (only on ALL tab)
  const statusFilters = document.getElementById('jcStatusFilters');
  if (statusFilters) statusFilters.style.display = (tab === 'ALL') ? 'flex' : 'none';

  // Reset status filter when switching tabs
  if (tab !== 'ALL') jcStatusFilter = 'ALL';

  // Hide forms
  closeJobCardForm();
  closeBorderForm();
  closeCancelForm();
  closeReadOnlyView();

  // Load data
  loadJobCards();
}

// ═══════════════════════════════════════════════════════════════
// DATA LOADING (with pagination)
// ═══════════════════════════════════════════════════════════════
async function loadJobCards() {
  const token = localStorage.getItem('sahjanand_token');
  const grid = document.getElementById('jcCardGrid');
  if (!grid) return;

  // Determine status filter based on tab
  let statusFilter = '';
  if (jcCurrentTab === 'ALL') {
    // Apply sub-filter
    if (jcStatusFilter === 'COMPLETED') {
      statusFilter = 'COMPLETED';
    } else if (jcStatusFilter === 'PENDING') {
      statusFilter = 'NEW,CANCELLED';
    } else {
      statusFilter = ''; // All records
    }
  } else {
    statusFilter = jcCurrentTab;
  }

  try {
    let url = `${JC_API}/api/job-cards/?page=${jcCurrentPage}&page_size=5`;
    if (statusFilter) url += `&status=${statusFilter}`;
    if (jcSearchTerm) url += `&search=${encodeURIComponent(jcSearchTerm)}`;
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) {
      grid.innerHTML = '<div class="jc-empty">Failed to load job cards.</div>';
      return;
    }
    const data = await res.json();
    jcCards = data.items || [];
    jcTotalPages = data.total_pages || 1;
    renderJobCardList();
    renderPagination(data.total, data.page, data.total_pages);
  } catch (e) {
    grid.innerHTML = '<div class="jc-empty">Error loading job cards.</div>';
  }
}

// ═══════════════════════════════════════════════════════════════
// RENDER JOB CARD LIST (per tab)
// ═══════════════════════════════════════════════════════════════
function renderJobCardList() {
  const grid = document.getElementById('jcCardGrid');
  if (!grid) return;
  if (!jcCards.length) {
    const emptyMsg = jcCurrentTab === 'ALL'
      ? 'No job cards yet. Click "+ New Job Card" to create one.'
      : `No job cards in ${TAB_LABELS[jcCurrentTab] || jcCurrentTab}.`;
    grid.innerHTML = `<div class="jc-empty">${emptyMsg}</div>`;
    return;
  }

  grid.innerHTML = jcCards.map(c => {
    const title = jcCurrentTab === 'FINAL'
      ? `${c.design_no || '—'} — ${c.quality || '—'} — J.CARD NO.: ${c.j_card_no || '—'}`
      : `${c.job_name || 'Job'} — J.CARD NO.: ${c.j_card_no || '—'}`;
    const sub = jcCurrentTab === 'FINAL'
      ? [c.job_name].filter(Boolean).join(' | ')
      : [c.quality, c.design_no].filter(Boolean).join(' | ');
    const date = c.jc_date || c.start_date || '';
    const isCancelled = c.workflow_status === 'CANCELLED';

    let actions = '';
    if (jcCurrentTab === 'ALL') {
      if (c.workflow_status === 'NEW' || c.workflow_status === 'CANCELLED') {
        actions = `
          <button class="jc-btn-icon jc-btn-edit" onclick="event.stopPropagation();editJobCard(${c.id})" title="Edit"><i class="fa-solid fa-pen"></i></button>
          <button class="jc-btn-icon jc-btn-delete" onclick="event.stopPropagation();deleteJobCard(${c.id})" title="Delete"><i class="fa-solid fa-trash"></i></button>
          <button class="jc-btn-accept" onclick="event.stopPropagation();acceptJobCard(${c.id})" title="Accept">Accept</button>`;
      } else {
        // Cards already in workflow — just show Open button
        actions = `<button class="jc-btn-confirm" onclick="event.stopPropagation();openJobCardDetail(${c.id})" title="View Details">Open</button>`;
      }
    } else if (jcCurrentTab === 'SUPERVISOR_CLEARANCE') {
      actions = `
        <button class="jc-btn-confirm" onclick="event.stopPropagation();confirmTransition(${c.id},'MANDING_DEPARTMENT')">Confirm</button>
        <button class="jc-btn-cancel" onclick="event.stopPropagation();openCancelForm(${c.id})">Cancel</button>`;
    } else if (jcCurrentTab === 'MANDING_DEPARTMENT') {
      actions = `<button class="jc-btn-confirm" onclick="event.stopPropagation();confirmTransition(${c.id},'BUTTA_CUTTING')">Confirm</button>`;
    } else if (jcCurrentTab === 'BUTTA_CUTTING') {
      actions = `<button class="jc-btn-confirm" onclick="event.stopPropagation();confirmTransition(${c.id},'MILL')">Confirm</button>`;
    } else if (jcCurrentTab === 'MILL') {
      actions = `<button class="jc-btn-confirm" onclick="event.stopPropagation();confirmTransition(${c.id},'BORDER')">Confirm</button>`;
    } else if (jcCurrentTab === 'BORDER') {
      actions = `<button class="jc-btn-confirm" onclick="event.stopPropagation();openBorderForm(${c.id})">Open Form</button>`;
    } else if (jcCurrentTab === 'FINAL') {
      actions = `
        <button class="jc-btn-confirm" onclick="event.stopPropagation();openJobCardDetail(${c.id})" title="View Details">Open</button>
        <button class="jc-btn-icon jc-btn-delete" onclick="event.stopPropagation();deleteJobCard(${c.id})" title="Delete"><i class="fa-solid fa-trash"></i></button>
        <button class="jc-btn-confirm" onclick="event.stopPropagation();confirmTransition(${c.id},'COMPLETED')">Final Confirm</button>`;
    }

    // Cancellation info for ALL tab
    let cancelInfo = '';
    if (isCancelled && jcCurrentTab === 'ALL') {
      cancelInfo = `<div class="jc-cancel-badge"><i class="fa-solid fa-ban"></i> Cancelled${c.cancel_reason ? ': ' + esc(c.cancel_reason.substring(0, 60)) : ''}</div>`;
    }

    // Border info for FINAL tab
    let borderInfo = '';
    if (jcCurrentTab === 'FINAL' && c.border_job_m) {
      borderInfo = `<div class="jc-border-info">Job:${c.border_job_m}M | Work:${c.border_work_m}M | Lapet:${c.border_lapet_m}M | Cut:${c.border_total_cut_m}M</div>`;
    }

    // Show confirmed_by info
    let confirmedInfo = '';
    if (c.confirmed_by_name && (jcCurrentTab === 'FINAL' || jcCurrentTab === 'ALL')) {
      confirmedInfo = `<div class="jc-confirmed-badge"><i class="fa-solid fa-circle-check"></i> Confirmed by: ${esc(c.confirmed_by_name)}</div>`;
    }

    // Show workflow status badge in ALL tab
    let statusBadge = '';
    if (jcCurrentTab === 'ALL' && c.workflow_status !== 'NEW' && c.workflow_status !== 'CANCELLED') {
      const stageLabels = {SUPERVISOR_CLEARANCE:'Supervisor',MANDING_DEPARTMENT:'Manding',BUTTA_CUTTING:'Butta Cutting',MILL:'Mill',BORDER:'Border',FINAL:'Final',COMPLETED:'Completed'};
      statusBadge = `<span class="jc-status-badge jc-status-${c.workflow_status.toLowerCase()}">${stageLabels[c.workflow_status] || c.workflow_status}</span>`;
    }

    return `
      <div class="jc-row ${isCancelled ? 'jc-row-cancelled' : ''}" ${jcCurrentTab === 'BORDER' ? `onclick="openBorderForm(${c.id})"` : ''}>
        <div class="jc-row-img" ${c.image_url ? `onclick="event.stopPropagation();openImageModal('${esc(c.image_url)}')" style="cursor:pointer;"` : ''}>
          ${c.image_url ? `<img src="${esc(c.image_url)}" alt="JC" />` : '<i class="fa-solid fa-image" style="color:#ccc;font-size:1rem;"></i>'}
        </div>
        <div class="jc-row-info">
          <div class="jc-row-title">${esc(title)}</div>
          <div class="jc-row-sub">${esc(sub)}</div>
          ${date ? `<div class="jc-row-date"><i class="fa-regular fa-calendar"></i> ${esc(date)}</div>` : ''}
          ${statusBadge}
          ${cancelInfo}
          ${confirmedInfo}
          ${borderInfo}
        </div>
        <div class="jc-row-actions">${actions}</div>
      </div>`;
  }).join('');
}

// ═══════════════════════════════════════════════════════════════
// PAGINATION
// ═══════════════════════════════════════════════════════════════
function renderPagination(total, page, totalPages) {
  const el = document.getElementById('jcPagination');
  if (!el) return;
  if (totalPages <= 1) { el.style.display = 'none'; return; }
  el.style.display = 'flex';

  let html = '';
  // Previous
  html += `<button class="jc-page-btn" ${page <= 1 ? 'disabled' : ''} onclick="goToPage(${page - 1})">‹</button>`;
  // Page numbers
  for (let i = 1; i <= totalPages; i++) {
    if (totalPages > 7 && i > 3 && i < totalPages - 2 && Math.abs(i - page) > 1) {
      if (i === 4 || i === totalPages - 3) html += '<span class="jc-page-dots">…</span>';
      continue;
    }
    html += `<button class="jc-page-btn ${i === page ? 'active' : ''}" onclick="goToPage(${i})">${i}</button>`;
  }
  // Next
  html += `<button class="jc-page-btn" ${page >= totalPages ? 'disabled' : ''} onclick="goToPage(${page + 1})">›</button>`;
  el.innerHTML = html;
}

function goToPage(p) {
  if (p < 1 || p > jcTotalPages) return;
  jcCurrentPage = p;
  loadJobCards();
}

// ═══════════════════════════════════════════════════════════════
// WORKFLOW ACTIONS
// ═══════════════════════════════════════════════════════════════

// Accept (from ALL JOB CARDS → SUPERVISOR_CLEARANCE)
async function acceptJobCard(id) {
  if (jcProcessing) return;
  if (!confirm('Are you sure you want to accept this Job Card?')) return;
  jcProcessing = true;
  try {
    const token = localStorage.getItem('sahjanand_token');
    const res = await fetch(`${JC_API}/api/job-cards/${id}/transition`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ target_status: 'SUPERVISOR_CLEARANCE' }),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      alert(err.detail || 'Failed to accept job card.');
      return;
    }
    loadJobCards();
  } catch (e) {
    alert('Network error. Please try again.');
  } finally {
    jcProcessing = false;
  }
}

// Generic confirm transition
async function confirmTransition(id, targetStatus) {
  if (jcProcessing) return;
  const label = TAB_LABELS[targetStatus] || targetStatus;
  const msg = targetStatus === 'COMPLETED'
    ? 'Are you sure you want to finalize this Job Card? This cannot be undone.'
    : `Confirm moving this Job Card to ${label}?`;
  if (!confirm(msg)) return;
  jcProcessing = true;
  try {
    const token = localStorage.getItem('sahjanand_token');
    const res = await fetch(`${JC_API}/api/job-cards/${id}/transition`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ target_status: targetStatus }),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      alert(err.detail || 'Failed to transition job card.');
      return;
    }
    loadJobCards();
  } catch (e) {
    alert('Network error. Please try again.');
  } finally {
    jcProcessing = false;
  }
}

// ═══════════════════════════════════════════════════════════════
// CANCELLATION
// ═══════════════════════════════════════════════════════════════
function openCancelForm(id) {
  document.getElementById('jcCancelCardId').value = id;
  document.getElementById('jcCancelReason').value = '';
  document.getElementById('jcCancelPanel').style.display = 'block';
  document.getElementById('jcCancelReason').focus();
}

function closeCancelForm() {
  document.getElementById('jcCancelPanel').style.display = 'none';
  document.getElementById('jcCancelCardId').value = '';
  document.getElementById('jcCancelReason').value = '';
}

async function confirmCancellation() {
  if (jcProcessing) return;
  const id = document.getElementById('jcCancelCardId').value;
  const reason = document.getElementById('jcCancelReason').value.trim();
  if (!reason) { alert('Please enter a cancellation reason.'); return; }
  if (!confirm('Are you sure you want to cancel this Job Card?')) return;

  jcProcessing = true;
  const btn = document.getElementById('jcCancelConfirmBtn');
  if (btn) btn.disabled = true;
  try {
    const token = localStorage.getItem('sahjanand_token');
    const res = await fetch(`${JC_API}/api/job-cards/${id}/cancel`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ reason }),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      alert(err.detail || 'Failed to cancel job card.');
      return;
    }
    closeCancelForm();
    loadJobCards();
  } catch (e) {
    alert('Network error. Please try again.');
  } finally {
    jcProcessing = false;
    if (btn) btn.disabled = false;
  }
}

// ═══════════════════════════════════════════════════════════════
// BORDER FORM
// ═══════════════════════════════════════════════════════════════
function openBorderForm(id) {
  const card = jcCards.find(c => c.id === id);
  if (!card) return;

  // Fill read-only info
  document.getElementById('jcBorderJobName').textContent = card.job_name || '—';
  document.getElementById('jcBorderCardNo').textContent = card.j_card_no || '—';
  document.getElementById('jcBorderDate').textContent = card.jc_date || '—';
  document.getElementById('jcBorderDesign').textContent = card.design_no || '—';

  // Clear editable fields
  ['job_m','work_m','lapet_m','blause_m','total_cut_m','rs_inch'].forEach(f => {
    const el = document.getElementById('jcBorder_' + f);
    if (el) el.value = '';
  });
  document.getElementById('jcBorder_description').value = '';
  document.getElementById('jcBorderCardId').value = id;
  document.getElementById('jcBorderPanel').style.display = 'block';
}

function closeBorderForm() {
  document.getElementById('jcBorderPanel').style.display = 'none';
  document.getElementById('jcBorderCardId').value = '';
}

async function confirmBorderForm() {
  if (jcProcessing) return;
  const id = document.getElementById('jcBorderCardId').value;
  if (!id) return;

  // Collect & validate
  const fields = ['job_m','work_m','lapet_m','blause_m','total_cut_m','rs_inch'];
  const body = {};
  for (const f of fields) {
    const el = document.getElementById('jcBorder_' + f);
    const val = el ? el.value.trim() : '';
    if (!val) { alert('Please fill all required fields.'); el && el.focus(); return; }
    if (isNaN(parseFloat(val))) { alert(`"${el.previousElementSibling?.textContent || f}" must be a valid number.`); el.focus(); return; }
    body['border_' + f] = val;
  }
  const desc = document.getElementById('jcBorder_description').value.trim();
  if (!desc) { alert('Please fill the Description field.'); document.getElementById('jcBorder_description').focus(); return; }
  body.border_description = desc;

  if (!confirm('Are you sure you want to complete Border processing for this Job Card?')) return;

  jcProcessing = true;
  const btn = document.getElementById('jcBorderConfirmBtn');
  if (btn) btn.disabled = true;
  try {
    const token = localStorage.getItem('sahjanand_token');
    const res = await fetch(`${JC_API}/api/job-cards/${id}/border`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      alert(err.detail || 'Failed to save border data.');
      return;
    }
    closeBorderForm();
    loadJobCards();
  } catch (e) {
    alert('Network error. Please try again.');
  } finally {
    jcProcessing = false;
    if (btn) btn.disabled = false;
  }
}

// ═══════════════════════════════════════════════════════════════
// JOB CARD CRUD (Create, Edit, Delete)
// ═══════════════════════════════════════════════════════════════

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
  return '1';
}

async function openNewJobCard() {
  jcEditingId = null;
  clearJobCardForm();
  renderProgramTable(null);
  renderTakaTable(null);
  const jcNoEl = document.getElementById('jc_j_card_no');
  if (jcNoEl) {
    jcNoEl.value = await getNextJCardNo();
    jcNoEl.readOnly = true;
  }
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
  const jcNoEl = document.getElementById('jc_j_card_no');
  if (jcNoEl) jcNoEl.readOnly = true;
  document.getElementById('jcImageUrl').value = card.image_url || '';
  const preview = document.getElementById('jcImagePreview');
  preview.innerHTML = card.image_url ? `<img src="${esc(card.image_url)}" style="max-height:80px;border-radius:8px;" />` : '';

  let pm = null, tk = null;
  try { pm = card.program_matching ? JSON.parse(card.program_matching) : null; } catch {}
  try { tk = card.taka_rows ? JSON.parse(card.taka_rows) : null; } catch {}
  renderProgramTable(pm);
  renderTakaTable(tk);
}

function openJobCardDetail(id) { openReadOnlyView(id); }

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
    if (res.ok) {
      closeJobCardForm();
      loadJobCards();
    } else {
      const err = await res.json().catch(() => ({}));
      alert(err.detail || 'Failed to save job card.');
    }
  } catch (e) {
    alert('Network error. Please try again.');
  }
}

async function deleteJobCard(id) {
  if (!confirm('Are you sure you want to delete this Job Card? This cannot be undone.')) return;
  const token = localStorage.getItem('sahjanand_token');
  try {
    const res = await fetch(`${JC_API}/api/job-cards/${id}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token}` },
    });
    if (res.ok) {
      loadJobCards();
    } else {
      const err = await res.json().catch(() => ({}));
      alert(err.detail || 'Failed to delete job card.');
    }
  } catch {
    alert('Network error.');
  }
}

// ═══════════════════════════════════════════════════════════════
// SEARCH & STATUS FILTER
// ═══════════════════════════════════════════════════════════════
let _searchDebounce = null;
function onJcSearch() {
  clearTimeout(_searchDebounce);
  _searchDebounce = setTimeout(() => {
    jcSearchTerm = (document.getElementById('jcSearchInput')?.value || '').trim();
    jcCurrentPage = 1;
    loadJobCards();
  }, 350);
}

function setStatusFilter(filter) {
  jcStatusFilter = filter;
  jcCurrentPage = 1;
  document.querySelectorAll('.jc-sf-btn').forEach(b => b.classList.remove('active'));
  const btn = document.querySelector(`.jc-sf-btn[data-sf="${filter}"]`);
  if (btn) btn.classList.add('active');
  loadJobCards();
}

// ═══════════════════════════════════════════════════════════════
// READ-ONLY VIEW (for Open button in FINAL/ALL/COMPLETED)
// ═══════════════════════════════════════════════════════════════
function openReadOnlyView(id) {
  const card = jcCards.find(c => c.id === id);
  if (!card) return;

  // Reuse the form panel but make it read-only
  jcEditingId = null;
  document.getElementById('jcFormPanel').style.display = 'block';
  document.getElementById('jcFormTitle').textContent = 'Job Card Details (Read Only)';

  JC_FIELDS.forEach(f => {
    const el = document.getElementById('jc_' + f);
    if (el) { el.value = card[f] || ''; el.readOnly = true; el.disabled = true; }
  });

  document.getElementById('jcImageUrl').value = card.image_url || '';
  const preview = document.getElementById('jcImagePreview');
  preview.innerHTML = card.image_url
    ? `<img src="${esc(card.image_url)}" style="max-height:80px;border-radius:8px;cursor:pointer;" onclick="openImageModal('${esc(card.image_url)}')" />`
    : '';

  let pm = null, tk = null;
  try { pm = card.program_matching ? JSON.parse(card.program_matching) : null; } catch {}
  try { tk = card.taka_rows ? JSON.parse(card.taka_rows) : null; } catch {}
  renderProgramTable(pm);
  renderTakaTable(tk);

  // Disable all inputs in the form
  document.querySelectorAll('#jcFormPanel input, #jcFormPanel textarea, #jcFormPanel select').forEach(el => {
    el.readOnly = true;
    el.disabled = true;
  });

  // Hide save/cancel buttons, show close button
  const actionsEl = document.querySelector('#jcFormPanel .jc-form-actions');
  if (actionsEl) {
    actionsEl.innerHTML = `<button class="btn-secondary" onclick="closeReadOnlyView()">Close</button>`;
  }
}

function closeReadOnlyView() {
  document.getElementById('jcFormPanel').style.display = 'none';
  // Re-enable all inputs for future edit use
  document.querySelectorAll('#jcFormPanel input, #jcFormPanel textarea, #jcFormPanel select').forEach(el => {
    el.readOnly = false;
    el.disabled = false;
  });
  // Restore action buttons
  const actionsEl = document.querySelector('#jcFormPanel .jc-form-actions');
  if (actionsEl) {
    actionsEl.innerHTML = `
      <button class="btn-secondary" onclick="closeJobCardForm()">Cancel</button>
      <button class="btn-primary" onclick="saveJobCard()"><i class="fa-solid fa-check"></i> Save Job Card</button>`;
  }
}

// ═══════════════════════════════════════════════════════════════
// IMAGE MODAL
// ═══════════════════════════════════════════════════════════════
function openImageModal(url) {
  if (!url) return;
  document.getElementById('jcImageModalImg').src = url;
  document.getElementById('jcImageModal').style.display = 'flex';
}

function closeImageModal() {
  document.getElementById('jcImageModal').style.display = 'none';
  document.getElementById('jcImageModalImg').src = '';
}

// ═══════════════════════════════════════════════════════════════
// UTILITIES
// ═══════════════════════════════════════════════════════════════
function esc(s) {
  if (!s) return '';
  const d = document.createElement('div');
  d.textContent = s;
  return d.innerHTML;
}

// ═══════════════════════════════════════════════════════════════
// EXPOSE GLOBALS
// ═══════════════════════════════════════════════════════════════
window.initJobCards = initJobCards;
window.switchWorkflowTab = switchWorkflowTab;
window.goToPage = goToPage;
window.openNewJobCard = openNewJobCard;
window.editJobCard = editJobCard;
window.openJobCardDetail = openJobCardDetail;
window.closeJobCardForm = closeJobCardForm;
window.deleteJobCard = deleteJobCard;
window.saveJobCard = saveJobCard;
window.uploadJobCardImage = uploadJobCardImage;
window.addTakaRow = addTakaRow;
window.removeTakaRow = removeTakaRow;
window.acceptJobCard = acceptJobCard;
window.confirmTransition = confirmTransition;
window.openCancelForm = openCancelForm;
window.closeCancelForm = closeCancelForm;
window.confirmCancellation = confirmCancellation;
window.openBorderForm = openBorderForm;
window.closeBorderForm = closeBorderForm;
window.confirmBorderForm = confirmBorderForm;
window.onJcSearch = onJcSearch;
window.setStatusFilter = setStatusFilter;
window.openReadOnlyView = openReadOnlyView;
window.closeReadOnlyView = closeReadOnlyView;
window.openImageModal = openImageModal;
window.closeImageModal = closeImageModal;

})();
