const API = 'http://localhost:8000';

// ── Auth guard ──
const token = localStorage.getItem('sahjanand_token');
const userData = JSON.parse(localStorage.getItem('sahjanand_user') || '{}');

if (!token) {
  window.location.href = 'login.html';
}

// ── Init ──
document.addEventListener('DOMContentLoaded', () => {
  setUserInfo();
  setGreeting();
  loadSales();
  loadSamples();
});

function setUserInfo() {
  const name  = userData.full_name || userData.email || 'User';
  const initials = name.split(' ').map(w => w[0]).join('').toUpperCase().slice(0, 2) || 'SJ';

  document.getElementById('userAvatar').textContent    = initials;
  document.getElementById('profileAvatar').textContent = initials;
  document.getElementById('profileName').textContent   = name;
  document.getElementById('profileEmail').textContent  = userData.email || '—';
  document.getElementById('greetingText').textContent  = `Welcome back, ${name}! Here's what's happening today.`;
}

function setGreeting() {
  const hour = new Date().getHours();
  let greet = 'Good morning';
  if (hour >= 12 && hour < 17) greet = 'Good afternoon';
  else if (hour >= 17)         greet = 'Good evening';
  const name = userData.full_name || userData.email || '';
  document.getElementById('greetingText').textContent = `${greet}, ${name}! Here's your overview.`;
}

// ── Navigation ──
const pageTitles = {
  sales:     'Sales Dashboard',
  reminders: 'Reminders',
  samples:   'Samples',
  profile:   'My Profile',
};

function showSection(id, el) {
  // Prevent default link behavior
  event && event.preventDefault();

  // Hide all sections
  document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));

  // Show selected
  document.getElementById(`section-${id}`)?.classList.add('active');
  if (el) el.classList.add('active');

  document.getElementById('pageTitle').textContent = pageTitles[id] || 'Dashboard';

  // Close mobile sidebar
  if (window.innerWidth <= 900) closeSidebar();
}

// ── Sidebar toggle ──
let sidebarCollapsed = false;

function toggleSidebar() {
  if (window.innerWidth <= 900) {
    // Mobile: slide in/out
    document.getElementById('sidebar').classList.toggle('mobile-open');
    document.getElementById('sidebarOverlay').style.display =
      document.getElementById('sidebar').classList.contains('mobile-open') ? 'block' : 'none';
  } else {
    // Desktop: collapse
    sidebarCollapsed = !sidebarCollapsed;
    document.getElementById('sidebar').classList.toggle('collapsed', sidebarCollapsed);
    document.getElementById('mainContent').classList.toggle('expanded', sidebarCollapsed);
  }
}

function closeSidebar() {
  document.getElementById('sidebar').classList.remove('mobile-open');
  document.getElementById('sidebarOverlay').style.display = 'none';
}

// ── Load Sales ──
async function loadSales() {
  try {
    const res = await fetch(`${API}/api/sales/`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    if (!res.ok) return;
    const data = await res.json();
    // TODO: populate stat cards and table when real data exists
  } catch {
    // Backend not running locally — graceful fallback
    console.info('Sales API unavailable — showing empty state.');
  }
}

// ── Load Samples ──
async function loadSamples() {
  try {
    const res = await fetch(`${API}/api/samples/`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    if (!res.ok) return;
    const data = await res.json();
    renderSamples(data.items || []);
  } catch {
    console.info('Samples API unavailable — showing empty state.');
  }
}

function renderSamples(items) {
  const grid = document.getElementById('samplesGrid');
  if (!items.length) return;
  grid.innerHTML = items.map(item => `
    <div class="sample-card">
      <div class="sample-img">
        <img src="${item.url}" alt="${item.name}" style="width:100%;height:150px;object-fit:cover;" />
      </div>
      <div class="sample-info">
        <h4>${item.name || 'Sample'}</h4>
        <p>${item.description || ''}</p>
      </div>
    </div>
  `).join('');
}

// ── Upload sample ──
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
      // Remove empty state if present
      const empty = grid.querySelector('.empty-state');
      if (empty) empty.remove();

      const card = document.createElement('div');
      card.className = 'sample-card';
      card.innerHTML = `
        <img src="${data.url}" alt="Sample" style="width:100%;height:150px;object-fit:cover;" />
        <div class="sample-info">
          <h4>${file.name}</h4>
          <p>Uploaded just now</p>
        </div>
      `;
      grid.prepend(card);
    }
  } catch {
    alert('Upload failed. Please ensure backend is running.');
  }

  input.value = '';
}

// ── Add Reminder modal placeholder ──
function openReminderModal() {
  alert('Reminder creation form coming soon!');
}

// ── Logout ──
function logout() {
  localStorage.removeItem('sahjanand_token');
  localStorage.removeItem('sahjanand_user');
  window.location.href = 'login.html';
}
