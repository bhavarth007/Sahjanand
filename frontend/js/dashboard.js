const API = window.location.hostname === 'localhost' ? 'http://localhost:8000' : '';
window.API = API;

// ── Auth guard ──────────────────────────────────────────
const token    = localStorage.getItem('sahjanand_token');
const userData = JSON.parse(localStorage.getItem('sahjanand_user') || '{}');

if (!token) {
  window.location.replace('/login');
  throw new Error('Not authenticated');
}

// ── Init ────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', async () => {
  // Refresh user data from server (picks up latest permissions)
  await refreshUserData();
  setUserInfo();
  setGreeting();
  applyAccessRights();
  loadSamples();

  // Restore last active section (persist across refresh)
  const savedSection = localStorage.getItem('sahjanand_active_section');
  if (savedSection && document.getElementById(`section-${savedSection}`)) {
    const navEl = document.querySelector(`[data-section="${savedSection}"]`);
    showSection(savedSection, navEl);
  } else {
    // Default to sales chat
    if (typeof initChat === 'function') initChat();
  }
});

// ── Refresh user data from server ───────────────────────
async function refreshUserData() {
  try {
    const res = await fetch(`${API}/api/auth/me`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (res.status === 401) {
      // Token expired — force re-login
      localStorage.removeItem('sahjanand_token');
      localStorage.removeItem('sahjanand_user');
      window.location.replace('/login');
      return;
    }
    if (res.ok) {
      const freshUser = await res.json();
      Object.assign(userData, freshUser);
      localStorage.setItem('sahjanand_user', JSON.stringify(userData));
    }
  } catch { /* ignore — use cached data */ }
}

// ── User info ───────────────────────────────────────────
function getInitials(nameOrEmail) {
  const name = (nameOrEmail || '').trim();
  if (!name) return 'SJ';
  const parts = name.split(' ').filter(Boolean);
  if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
  return name.substring(0, 2).toUpperCase();
}

function setUserInfo() {
  const displayName = userData.full_name || userData.email || 'User';
  const email       = userData.email || '';
  const initials    = getInitials(displayName);

  // Topbar
  document.getElementById('userAvatar').textContent      = initials;
  document.getElementById('userNameTopbar').textContent  = displayName;
  const desigEl = document.getElementById('userDesignationTopbar');
  if (desigEl) desigEl.textContent = userData.designation || '';

  // Dropdown
  document.getElementById('dropdownAvatar').textContent  = initials;
  document.getElementById('dropdownName').textContent    = displayName;
  document.getElementById('dropdownEmail').textContent   = email;

  // Profile section
  document.getElementById('profileAvatar').textContent   = initials;
  document.getElementById('profileName').textContent     = displayName;
  document.getElementById('profileEmail').textContent    = email;

  const nameInput  = document.getElementById('editName');
  const emailInput = document.getElementById('editEmail');
  if (nameInput)  nameInput.value  = userData.full_name || '';
  if (emailInput) emailInput.value = email;
}

function setGreeting() {
  const hour  = new Date().getHours();
  let greet   = 'Good morning';
  if (hour >= 12 && hour < 17) greet = 'Good afternoon';
  else if (hour >= 17)         greet = 'Good evening';
  const name = userData.full_name || userData.email || 'there';
  const el = document.getElementById('greetingText');
  if (el) el.textContent = `${greet}, ${name}! Here's what's happening today.`;
}

// ── Access rights: hide/show nav items based on permissions ─────
function applyAccessRights() {
  // Admin sees the admin section
  if (userData.is_admin) {
    const adminNav   = document.getElementById('adminNavItem');
    const adminLabel = document.getElementById('adminNavLabel');
    if (adminNav)   adminNav.style.display   = '';
    if (adminLabel) adminLabel.style.display  = '';
  }

  // Hide sections user cannot access (admin always sees everything)
  if (!userData.is_admin) {
    const accessMap = {
      sales:     userData.can_view_sales,
      reminders: userData.can_view_reminders,
      samples:   userData.can_view_samples,
    };

    Object.entries(accessMap).forEach(([section, allowed]) => {
      if (allowed === false) {
        // Hide nav item
        const navItem = document.querySelector(`[data-section="${section}"]`);
        if (navItem) navItem.style.display = 'none';
      }
    });

    // If the default active section (sales) is hidden, show the first visible one
    const salesNav = document.querySelector('[data-section="sales"]');
    if (salesNav && salesNav.style.display === 'none') {
      const firstVisible = document.querySelector('.nav-item[data-section]:not([style*="display: none"])');
      if (firstVisible) {
        const sectionId = firstVisible.dataset.section;
        showSection(sectionId, firstVisible);
      }
    }
  }
}

// ── Profile dropdown ────────────────────────────────────
let profileOpen = false;

function toggleProfileMenu() {
  profileOpen = !profileOpen;
  document.getElementById('profileDropdown').classList.toggle('show', profileOpen);
  document.getElementById('profileBtn').classList.toggle('open', profileOpen);
}

function closeProfileMenu() {
  profileOpen = false;
  document.getElementById('profileDropdown')?.classList.remove('show');
  document.getElementById('profileBtn')?.classList.remove('open');
}

// Close dropdown on outside click
document.addEventListener('click', (e) => {
  const wrap = document.getElementById('profileWrap');
  if (wrap && !wrap.contains(e.target)) closeProfileMenu();
});

// ── Navigation ──────────────────────────────────────────
const pageTitles = {
  sales:     'Sales Chat',
  reminders: 'Reminders',
  samples:   'Samples',
  admin:     'User Management',
  profile:   'Manage Profile',
};

function showSection(id, el) {
  // Enforce access control — non-admin users cannot access restricted sections
  if (!userData.is_admin) {
    const accessMap = {
      sales:     userData.can_view_sales,
      reminders: userData.can_view_reminders,
      samples:   userData.can_view_samples,
    };
    if (accessMap[id] === false) {
      // Redirect to first allowed section instead
      const firstAllowed = document.querySelector('.nav-item[data-section]:not([style*="display: none"])');
      if (firstAllowed && firstAllowed.dataset.section !== id) {
        showSection(firstAllowed.dataset.section, firstAllowed);
      }
      return;
    }
  }

  document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));

  const section = document.getElementById(`section-${id}`);
  if (section) section.classList.add('active');
  if (el) el.classList.add('active');

  // Save active section so it persists across refresh
  localStorage.setItem('sahjanand_active_section', id);

  // Initialize chat on first open (now inside sales section)
  if (id === 'sales' && typeof initChat === 'function') {
    initChat();
  }

  // Load reminders page when Reminders section is opened
  if (id === 'reminders' && typeof loadRemindersPage === 'function') {
    loadRemindersPage();
  }

  // Initialize admin panel on first open
  if (id === 'admin' && typeof initAdmin === 'function') {
    initAdmin();
  }

  // Initialize job cards when Samples section is opened
  if (id === 'samples' && typeof initJobCards === 'function') {
    initJobCards();
  }

  // Initialize admin CRUD when profile is opened (admin only)
  if (id === 'profile' && userData.is_admin && typeof initAdminCrud === 'function') {
    initAdminCrud();
  }

  const titleEl = document.getElementById('pageTitle');
  if (titleEl) titleEl.textContent = pageTitles[id] || 'Dashboard';

  if (window.innerWidth <= 900) closeSidebar();
}

