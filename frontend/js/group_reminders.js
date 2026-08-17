;(function() {
'use strict';
const R_API = (typeof window.API !== 'undefined') ? window.API : (window.location.hostname === 'localhost' ? 'http://localhost:8000' : '');
let currentRTab = 'pending';
let editingReminderId = null;
let reminderCheckInterval = null;
let reminderAutoRefreshInterval = null;
let allReminders = [];  // cached for filtering

// ═══════════════════════════════════════════════════════════════
// Load reminders
// ═══════════════════════════════════════════════════════════════
async function loadGroupReminders(tab) {
  const gid = window.currentGroupId;
  if (!gid) { renderEmpty(); return; }
  const t = tab || currentRTab;
  const token = localStorage.getItem('sahjanand_token');
  try {
    const res = await fetch(`${R_API}/api/chat/groups/${gid}/reminders?tab=${t}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) return;
    allReminders = await res.json();
    applyFiltersAndRender(t);
  } catch(e) { console.warn('[reminders]', e); }
  // Start auto-refresh if not already running
  startReminderAutoRefresh();
}

// Auto-refresh: every 30s check if any pending reminder has expired → reload list
function startReminderAutoRefresh() {
  if (reminderAutoRefreshInterval) return;
  reminderAutoRefreshInterval = setInterval(() => {
    if (currentRTab !== 'pending') return;
    // Check if any visible reminder has passed its deadline
    const now = new Date();
    const hasExpired = allReminders.some(r => {
      const rt = new Date(`${r.remind_date}T${r.remind_time}`);
      return rt <= now;
    });
    if (hasExpired) {
      loadGroupReminders('pending');
    }
  }, 30000);
}

function renderEmpty() {
  const list = document.getElementById('reminderList');
  if (list) list.innerHTML = '<div class="reminder-empty">Select a group to see reminders</div>';
}

function applyFiltersAndRender(tab) {
  let items = [...allReminders];
  const titleFilter = document.getElementById('filterTitle')?.value?.trim().toLowerCase() || '';
  const userFilterRaw = document.getElementById('filterUser')?.value?.trim() || '';
  // Extract name after @ (or use the raw text)
  const userFilter = userFilterRaw.startsWith('@') ? userFilterRaw.slice(1).toLowerCase() : userFilterRaw.toLowerCase();

  if (titleFilter) items = items.filter(r => r.name.toLowerCase().includes(titleFilter));
  if (userFilter) items = items.filter(r => (r.remind_to_name || '').toLowerCase().includes(userFilter));

  renderReminders(items, tab || currentRTab);
}

function renderReminders(items, tab) {
  const list = document.getElementById('reminderList');
  if (!list) return;
  if (!items.length) {
    list.innerHTML = `<div class="reminder-empty">${tab==='pending'?'No pending reminders':'No history yet'}</div>`;
    return;
  }
  list.innerHTML = items.map(r => {
    const dateStr = formatRDate(r.remind_date);
    const timeStr = formatRTime(r.remind_time);
    const iconClass = tab==='pending'?'pending':'history';
    const iconHtml = tab==='pending'?'<i class="fa-solid fa-clock"></i>':'<i class="fa-solid fa-check-circle"></i>';
    const statusClass = tab==='history'?'done':r.status.replace(' ','_');
    const statusLabel = tab==='history'?'Done':(r.status==='set'?'Set':'Not Set');
    // Show all targeted persons
    const toNames = r.remind_to_names && r.remind_to_names.length ? r.remind_to_names : (r.remind_to_name ? [r.remind_to_name] : []);
    const toLabel = toNames.length ? `<span class="reminder-row-to">→ ${toNames.map(n => esc(n)).join(', ')}</span>` : '';
    const descHtml = r.description ? `<div class="reminder-row-desc">${esc(r.description)}</div>` : '';
    const mediaHtml = r.media_url ? buildMediaPreview(r.media_url, r.media_name) : '';
    const editBtn = tab==='pending' ? `<button class="reminder-row-edit" onclick="editReminder(${r.id})" title="Edit"><i class="fa-solid fa-pen"></i></button>` : '';

    return `
    <div class="reminder-row" data-rid="${r.id}" data-json='${JSON.stringify(r).replace(/'/g,"&#39;")}'>
      <div class="reminder-row-icon ${iconClass}">${iconHtml}</div>
      <div class="reminder-row-info">
        <div class="reminder-row-name">${esc(r.name)} ${toLabel}</div>
        <div class="reminder-row-time">${dateStr} • ${timeStr}</div>
        ${descHtml}${mediaHtml}
      </div>
      <span class="reminder-row-status ${statusClass}">${statusLabel}</span>
      ${editBtn}
      <button class="reminder-row-delete" onclick="deleteGroupReminder(${r.id})" title="Delete"><i class="fa-solid fa-trash-can"></i></button>
    </div>`;
  }).join('');
}

function buildMediaPreview(url, name) {
  const ext = (name || url || '').split('.').pop().toLowerCase();
  if (['jpg','jpeg','png','gif','webp'].includes(ext)) {
    return `<div class="reminder-row-media" style="margin-top:6px;"><img src="${esc(url)}" style="width:36px;height:36px;border-radius:6px;cursor:pointer;object-fit:cover;border:1px solid var(--border);" onclick="openRpMediaLightbox('image','${esc(url)}')" /></div>`;
  }
  if (['mp3','ogg','wav','m4a','webm'].includes(ext)) {
    return `<div class="reminder-row-media" style="display:flex;align-items:center;gap:6px;background:#f9f5f3;padding:3px 8px;border-radius:16px;max-width:160px;margin-top:6px;"><i class="fa-solid fa-microphone" style="color:var(--primary);font-size:.7rem;"></i><audio controls src="${esc(url)}" preload="none" style="height:22px;flex:1;min-width:0;"></audio></div>`;
  }
  if (['mp4','mov','avi'].includes(ext)) {
    return `<div class="reminder-row-media" style="margin-top:6px;"><button style="width:36px;height:36px;border-radius:8px;background:#f5f5f5;border:1px solid var(--border);display:flex;align-items:center;justify-content:center;cursor:pointer;" onclick="openRpMediaLightbox('video','${esc(url)}')" title="Play video"><i class="fa-solid fa-video" style="font-size:.8rem;color:var(--text-secondary);"></i></button></div>`;
  }
  return `<div class="reminder-row-media"><a href="${esc(url)}" target="_blank" style="font-size:.78rem;color:var(--primary);"><i class="fa-solid fa-paperclip"></i> ${esc(name||'Attachment')}</a></div>`;
}

// ═══════════════════════════════════════════════════════════════
// Tabs
// ═══════════════════════════════════════════════════════════════
function switchReminderTab(tab) {
  currentRTab = tab;
  document.getElementById('tabPending')?.classList.toggle('active', tab==='pending');
  document.getElementById('tabHistory')?.classList.toggle('active', tab==='history');
  const btn = document.getElementById('addReminderBtn');
  if (btn) btn.style.display = tab==='pending'?'':'none';
  loadGroupReminders(tab);
}

// ═══════════════════════════════════════════════════════════════
// Form open/close
// ═══════════════════════════════════════════════════════════════
function openReminderForm() {
  editingReminderId = null;
  const form = document.getElementById('reminderForm');
  if (form) form.style.display = 'block';
  document.getElementById('reminderFormTitle').textContent = 'New Reminder';
  document.getElementById('reminderName').value = '';
  const today = new Date().toISOString().split('T')[0];
  document.getElementById('reminderDate').value = today;
  document.getElementById('reminderDate').min = today;
  document.getElementById('reminderTime').value = '';
  document.getElementById('reminderDesc').value = '';
  document.getElementById('reminderStatus').value = 'set';
  document.getElementById('reminderMediaUrl').value = '';
  document.getElementById('reminderMediaName').value = '';
  document.getElementById('reminderMediaInfo').textContent = '';
  loadReminderUsers();
}

function closeReminderForm() {
  document.getElementById('reminderForm').style.display = 'none';
  editingReminderId = null;
}

async function loadReminderUsers() {
  const container = document.getElementById('reminderToContainer');
  if (!container) return;
  const token = localStorage.getItem('sahjanand_token');
  const currentUserData = JSON.parse(localStorage.getItem('sahjanand_user') || '{}');
  try {
    const res = await fetch(`${R_API}/api/chat/all-users`, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) return;
    const users = await res.json();
    // Non-admin users cannot select admin in the list
    const isAdmin = currentUserData.is_admin;
    const filteredUsers = isAdmin ? users : users.filter(u => !u.is_admin);

    container.innerHTML = `
      <div class="multi-select-dropdown" id="reminderToDropdown">
        <div class="multi-select-trigger" onclick="toggleReminderToDropdown()">
          <span class="multi-select-placeholder" id="reminderToPlaceholder">-- Select users --</span>
          <i class="fa-solid fa-chevron-down"></i>
        </div>
        <div class="multi-select-options" id="reminderToOptions" style="display:none;">
          ${filteredUsers.map(u => `
            <label class="multi-select-option">
              <input type="checkbox" value="${u.id}" data-name="${esc(u.full_name||u.email)}" onchange="updateReminderToSelection()" />
              <span>${esc(u.full_name||u.email)}</span>
            </label>
          `).join('')}
        </div>
      </div>
    `;
  } catch {}
}

function toggleReminderToDropdown() {
  const opts = document.getElementById('reminderToOptions');
  if (opts) opts.style.display = opts.style.display === 'none' ? 'block' : 'none';
}

function updateReminderToSelection() {
  const checkboxes = document.querySelectorAll('#reminderToOptions input[type="checkbox"]:checked');
  const names = Array.from(checkboxes).map(cb => cb.dataset.name);
  const placeholder = document.getElementById('reminderToPlaceholder');
  if (placeholder) {
    placeholder.textContent = names.length ? names.join(', ') : '-- Select users --';
    placeholder.title = names.join(', ');
  }
}

function getSelectedReminderToIds() {
  const checkboxes = document.querySelectorAll('#reminderToOptions input[type="checkbox"]:checked');
  return Array.from(checkboxes).map(cb => parseInt(cb.value));
}

function setSelectedReminderToIds(ids) {
  if (!ids || !ids.length) return;
  const checkboxes = document.querySelectorAll('#reminderToOptions input[type="checkbox"]');
  checkboxes.forEach(cb => {
    cb.checked = ids.includes(parseInt(cb.value));
  });
  updateReminderToSelection();
}

// ═══════════════════════════════════════════════════════════════
// Edit
// ═══════════════════════════════════════════════════════════════
function editReminder(rid) {
  const row = document.querySelector(`[data-rid="${rid}"]`);
  if (!row) return;
  const r = JSON.parse(row.dataset.json);
  editingReminderId = rid;
  document.getElementById('reminderForm').style.display = 'block';
  document.getElementById('reminderFormTitle').textContent = 'Edit Reminder';
  document.getElementById('reminderName').value = r.name || '';
  document.getElementById('reminderDate').value = r.remind_date || '';
  document.getElementById('reminderTime').value = r.remind_time || '';
  document.getElementById('reminderDesc').value = r.description || '';
  document.getElementById('reminderStatus').value = r.status || 'set';
  document.getElementById('reminderMediaUrl').value = r.media_url || '';
  document.getElementById('reminderMediaName').value = r.media_name || '';
  document.getElementById('reminderMediaInfo').textContent = r.media_name ? `📎 ${r.media_name}` : '';
  loadReminderUsers().then(() => {
    const ids = r.remind_to_ids || (r.remind_to ? [r.remind_to] : []);
    setSelectedReminderToIds(ids);
  });
}

// ═══════════════════════════════════════════════════════════════
// Save
// ═══════════════════════════════════════════════════════════════
async function saveReminder() {
  const gid = window.currentGroupId;
  if (!gid) { rToast('Select a group first','error'); return; }

  const name = (document.getElementById('reminderName')?.value||'').trim();
  const rdate = document.getElementById('reminderDate')?.value;
  const rtime = document.getElementById('reminderTime')?.value;
  const desc = (document.getElementById('reminderDesc')?.value||'').trim();
  const status = document.getElementById('reminderStatus')?.value || 'set';
  const remindToIds = getSelectedReminderToIds();
  const mediaUrl = document.getElementById('reminderMediaUrl')?.value || null;
  const mediaName = document.getElementById('reminderMediaName')?.value || null;

  if (!name||!rdate||!rtime) { rToast('Fill Title, Date and Time','error'); return; }

  // Validate date+time is not in the past (IST)
  const selectedDT = new Date(`${rdate}T${rtime}`);
  if (selectedDT <= new Date()) {
    rToast('Cannot set reminder in the past. Choose a future date/time.','error');
    return;
  }

  const token = localStorage.getItem('sahjanand_token');
  const body = {
    name, remind_date: rdate, remind_time: rtime,
    description: desc || null, status,
    remind_to_ids: remindToIds.length ? remindToIds : null,
    remind_to: remindToIds.length ? remindToIds[0] : null,
    media_url: mediaUrl || null, media_name: mediaName || null,
  };

  const isEdit = !!editingReminderId;
  const url = isEdit
    ? `${R_API}/api/chat/groups/${gid}/reminders/${editingReminderId}`
    : `${R_API}/api/chat/groups/${gid}/reminders`;

  try {
    const res = await fetch(url, {
      method: isEdit?'PATCH':'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) { const e=await res.json().catch(()=>({})); rToast(e.detail||'Failed','error'); return; }
    const saved = await res.json();
    rToast(isEdit?'Updated!':'Created!','success');
    closeReminderForm();
    loadGroupReminders('pending');
    // Show notification to creator
    if (!isEdit) showReminderNotification(saved);
  } catch { rToast('Network error','error'); }
}

// ═══════════════════════════════════════════════════════════════
// Voice note recording for reminders
// ═══════════════════════════════════════════════════════════════
let rRecording = false, rMediaRecorder = null, rAudioChunks = [];

async function toggleReminderVoice() {
  if (rRecording) {
    rMediaRecorder && rMediaRecorder.stop();
    rRecording = false;
    document.getElementById('reminderVoiceBtn')?.classList.remove('recording');
    return;
  }
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    rAudioChunks = [];
    rMediaRecorder = new MediaRecorder(stream);
    rMediaRecorder.ondataavailable = e => rAudioChunks.push(e.data);
    rMediaRecorder.onstop = async () => {
      const blob = new Blob(rAudioChunks, { type: 'audio/webm' });
      const file = new File([blob], `reminder_voice_${Date.now()}.webm`, { type: 'audio/webm' });
      stream.getTracks().forEach(t => t.stop());
      await uploadReminderFile(file);
    };
    rMediaRecorder.start();
    rRecording = true;
    document.getElementById('reminderVoiceBtn')?.classList.add('recording');
    rToast('Recording… click again to stop', 'info');
  } catch { rToast('Microphone denied', 'error'); }
}

async function uploadReminderMedia(input) {
  const file = input.files[0];
  if (!file) return;
  await uploadReminderFile(file);
  input.value = '';
}

async function uploadReminderFile(file) {
  const token = localStorage.getItem('sahjanand_token');
  const fd = new FormData(); fd.append('file', file);
  try {
    const res = await fetch(`${R_API}/api/chat/upload`, {
      method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: fd,
    });
    if (!res.ok) { rToast('Upload failed','error'); return; }
    const data = await res.json();
    document.getElementById('reminderMediaUrl').value = data.media_url;
    document.getElementById('reminderMediaName').value = data.media_name || file.name;
    document.getElementById('reminderMediaInfo').textContent = `📎 ${file.name}`;
    rToast('Attached!','success');
  } catch { rToast('Upload error','error'); }
}

// ═══════════════════════════════════════════════════════════════
// Delete
// ═══════════════════════════════════════════════════════════════
async function deleteGroupReminder(rid) {
  if (!confirm('Delete this reminder?')) return;
  const gid = window.currentGroupId;
  if (!gid) return;
  const token = localStorage.getItem('sahjanand_token');
  try {
    const res = await fetch(`${R_API}/api/chat/groups/${gid}/reminders/${rid}`, {
      method:'DELETE', headers:{Authorization:`Bearer ${token}`},
    });
    if (!res.ok) { rToast('Delete failed','error'); return; }
    document.querySelector(`[data-rid="${rid}"]`)?.remove();
    rToast('Deleted','success');
  } catch { rToast('Network error','error'); }
}

// ═══════════════════════════════════════════════════════════════
// Notification + Alert 2 min before reminder time
// ═══════════════════════════════════════════════════════════════
async function checkReminderNotifications() {
  // This function is no longer called on group select.
  // The global checker in dashboard.js handles all reminder alerts.
  // Kept for backward compatibility but does nothing.
  return;
}

// Check every 30 seconds for reminders approaching (2 min before)
function startReminderAlertChecker() {
  if (reminderCheckInterval) return;
  reminderCheckInterval = setInterval(() => {
    checkUpcomingAlerts();
  }, 30000);
  // Also run immediately
  checkUpcomingAlerts();
}

async function checkUpcomingAlerts() {
  const gid = window.currentGroupId;
  if (!gid) return;
  const token = localStorage.getItem('sahjanand_token');
  try {
    const res = await fetch(`${R_API}/api/chat/groups/${gid}/reminders?tab=pending`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) return;
    const items = await res.json();
    const now = new Date();
    const userData = JSON.parse(localStorage.getItem('sahjanand_user') || '{}');

    items.forEach(r => {
      // Only alert for reminders targeted at me OR created by me
      if (r.remind_to !== userData.id && r.created_by !== userData.id) return;

      const reminderTime = new Date(`${r.remind_date}T${r.remind_time}`);
      const diffMs = reminderTime - now;
      const diffMin = diffMs / 60000;

      // Fire exactly once when 2 min or less remain (but still in future)
      // Window: between 0 and 2.5 minutes before
      if (diffMin > 0 && diffMin <= 2.5) {
        const alertKey = `reminder_2min_alert_${r.id}`;
        if (localStorage.getItem(alertKey)) return; // already fired (persists across refresh)
        localStorage.setItem(alertKey, '1');
        showReminderNotification(r, true);
      }
    });
  } catch {}
}

function showReminderNotification(r, withBuzz) {
  const dateStr = formatRDate(r.remind_date);
  const timeStr = formatRTime(r.remind_time);
  const el = document.createElement('div');
  el.className = 'reminder-notification';
  el.innerHTML = `
    <button class="reminder-notif-close" onclick="this.parentElement.remove()"><i class="fa-solid fa-xmark"></i></button>
    <div class="reminder-notif-header"><i class="fa-solid fa-bell"></i> Reminder${withBuzz?' ⚡ Alert!':''}</div>
    <div class="reminder-notif-body">
      <strong>${esc(r.created_by_name||'Someone')}</strong> has set a reminder${r.remind_to_name?' for <strong>'+esc(r.remind_to_name)+'</strong>':''}.
      <br><br>
      <b>📅 Date:</b> ${dateStr}<br>
      <b>⏰ Time:</b> ${timeStr}<br>
      ${r.description ? `<b>📝 Description:</b> ${esc(r.description)}<br>` : ''}
      ${r.media_url ? `<b>📎 Attachment:</b> <a href="${esc(r.media_url)}" target="_blank">${esc(r.media_name||'View')}</a><br>` : ''}
    </div>
  `;
  document.body.appendChild(el);

  // Only play alert sound when explicitly requested (deadline alerts)
  if (withBuzz === true) playAlertSound();

  // Auto-dismiss non-urgent notifications after 10 seconds
  if (!withBuzz) setTimeout(() => { if (el.parentElement) el.remove(); }, 10000);
}

// ═══════════════════════════════════════════════════════════════
// Sound: distinctive 5-second alarm (urgent siren-like pattern)
// ═══════════════════════════════════════════════════════════════
function playAlertSound() {
  try {
    // Vibrate phone (works on Android WebView)
    if (navigator.vibrate) navigator.vibrate([200, 100, 200, 100, 400]);

    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    const now = ctx.currentTime;
    const duration = 5; // 5 seconds total

    // Create an urgent two-tone siren pattern
    for (let t = 0; t < duration; t += 0.4) {
      // High tone
      const osc1 = ctx.createOscillator();
      const gain1 = ctx.createGain();
      osc1.connect(gain1); gain1.connect(ctx.destination);
      osc1.type = 'square';
      osc1.frequency.value = 1200;
      gain1.gain.value = 0.15;
      osc1.start(now + t);
      osc1.stop(now + t + 0.18);

      // Low tone (offset by 0.2s)
      if (t + 0.2 < duration) {
        const osc2 = ctx.createOscillator();
        const gain2 = ctx.createGain();
        osc2.connect(gain2); gain2.connect(ctx.destination);
        osc2.type = 'square';
        osc2.frequency.value = 800;
        gain2.gain.value = 0.15;
        osc2.start(now + t + 0.2);
        osc2.stop(now + t + 0.38);
      }
    }
  } catch(e) { console.warn('[alert sound]', e); }
}

// ═══════════════════════════════════════════════════════════════
// Filters: by Title and by "Reminder To" user
// Default filter persisted in localStorage
// ═══════════════════════════════════════════════════════════════
function initFilters() {
  const saved = JSON.parse(localStorage.getItem('reminder_default_filter') || '{}');
  const titleInput = document.getElementById('filterTitle');
  const userInput = document.getElementById('filterUser');

  if (saved.title && titleInput) titleInput.value = saved.title;
  if (saved.user && userInput) userInput.value = saved.user;

  updateFilterBadge();
}

function applyFilter() {
  applyFiltersAndRender(currentRTab);
  updateFilterBadge();
}

function setDefaultFilter() {
  const title = document.getElementById('filterTitle')?.value?.trim() || '';
  const user = document.getElementById('filterUser')?.value?.trim() || '';
  localStorage.setItem('reminder_default_filter', JSON.stringify({ title, user }));
  rToast('Default filter saved!', 'success');
  updateFilterBadge();
}

function clearFilter() {
  const titleInput = document.getElementById('filterTitle');
  const userInput = document.getElementById('filterUser');
  if (titleInput) titleInput.value = '';
  if (userInput) userInput.value = '';
  // Re-apply default filter if exists
  const saved = JSON.parse(localStorage.getItem('reminder_default_filter') || '{}');
  if (saved.title && titleInput) titleInput.value = saved.title;
  if (saved.user && userInput) userInput.value = saved.user;
  applyFiltersAndRender(currentRTab);
  updateFilterBadge();
}

function removeDefaultFilter() {
  localStorage.removeItem('reminder_default_filter');
  const titleInput = document.getElementById('filterTitle');
  const userInput = document.getElementById('filterUser');
  if (titleInput) titleInput.value = '';
  if (userInput) userInput.value = '';
  applyFiltersAndRender(currentRTab);
  rToast('Default filter removed', 'success');
  updateFilterBadge();
}

function updateFilterBadge() {
  const hasDefault = !!localStorage.getItem('reminder_default_filter');
  const titleVal = document.getElementById('filterTitle')?.value?.trim();
  const userVal = document.getElementById('filterUser')?.value?.trim();
  const active = !!(titleVal || userVal);

  const badge = document.getElementById('filterActiveBadge');
  if (badge) badge.style.display = active ? 'inline-flex' : 'none';

  const defaultBadge = document.getElementById('filterDefaultBadge');
  if (defaultBadge) defaultBadge.style.display = hasDefault ? 'inline-flex' : 'none';
}

// ═══════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════
function formatRDate(d) {
  if (!d) return '';
  const [y,m,day] = d.split('-');
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return `${parseInt(day)} ${months[parseInt(m)-1]} ${y}`;
}
function formatRTime(t) {
  if (!t) return '';
  const [h,m] = t.split(':');
  const hr = parseInt(h);
  const ampm = hr >= 12 ? 'PM' : 'AM';
  const h12 = hr % 12 || 12;
  return `${String(h12).padStart(2,'0')}:${m} ${ampm}`;
}
function esc(s) { return s?String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'):''; }
function rToast(msg,type){const c={info:'#667781',success:'#25d366',error:'#c0392b'};const el=document.createElement('div');el.textContent=msg;Object.assign(el.style,{position:'fixed',bottom:'80px',left:'50%',transform:'translateX(-50%)',background:c[type]||'#667781',color:'#fff',padding:'8px 20px',borderRadius:'20px',fontSize:'.85rem',zIndex:'9998',boxShadow:'0 2px 10px rgba(0,0,0,.2)',fontFamily:'inherit',pointerEvents:'none'});document.body.appendChild(el);setTimeout(()=>el.remove(),2800);}

// Close multi-select dropdown when clicking outside
document.addEventListener('click', function(e) {
  const dropdown = document.getElementById('reminderToDropdown');
  if (dropdown && !dropdown.contains(e.target)) {
    const opts = document.getElementById('reminderToOptions');
    if (opts) opts.style.display = 'none';
  }
});

// ═══════════════════════════════════════════════════════════════
// Expose
// ═══════════════════════════════════════════════════════════════
window.loadGroupReminders = loadGroupReminders;
window.switchReminderTab = switchReminderTab;
window.openReminderForm = openReminderForm;
window.closeReminderForm = closeReminderForm;
window.saveReminder = saveReminder;
window.editReminder = editReminder;
window.deleteGroupReminder = deleteGroupReminder;
window.uploadReminderMedia = uploadReminderMedia;
window.toggleReminderVoice = toggleReminderVoice;
window.checkReminderNotifications = checkReminderNotifications;
window.startReminderAlertChecker = startReminderAlertChecker;
window.applyFilter = applyFilter;
window.setDefaultFilter = setDefaultFilter;
window.clearFilter = clearFilter;
window.removeDefaultFilter = removeDefaultFilter;
window.initFilters = initFilters;
window.toggleReminderToDropdown = toggleReminderToDropdown;
window.updateReminderToSelection = updateReminderToSelection;
window.clearFilter = clearFilter;
window.removeDefaultFilter = removeDefaultFilter;
window.initFilters = initFilters;
})();
