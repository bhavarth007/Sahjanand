const API = 'http://localhost:8000';

// ── Auth guard ──────────────────────────────────────────
const token    = localStorage.getItem('sahjanand_token');
const userData = JSON.parse(localStorage.getItem('sahjanand_user') || '{}');

if (!token) {
  window.location.replace('login.html');
}

// ── Init ────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  setUserInfo();
  setGreeting();
  loadSales();
  loadSamples();
});

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
  sales:     'Sales Dashboard',
  reminders: 'Reminders',
  samples:   'Samples',
  profile:   'Manage Profile',
};

function showSection(id, el) {
  document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));

  const section = document.getElementById(`section-${id}`);
  if (section) section.classList.add('active');
  if (el) el.classList.add('active');

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
  window.location.replace('login.html');
}