// ── Sidebar toggle ──────────────────────────────────────
let sidebarCollapsed = false;

function toggleSidebar() {
  if (window.innerWidth <= 900) {
    document.getElementById('sidebar').classList.toggle('mobile-open');
    document.getElementById('sidebarOverlay').style.display =
      document.getElementById('sidebar').classList.contains('mobile-open') ? 'block' : 'none';
  } else {
    sidebarCollapsed = !sidebarCollapsed;
    document.getElementById('sidebar').classList.toggle('collapsed', sidebarCollapsed);
    document.getElementById('mainContent').classList.toggle('expanded', sidebarCollapsed);
  }
}

function closeSidebar() {
  document.getElementById('sidebar').classList.remove('mobile-open');
  document.getElementById('sidebarOverlay').style.display = 'none';
}

// ── Load Sales ──────────────────────────────────────────
async function loadSales() {
  try {
    const res = await fetch(`${API}/api/sales/`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    if (!res.ok) return;
    const data = await res.json();

    if (data.total)  document.getElementById('statRevenue').textContent = `₹${Number(data.total).toLocaleString('en-IN')}`;
    if (data.count)  document.getElementById('statOrders').textContent  = data.count;

    if (data.items?.length) renderSalesTable(data.items);
  } catch {
    console.info('Sales API not available — showing empty state.');
  }
}

function renderSalesTable(items) {
  const tbody = document.getElementById('salesTableBody');
  if (!tbody || !items.length) return;
  tbody.innerHTML = items.map((s, i) => `
    <tr>
      <td>${i + 1}</td>
      <td>${s.customer}</td>
      <td>${s.product}</td>
      <td>₹${Number(s.amount).toLocaleString('en-IN')}</td>
      <td>${new Date(s.created_at).toLocaleDateString('en-IN')}</td>
      <td><span class="badge badge-${s.status === 'completed' ? 'success' : s.status === 'cancelled' ? 'danger' : 'warning'}">${s.status}</span></td>
    </tr>
  `).join('');
}

// ── Load Samples ────────────────────────────────────────
async function loadSamples() {
  try {
    const res = await fetch(`${API}/api/samples/`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    if (!res.ok) return;
    const data = await res.json();
    if (data?.length) renderSamples(data);
  } catch {
    console.info('Samples API not available — showing empty state.');
  }
}

function renderSamples(items) {
  const grid = document.getElementById('samplesGrid');
  if (!items.length || !grid) return;
  grid.innerHTML = items.map(item => `
    <div class="sample-card">
      <img src="${item.image_url}" alt="${item.name}" style="width:100%;height:150px;object-fit:cover;" />
      <div class="sample-info">
        <h4>${item.name || 'Sample'}</h4>
        <p>${item.description || ''}</p>
      </div>
    </div>
  `).join('');
}

// ── Upload sample ────────────────────────────────────────
async function uploadSample(input) {
  const file = input.files[0];
  if (!file) return;
  const formData = new FormData();
  formData.append('file', file);
  try {
    const res = await fetch(`${API}/api/samples/upload`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${token}` },
      body: formData,
    });
    if (res.ok) {
      const data = await res.json();
      const grid = document.getElementById('samplesGrid');
      const empty = grid?.querySelector('.empty-state');
      if (empty) empty.remove();
      const card = document.createElement('div');
      card.className = 'sample-card';
      card.innerHTML = `
        <img src="${data.image_url}" alt="Sample" style="width:100%;height:150px;object-fit:cover;" />
        <div class="sample-info"><h4>${file.name}</h4><p>Uploaded just now</p></div>
      `;
      grid?.prepend(card);
    }
  } catch {
    alert('Upload failed. Please check Cloudinary settings.');
  }
  input.value = '';
}

// ── Logout ───────────────────────────────────────────────
function logout() {
  localStorage.removeItem('sahjanand_token');
  localStorage.removeItem('sahjanand_user');
  window.location.replace('/login');
}

// ══════════════════════════════════════════════════════════════
// Reminders Page — Card-based view (Pending + History)
// Uses /api/chat/my-all-reminders endpoint
// ══════════════════════════════════════════════════════════════
let rpCurrentTab = 'pending';
let rpAutoRefreshInterval = null;
let rpAllItems = []; // cached for filtering
let rpEmptyMsgInterval = null;
const rpEmptyMessages = [
  '😊 You have zero pending reminders!',
  '🎉 All caught up! Nothing pending.',
  '💡 Want to add a reminder? Click "+ New Reminder" in Sales Chat.',
  '✅ No tasks waiting — enjoy your day!',
  '📋 Your reminder list is clear. Great job!',
];
let rpEmptyMsgIndex = 0;

async function loadRemindersPage(tab) {
  const t = tab || rpCurrentTab;
  rpCurrentTab = t;
  const grid = document.getElementById('reminderCardsGrid');
  if (!grid) return;

  try {
    const res = await fetch(`${API}/api/chat/my-all-reminders?tab=${t}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) {
      if (t === 'pending') {
        showRpEmptyState(grid);
      } else {
        grid.innerHTML = '<div class="reminder-cards-empty">No history found.</div>';
      }
      return;
    }
    rpAllItems = await res.json();
    applyRpFilters();
  } catch (e) {
    console.warn('[reminders-page]', e);
    if (t === 'pending') {
      showRpEmptyState(grid);
    } else {
      grid.innerHTML = '<div class="reminder-cards-empty">No reminders yet.</div>';
    }
  }

  // Start auto-refresh
  startRpAutoRefresh();
  // Update nav badge
  updateReminderNavBadge();
}

function applyRpFilters() {
  let items = [...rpAllItems];
  const titleFilter = (document.getElementById('rpFilterTitle')?.value || '').trim().toLowerCase();
  const personFilter = (document.getElementById('rpFilterPerson')?.value || '').trim().replace(/^@/, '').toLowerCase();

  if (titleFilter) items = items.filter(r => (r.name || '').toLowerCase().includes(titleFilter));
  if (personFilter) {
    items = items.filter(r => {
      const names = (r.remind_to_names || []).join(' ').toLowerCase();
      const singleName = (r.remind_to_name || '').toLowerCase();
      return names.includes(personFilter) || singleName.includes(personFilter);
    });
  }

  const grid = document.getElementById('reminderCardsGrid');
  if (!grid) return;

  if (!items.length) {
    if (rpCurrentTab === 'pending') {
      showRpEmptyState(grid);
    } else {
      grid.innerHTML = '<div class="reminder-cards-empty">No history found.</div>';
    }
    return;
  }

  // Stop rotating messages if we have items
  if (rpEmptyMsgInterval) { clearInterval(rpEmptyMsgInterval); rpEmptyMsgInterval = null; }

  renderReminderCards(items, rpCurrentTab, grid);
}

function showRpEmptyState(grid) {
  rpEmptyMsgIndex = 0;
  grid.innerHTML = `<div class="reminder-cards-empty rp-empty-animated" id="rpEmptyState">${rpEmptyMessages[0]}</div>`;
  // Rotate messages every 3 seconds
  if (rpEmptyMsgInterval) clearInterval(rpEmptyMsgInterval);
  rpEmptyMsgInterval = setInterval(() => {
    rpEmptyMsgIndex = (rpEmptyMsgIndex + 1) % rpEmptyMessages.length;
    const el = document.getElementById('rpEmptyState');
    if (el) {
      el.style.opacity = '0';
      setTimeout(() => {
        el.textContent = rpEmptyMessages[rpEmptyMsgIndex];
        el.style.opacity = '1';
      }, 300);
    }
  }, 3000);
}

function renderReminderCards(items, tab, grid) {
  const isAdmin = userData.is_admin;
  const isHistory = tab === 'history';

  grid.innerHTML = items.map((r) => {
    const dateStr = formatReminderDate(r.remind_date);
    const timeStr = formatReminderTime(r.remind_time);
    const toNames = r.remind_to_names && r.remind_to_names.length ? r.remind_to_names.join(', ') : (r.remind_to_name || '');
    const desc = r.description || '';
    const cardClass = isHistory ? 'rp-card rp-card-history' : 'rp-card';
    const deleteBtn = (isHistory && isAdmin) ? `<button class="rp-card-delete" onclick="deleteReminderCard(${r.id}, ${r.group_id})" title="Delete"><i class="fa-solid fa-trash-can"></i></button>` : '';

    // Media preview — compact icons
    let mediaHtml = '';
    if (r.media_url) {
      const ext = (r.media_name || r.media_url || '').split('.').pop().toLowerCase();
      if (['jpg','jpeg','png','gif','webp'].includes(ext)) {
        mediaHtml = `<div class="rp-card-media"><img class="rp-media-thumb" src="${escRp(r.media_url)}" alt="Attachment" onclick="openRpMediaLightbox('image','${escRp(r.media_url)}')" /></div>`;
      } else if (['mp3','ogg','wav','m4a','webm'].includes(ext)) {
        mediaHtml = `<div class="rp-card-media rp-card-audio"><i class="fa-solid fa-microphone"></i><audio controls preload="none" src="${escRp(r.media_url)}"></audio></div>`;
      } else if (['mp4','mov','avi'].includes(ext)) {
        mediaHtml = `<div class="rp-card-media"><button class="rp-media-icon-btn" onclick="openRpMediaLightbox('video','${escRp(r.media_url)}')" title="Play video"><i class="fa-solid fa-video"></i></button></div>`;
      } else {
        mediaHtml = `<div class="rp-card-media"><a href="${escRp(r.media_url)}" target="_blank"><i class="fa-solid fa-paperclip"></i> ${escRp(r.media_name || 'Attachment')}</a></div>`;
      }
    }

    return `
      <div class="${cardClass}" data-rpid="${r.id}">
        <div class="rp-card-icon${isHistory ? ' history' : ''}">
          <i class="fa-solid fa-bell"></i>
        </div>
        <div class="rp-card-body">
          <h4 class="rp-card-title">${escRp(r.name)}</h4>
          ${desc ? `<p class="rp-card-desc">${escRp(desc)}</p>` : ''}
          ${toNames ? `<div class="rp-card-to"><i class="fa-solid fa-user"></i> ${escRp(toNames)}</div>` : ''}
          <div class="rp-card-time"><i class="fa-regular fa-clock"></i> ${dateStr}, ${timeStr}</div>
          ${mediaHtml}
        </div>
        ${isHistory ? '<div class="rp-card-badge">DONE</div>' : `<div class="rp-card-status">${r.status === 'set' ? 'SET' : 'NOT SET'}</div>`}
        ${deleteBtn}
      </div>
    `;
  }).join('');
}

async function deleteReminderCard(rid, gid) {
  if (!confirm('Delete this reminder permanently?')) return;
  try {
    const res = await fetch(`${API}/api/chat/groups/${gid}/reminders/${rid}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token}` },
    });
    if (res.ok) {
      const el = document.querySelector(`[data-rpid="${rid}"]`);
      if (el) el.remove();
      // Check if grid is now empty
      const grid = document.getElementById('reminderCardsGrid');
      if (grid && !grid.querySelector('.rp-card')) {
        grid.innerHTML = '<div class="reminder-cards-empty">No history found.</div>';
      }
    }
  } catch {}
}

function switchRemindersPageTab(tab) {
  rpCurrentTab = tab;
  document.getElementById('rpTabPending')?.classList.toggle('active', tab === 'pending');
  document.getElementById('rpTabHistory')?.classList.toggle('active', tab === 'history');
  // Clear filters on tab switch
  const titleInput = document.getElementById('rpFilterTitle');
  const personInput = document.getElementById('rpFilterPerson');
  if (titleInput) titleInput.value = '';
  if (personInput) personInput.value = '';
  loadRemindersPage(tab);
}

function startRpAutoRefresh() {
  if (rpAutoRefreshInterval) return;
  rpAutoRefreshInterval = setInterval(() => {
    loadRemindersPage(rpCurrentTab);
    updateReminderNavBadge();
  }, 30000);
}

// Real-time nav badge update
async function updateReminderNavBadge() {
  try {
    const res = await fetch(`${API}/api/chat/my-all-reminders?tab=pending`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) return;
    const items = await res.json();
    const badge = document.getElementById('reminderBadge');
    if (badge) {
      const count = items.length;
      badge.textContent = count;
      badge.style.display = count > 0 ? 'inline-flex' : 'none';
    }
  } catch {}
}

function formatReminderDate(d) {
  if (!d) return '';
  const [y, m, day] = d.split('-');
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const today = new Date();
  const rDate = new Date(parseInt(y), parseInt(m)-1, parseInt(day));
  const diffDays = Math.round((rDate - new Date(today.getFullYear(), today.getMonth(), today.getDate())) / 86400000);
  if (diffDays === 0) return 'Today';
  if (diffDays === 1) return 'Tomorrow';
  return `${months[parseInt(m)-1]} ${parseInt(day)}, ${y}`;
}

function formatReminderTime(t) {
  if (!t) return '';
  const [h, m] = t.split(':');
  const hr = parseInt(h);
  const ampm = hr >= 12 ? 'PM' : 'AM';
  const h12 = hr % 12 || 12;
  return `${h12}:${m} ${ampm}`;
}

function escRp(s) {
  const d = document.createElement('div');
  d.textContent = s || '';
  return d.innerHTML;
}

// ── New Reminder form (Reminders page) ──
async function openRpNewReminder() {
  const panel = document.getElementById('rpFormPanel');
  if (panel) panel.style.display = 'block';
  document.getElementById('rpReminderName').value = '';
  const today = new Date().toISOString().split('T')[0];
  document.getElementById('rpReminderDate').value = today;
  document.getElementById('rpReminderDate').min = today;
  document.getElementById('rpReminderTime').value = '';
  document.getElementById('rpReminderDesc').value = '';
  // Clear media
  if (document.getElementById('rpMediaUrl')) document.getElementById('rpMediaUrl').value = '';
  if (document.getElementById('rpMediaName')) document.getElementById('rpMediaName').value = '';
  if (document.getElementById('rpMediaInfo')) document.getElementById('rpMediaInfo').textContent = '';
  // Load users for the multi-select
  await loadRpReminderUsers();
}

function closeRpNewReminder() {
  const panel = document.getElementById('rpFormPanel');
  if (panel) panel.style.display = 'none';
}

async function loadRpReminderUsers() {
  const container = document.getElementById('rpReminderToContainer');
  if (!container) return;
  try {
    const res = await fetch(`${API}/api/chat/all-users`, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) return;
    const users = await res.json();
    // Non-admin users cannot see/select admin in the list
    const isAdmin = userData.is_admin;
    const filteredUsers = isAdmin ? users : users.filter(u => !u.is_admin);

    container.innerHTML = `
      <div class="multi-select-dropdown" id="rpReminderToDropdown">
        <div class="multi-select-trigger" onclick="toggleRpReminderToDropdown()">
          <span class="multi-select-placeholder" id="rpReminderToPlaceholder">-- Select users --</span>
          <i class="fa-solid fa-chevron-down"></i>
        </div>
        <div class="multi-select-options" id="rpReminderToOptions" style="display:none;">
          ${filteredUsers.map(u => `
            <label class="multi-select-option">
              <input type="checkbox" value="${u.id}" data-name="${escRp(u.full_name||u.email)}" onchange="updateRpReminderToSelection()" />
              <span>${escRp(u.full_name||u.email)}</span>
            </label>
          `).join('')}
        </div>
      </div>
    `;
  } catch {}
}

function toggleRpReminderToDropdown() {
  const opts = document.getElementById('rpReminderToOptions');
  if (opts) opts.style.display = opts.style.display === 'none' ? 'block' : 'none';
}

function updateRpReminderToSelection() {
  const checkboxes = document.querySelectorAll('#rpReminderToOptions input[type="checkbox"]:checked');
  const names = Array.from(checkboxes).map(cb => cb.dataset.name);
  const placeholder = document.getElementById('rpReminderToPlaceholder');
  if (placeholder) {
    placeholder.textContent = names.length ? names.join(', ') : '-- Select users --';
  }
}

// Close dropdown on outside click
document.addEventListener('click', function(e) {
  const dd = document.getElementById('rpReminderToDropdown');
  if (dd && !dd.contains(e.target)) {
    const opts = document.getElementById('rpReminderToOptions');
    if (opts) opts.style.display = 'none';
  }
});

async function saveRpReminder() {
  const name = (document.getElementById('rpReminderName')?.value || '').trim();
  const rdate = document.getElementById('rpReminderDate')?.value;
  const rtime = document.getElementById('rpReminderTime')?.value;
  const desc = (document.getElementById('rpReminderDesc')?.value || '').trim();

  if (!name || !rdate || !rtime) { alert('Please fill Title, Date and Time'); return; }

  // Validate date+time is not in the past
  const selectedDT = new Date(`${rdate}T${rtime}`);
  if (selectedDT <= new Date()) {
    alert('Cannot set reminder in the past. Please choose a future date and time.');
    return;
  }

  const checkboxes = document.querySelectorAll('#rpReminderToOptions input[type="checkbox"]:checked');
  const remindToIds = Array.from(checkboxes).map(cb => parseInt(cb.value));

  // We need a group_id to create the reminder. Use the first group the user belongs to.
  // Fetch user's groups
  let gid = window.currentGroupId;
  if (!gid) {
    try {
      const gRes = await fetch(`${API}/api/chat/groups`, { headers: { Authorization: `Bearer ${token}` } });
      if (gRes.ok) {
        const groups = await gRes.json();
        if (groups.length) gid = groups[0].id;
      }
    } catch {}
  }
  if (!gid) { alert('No group available. Please join a group first.'); return; }

  const body = {
    name, remind_date: rdate, remind_time: rtime,
    description: desc || null, status: 'set',
    remind_to_ids: remindToIds.length ? remindToIds : null,
    remind_to: remindToIds.length ? remindToIds[0] : null,
    media_url: document.getElementById('rpMediaUrl')?.value || null,
    media_name: document.getElementById('rpMediaName')?.value || null,
  };

  try {
    const res = await fetch(`${API}/api/chat/groups/${gid}/reminders`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) { const e = await res.json().catch(()=>({})); alert(e.detail || 'Failed to create reminder'); return; }
    closeRpNewReminder();
    loadRemindersPage('pending');
    updateReminderNavBadge();
  } catch { alert('Network error'); }
}

// Expose
window.loadRemindersPage = loadRemindersPage;
window.switchRemindersPageTab = switchRemindersPageTab;
window.deleteReminderCard = deleteReminderCard;
// ── Media upload for Reminders page ──
async function uploadRpMedia(input) {
  const file = input.files[0];
  if (!file) return;
  const formData = new FormData();
  formData.append('file', file);
  const infoEl = document.getElementById('rpMediaInfo');
  if (infoEl) infoEl.textContent = 'Uploading...';
  try {
    const res = await fetch(`${API}/api/chat/upload`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: formData,
    });
    if (res.ok) {
      const data = await res.json();
      document.getElementById('rpMediaUrl').value = data.url || data.media_url || '';
      document.getElementById('rpMediaName').value = file.name;
      if (infoEl) infoEl.textContent = `📎 ${file.name}`;
    } else {
      if (infoEl) infoEl.textContent = 'Upload failed';
    }
  } catch {
    if (infoEl) infoEl.textContent = 'Upload failed';
  }
  input.value = '';
}

let rpRecording = false, rpMediaRecorder = null, rpAudioChunks = [];
function toggleRpVoice() {
  if (rpRecording) { stopRpVoice(); return; }
  navigator.mediaDevices.getUserMedia({ audio: true }).then(stream => {
    rpRecording = true;
    const btn = document.getElementById('rpVoiceBtn');
    if (btn) btn.style.background = '#c0392b';
    rpMediaRecorder = new MediaRecorder(stream);
    rpAudioChunks = [];
    rpMediaRecorder.ondataavailable = e => rpAudioChunks.push(e.data);
    rpMediaRecorder.onstop = async () => {
      stream.getTracks().forEach(t => t.stop());
      const blob = new Blob(rpAudioChunks, { type: 'audio/webm' });
      const file = new File([blob], 'voice_note.webm', { type: 'audio/webm' });
      const formData = new FormData();
      formData.append('file', file);
      const infoEl = document.getElementById('rpMediaInfo');
      if (infoEl) infoEl.textContent = 'Uploading voice...';
      try {
        const res = await fetch(`${API}/api/chat/upload`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${token}` },
          body: formData,
        });
        if (res.ok) {
          const data = await res.json();
          document.getElementById('rpMediaUrl').value = data.url || data.media_url || '';
          document.getElementById('rpMediaName').value = 'voice_note.webm';
          if (infoEl) infoEl.textContent = '🎤 Voice note recorded';
        }
      } catch {}
    };
    rpMediaRecorder.start();
  }).catch(() => alert('Microphone access denied. Please allow microphone permission.'));
}

function stopRpVoice() {
  rpRecording = false;
  const btn = document.getElementById('rpVoiceBtn');
  if (btn) btn.style.background = '';
  if (rpMediaRecorder && rpMediaRecorder.state === 'recording') rpMediaRecorder.stop();
}

window.uploadRpMedia = uploadRpMedia;
window.toggleRpVoice = toggleRpVoice;
window.applyRpFilters = applyRpFilters;
window.openRpNewReminder = openRpNewReminder;
window.closeRpNewReminder = closeRpNewReminder;
window.saveRpReminder = saveRpReminder;
window.toggleRpReminderToDropdown = toggleRpReminderToDropdown;
window.updateRpReminderToSelection = updateRpReminderToSelection;

// Update badge on page load
updateReminderNavBadge();

// ══════════════════════════════════════════════════════════════
// Media Lightbox for Reminder Cards
// ══════════════════════════════════════════════════════════════
function openRpMediaLightbox(type, url) {
  // Remove existing lightbox if any
  const existing = document.querySelector('.rp-media-lightbox');
  if (existing) existing.remove();

  const overlay = document.createElement('div');
  overlay.className = 'rp-media-lightbox';

  let contentHtml = '';
  if (type === 'image') {
    contentHtml = `<img src="${url}" alt="Preview" />`;
  } else if (type === 'video') {
    contentHtml = `<video controls autoplay src="${url}"></video>`;
  }

  overlay.innerHTML = `
    <button class="rp-lb-close" onclick="closeRpMediaLightbox()"><i class="fa-solid fa-xmark"></i></button>
    ${contentHtml}
  `;

  // Close on backdrop click
  overlay.addEventListener('click', function(e) {
    if (e.target === overlay) closeRpMediaLightbox();
  });

  document.body.appendChild(overlay);

  // Close on Escape key
  document.addEventListener('keydown', rpLightboxEscHandler);
}

function closeRpMediaLightbox() {
  const el = document.querySelector('.rp-media-lightbox');
  if (el) el.remove();
  document.removeEventListener('keydown', rpLightboxEscHandler);
}

function rpLightboxEscHandler(e) {
  if (e.key === 'Escape') closeRpMediaLightbox();
}

window.openRpMediaLightbox = openRpMediaLightbox;
window.closeRpMediaLightbox = closeRpMediaLightbox;

// ══════════════════════════════════════════════════════════════
// Global Reminder Alert System
// Checks ALL pending reminders for this user (across all groups)
// every 30 seconds. Fires a notification 2 min before deadline.
// ══════════════════════════════════════════════════════════════
let globalReminderInterval = null;

function startGlobalReminderChecker() {
  if (globalReminderInterval) return;
  // Request browser notification permission
  if ('Notification' in window && Notification.permission === 'default') {
    Notification.requestPermission();
  }
  // Run immediately on load
  checkGlobalUpcomingAlerts();
  checkGlobalNewReminders();
  // Then every 10 seconds for precise alerts
  globalReminderInterval = setInterval(() => {
    checkGlobalUpcomingAlerts();
  }, 10000);
}

async function checkGlobalUpcomingAlerts() {
  try {
    const res = await fetch(`${API}/api/chat/my-all-reminders`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) return;
    const items = await res.json();
    const now = new Date();

    items.forEach(r => {
      const reminderTime = new Date(`${r.remind_date}T${r.remind_time}`);
      const diffMs = reminderTime - now;
      const diffSec = diffMs / 1000;

      // Alert 1: At 2 minutes before deadline (120 sec)
      if (diffSec > 0 && diffSec <= 125 && diffSec > 15) {
        const alertKey = `reminder_2min_alert_${r.id}`;
        if (localStorage.getItem(alertKey)) return;
        localStorage.setItem(alertKey, '1');
        showGlobalReminderAlert(r, false);
        sendBrowserNotification(r, 'Reminder in 2 minutes!');
      }

      // Alert 2: At exact deadline (last 15 sec) — with SOUND
      if (diffSec > -5 && diffSec <= 15) {
        const alertKey = `reminder_deadline_alert_${r.id}`;
        if (localStorage.getItem(alertKey)) return;
        localStorage.setItem(alertKey, '1');
        showGlobalReminderAlert(r, true);
        playGlobalAlertSound();
        sendBrowserNotification(r, 'Reminder NOW!');
      }
    });
  } catch (e) { console.warn('[global-reminder] alert check failed', e); }
}

// Browser notification (works when tab is in background)
function sendBrowserNotification(r, title) {
  if ('Notification' in window && Notification.permission === 'granted') {
    new Notification(title, {
      body: `${r.name} — ${r.remind_time}`,
      icon: '/assets/images/logo.png',
      tag: `reminder_${r.id}_${title}`,
      requireInteraction: true,
    });
  }
}

async function checkGlobalNewReminders() {
  try {
    const res = await fetch(`${API}/api/chat/my-all-reminders`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) return;
    const items = await res.json();

    // Show notification for new reminders assigned to this user
    items.forEach(r => {
      if (r.remind_to !== userData.id) return;
      const key = `reminder_notif_seen_${r.id}`;
      if (localStorage.getItem(key)) return;
      localStorage.setItem(key, '1');
      showGlobalReminderAlert(r, false);
    });

    // Update bell badge count
    const pendingCount = items.filter(r => r.remind_to === userData.id).length;
    localStorage.setItem('notif_pending_count', String(pendingCount));
    updateNotificationBadge(pendingCount);
  } catch (e) { console.warn('[global-reminder] notification check failed', e); }
}

function updateNotificationBadge(count) {
  const dot = document.getElementById('notifStatusDot');
  if (!dot) return;

  if (count === 0) {
    // No pending notifications — green dot
    dot.className = 'notif-status-dot green';
    // Clear the "last seen" count since there's nothing pending
    localStorage.setItem('notif_last_seen_count', '0');
  } else {
    // There are pending notifications
    const lastSeenCount = parseInt(localStorage.getItem('notif_last_seen_count') || '0', 10);
    const bellClicked = localStorage.getItem('notif_bell_clicked') === 'true';

    if (count > lastSeenCount) {
      // New notifications arrived since last bell click — red dot (unseen)
      dot.className = 'notif-status-dot red';
      // Reset the "clicked" flag since there are new ones
      localStorage.setItem('notif_bell_clicked', 'false');
    } else if (bellClicked) {
      // User has clicked the bell, but still has pending — yellow dot
      dot.className = 'notif-status-dot yellow';
    } else {
      // Pending exists but user hasn't clicked bell yet — red dot
      dot.className = 'notif-status-dot red';
    }
  }
}

// Handle notification bell click — marks as "seen" (turns yellow if pending)
function handleNotifBellClick() {
  const dot = document.getElementById('notifStatusDot');

  // If there are pending reminders, mark as seen (red → yellow)
  if (dot && dot.classList.contains('red')) {
    dot.className = 'notif-status-dot yellow';
    localStorage.setItem('notif_bell_clicked', 'true');
    // Save current count as "last seen" so new ones trigger red again
    const currentCount = parseInt(localStorage.getItem('notif_pending_count') || '0', 10);
    localStorage.setItem('notif_last_seen_count', String(currentCount));
  }

  // Check if user has access to reminders section
  if (!userData.is_admin && userData.can_view_reminders === false) {
    alert('You do not have access to the Reminders section.');
    return;
  }

  // Navigate to reminders section
  showSection('reminders', document.querySelector('[data-section=reminders]'));
}

// Expose handleNotifBellClick globally
window.handleNotifBellClick = handleNotifBellClick;

function showGlobalReminderAlert(r, isUrgent) {
  const dateStr = r.remind_date || '';
  const timeStr = r.remind_time || '';
  const el = document.createElement('div');
  el.className = 'reminder-notification';
  el.innerHTML = `
    <button class="reminder-notif-close" onclick="this.parentElement.remove()"><i class="fa-solid fa-xmark"></i></button>
    <div class="reminder-notif-header"><i class="fa-solid fa-bell"></i> ${isUrgent ? '⚡ Reminder Alert!' : 'New Reminder'}</div>
    <div class="reminder-notif-body">
      <strong>${escHtml(r.created_by_name || 'Someone')}</strong> has set a reminder${r.remind_to_name ? ' for <strong>' + escHtml(r.remind_to_name) + '</strong>' : ''}.
      <br><br>
      <b>📌 Title:</b> ${escHtml(r.name)}<br>
      <b>📅 Date:</b> ${dateStr}<br>
      <b>⏰ Time:</b> ${timeStr}<br>
      ${r.description ? '<b>📝 Note:</b> ' + escHtml(r.description) + '<br>' : ''}
    </div>
  `;
  document.body.appendChild(el);

  // Play alert sound for urgent (2 min before) alerts
  if (isUrgent) playGlobalAlertSound();

  // Auto-dismiss after 15 seconds for non-urgent
  if (!isUrgent) setTimeout(() => el.remove(), 15000);
}

function escHtml(s) {
  const d = document.createElement('div');
  d.textContent = s || '';
  return d.innerHTML;
}

function playGlobalAlertSound() {
  try {
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    const now = ctx.currentTime;
    for (let t = 0; t < 3; t += 0.4) {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.connect(gain); gain.connect(ctx.destination);
      osc.type = 'square';
      osc.frequency.value = t % 0.8 < 0.4 ? 1200 : 800;
      gain.gain.value = 0.12;
      osc.start(now + t);
      osc.stop(now + t + 0.18);
    }
  } catch {}
}

// Start the global checker as soon as dashboard loads
startGlobalReminderChecker();
