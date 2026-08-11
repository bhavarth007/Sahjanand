/* ═══════════════════════════════════════════════════════════════
   admin.js  —  Admin User Management Panel
   ═══════════════════════════════════════════════════════════════ */

const ADMIN_API = window.API || 'http://localhost:8000';

let adminUsers = [];
let adminLoaded = false;

// ═══════════════════════════════════════════════════════════════
// Init — called when admin section is opened
// ═══════════════════════════════════════════════════════════════
async function initAdmin() {
  if (adminLoaded) return;
  adminLoaded = true;
  await loadAdminUsers();
  bindAdminSearch();
}

// ═══════════════════════════════════════════════════════════════
// Load users from API
// ═══════════════════════════════════════════════════════════════
async function loadAdminUsers() {
  const token = localStorage.getItem('sahjanand_token');
  try {
    const res = await fetch(`${ADMIN_API}/api/admin/users`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (res.status === 403) {
      document.getElementById('adminUsersBody').innerHTML =
        `<tr><td colspan="6"><div class="empty-state"><i class="fa-solid fa-lock"></i><p>Admin access required.</p></div></td></tr>`;
      return;
    }
    if (!res.ok) return;
    adminUsers = await res.json();
    renderAdminUsers();
  } catch (e) {
    console.warn('[admin] load failed', e);
  }
}

// ═══════════════════════════════════════════════════════════════
// Render user table
// ═══════════════════════════════════════════════════════════════
function renderAdminUsers(filter = '') {
  const tbody = document.getElementById('adminUsersBody');
  if (!tbody) return;

  const lower = filter.toLowerCase();
  const visible = adminUsers.filter(u =>
    !lower ||
    (u.full_name || '').toLowerCase().includes(lower) ||
    u.email.toLowerCase().includes(lower)
  );

  if (!visible.length) {
    tbody.innerHTML = `<tr><td colspan="6"><div class="empty-state"><i class="fa-solid fa-users-slash"></i><p>No users found.</p></div></td></tr>`;
    return;
  }

  tbody.innerHTML = visible.map(u => {
    const name     = u.full_name || u.email;
    const initials = adminGetInitials(name);
    const badge    = u.is_admin ? '<span class="admin-badge">Admin</span>' : '';
    return `
    <tr data-uid="${u.id}">
      <td>
        <div class="admin-user-cell">
          <div class="admin-user-avatar">${initials}</div>
          <div class="admin-user-meta">
            <div class="admin-user-name">${escAdmin(name)} ${badge}</div>
            <div class="admin-user-email">${escAdmin(u.email)}</div>
          </div>
        </div>
      </td>
      <td class="admin-td-center">
        <label class="admin-checkbox">
          <input type="checkbox" ${u.can_view_sales ? 'checked' : ''}
                 onchange="updateAccess(${u.id}, 'can_view_sales', this.checked)" />
          <span class="admin-check-mark"></span>
        </label>
      </td>
      <td class="admin-td-center">
        <label class="admin-checkbox">
          <input type="checkbox" ${u.can_view_reminders ? 'checked' : ''}
                 onchange="updateAccess(${u.id}, 'can_view_reminders', this.checked)" />
          <span class="admin-check-mark"></span>
        </label>
      </td>
      <td class="admin-td-center">
        <label class="admin-checkbox">
          <input type="checkbox" ${u.can_view_samples ? 'checked' : ''}
                 onchange="updateAccess(${u.id}, 'can_view_samples', this.checked)" />
          <span class="admin-check-mark"></span>
        </label>
      </td>
      <td class="admin-td-center">
        <label class="admin-checkbox">
          <input type="checkbox" ${u.can_view_chat ? 'checked' : ''}
                 onchange="updateAccess(${u.id}, 'can_view_chat', this.checked)" />
          <span class="admin-check-mark"></span>
        </label>
      </td>
      <td class="admin-td-center">
        <label class="admin-checkbox">
          <input type="checkbox" ${u.chat_can_send ? 'checked' : ''}
                 onchange="updateAccess(${u.id}, 'chat_can_send', this.checked)" />
          <span class="admin-check-mark"></span>
        </label>
      </td>
    </tr>`;
  }).join('');
}

// ═══════════════════════════════════════════════════════════════
// Update a user's access permission
// ═══════════════════════════════════════════════════════════════
async function updateAccess(uid, field, value) {
  const token = localStorage.getItem('sahjanand_token');
  try {
    const res = await fetch(`${ADMIN_API}/api/admin/users/${uid}/access`, {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ [field]: value }),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      showAdminToast(err.detail || 'Update failed', 'error');
      // Revert checkbox
      const row = document.querySelector(`tr[data-uid="${uid}"]`);
      if (row) {
        const inputs = row.querySelectorAll('input[type=checkbox]');
        const fields = ['can_view_sales', 'can_view_reminders', 'can_view_samples', 'can_view_chat', 'chat_can_send'];
        const idx = fields.indexOf(field);
        if (idx >= 0 && inputs[idx]) inputs[idx].checked = !value;
      }
      return;
    }
    // Update local state
    const u = adminUsers.find(x => x.id === uid);
    if (u) u[field] = value;
    showAdminToast(`Permission updated`, 'success');
  } catch {
    showAdminToast('Network error', 'error');
  }
}

// ═══════════════════════════════════════════════════════════════
// Search
// ═══════════════════════════════════════════════════════════════
function bindAdminSearch() {
  const input = document.getElementById('adminUserSearch');
  if (input) {
    input.addEventListener('input', () => renderAdminUsers(input.value));
  }
}

// ═══════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════
function escAdmin(str) {
  if (!str) return '';
  return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;')
    .replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function adminGetInitials(name) {
  const parts = (name || '').trim().split(' ').filter(Boolean);
  if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
  return (name || 'U').substring(0, 2).toUpperCase();
}

function showAdminToast(msg, type = 'info') {
  const colors = { info: '#667781', success: '#25d366', error: '#c0392b' };
  const el = document.createElement('div');
  el.textContent = msg;
  Object.assign(el.style, {
    position: 'fixed', bottom: '80px', left: '50%', transform: 'translateX(-50%)',
    background: colors[type] || '#667781', color: '#fff',
    padding: '8px 20px', borderRadius: '20px', fontSize: '.85rem',
    zIndex: '9998', boxShadow: '0 2px 10px rgba(0,0,0,.2)',
    fontFamily: 'inherit', pointerEvents: 'none',
  });
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 2800);
}

// Expose
window.initAdmin   = initAdmin;
window.updateAccess = updateAccess;


// ═══════════════════════════════════════════════════════════════
// CRUD: User list in Profile section (admin only)
// ═══════════════════════════════════════════════════════════════
let crudUsers = [];
let crudLoaded = false;
let deleteTargetId = null;

function initAdminCrud() {
  if (crudLoaded) return;
  crudLoaded = true;
  // Show the panel
  const panel = document.getElementById('adminCrudPanel');
  if (panel) panel.style.display = '';
  loadCrudUsers();
}

async function loadCrudUsers() {
  const token = localStorage.getItem('sahjanand_token');
  try {
    const res = await fetch(`${ADMIN_API}/api/admin/users`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) return;
    crudUsers = await res.json();
    renderCrudUsers();
  } catch (e) {
    console.warn('[admin-crud] load failed', e);
  }
}

function renderCrudUsers() {
  const tbody = document.getElementById('adminCrudUsersBody');
  if (!tbody) return;

  if (!crudUsers.length) {
    tbody.innerHTML = `<tr><td colspan="4"><div class="empty-state"><i class="fa-solid fa-users-slash"></i><p>No users found.</p></div></td></tr>`;
    return;
  }

  tbody.innerHTML = crudUsers.map((u, i) => {
    const name = u.full_name || '—';
    const initials = adminGetInitials(u.full_name || u.email);
    return `
    <tr>
      <td>${i + 1}</td>
      <td>
        <div class="admin-user-cell">
          <div class="admin-user-avatar">${initials}</div>
          <span>${escAdmin(name)}</span>
        </div>
      </td>
      <td>${escAdmin(u.email)}</td>
      <td class="admin-td-center">
        <button class="admin-action-btn edit" title="Edit" onclick="openEditUserModal(${u.id})">
          <i class="fa-solid fa-pen"></i>
        </button>
        <button class="admin-action-btn delete" title="Delete" onclick="openDeleteModal(${u.id}, '${escAdmin(u.full_name || u.email)}')">
          <i class="fa-solid fa-trash"></i>
        </button>
      </td>
    </tr>`;
  }).join('');
}

// ── Add User Modal ──────────────────────────────────────────────
function openAddUserModal() {
  document.getElementById('userModalTitle').textContent = 'Add New User';
  document.getElementById('userModalId').value = '';
  document.getElementById('userModalName').value = '';
  document.getElementById('userModalDesignation').value = '';
  document.getElementById('userModalEmail').value = '';
  document.getElementById('userModalPassword').value = '';
  document.getElementById('userModalPassword').required = true;
  document.getElementById('userModalPwdLabel').textContent = 'Password';
  document.getElementById('userModalSubmitBtn').innerHTML = '<i class="fa-solid fa-user-plus"></i> Create';
  document.getElementById('userModal').style.display = 'flex';
}

// ── Edit User Modal ─────────────────────────────────────────────
function openEditUserModal(uid) {
  const user = crudUsers.find(u => u.id === uid);
  if (!user) return;
  document.getElementById('userModalTitle').textContent = 'Edit User';
  document.getElementById('userModalId').value = uid;
  document.getElementById('userModalName').value = user.full_name || '';
  document.getElementById('userModalDesignation').value = user.designation || '';
  document.getElementById('userModalEmail').value = user.email || '';
  document.getElementById('userModalPassword').value = '';
  document.getElementById('userModalPassword').required = false;
  document.getElementById('userModalPwdLabel').textContent = 'New Password (leave blank to keep)';
  document.getElementById('userModalSubmitBtn').innerHTML = '<i class="fa-solid fa-check"></i> Save';
  document.getElementById('userModal').style.display = 'flex';
}

function closeUserModal() {
  document.getElementById('userModal').style.display = 'none';
}

// ── Submit (create or edit) ─────────────────────────────────────
async function submitUserForm(e) {
  e.preventDefault();
  const token = localStorage.getItem('sahjanand_token');
  const uid   = document.getElementById('userModalId').value;
  const name  = document.getElementById('userModalName').value.trim();
  const designation = document.getElementById('userModalDesignation').value.trim();
  const email = document.getElementById('userModalEmail').value.trim();
  const pwd   = document.getElementById('userModalPassword').value;

  const isEdit = !!uid;
  const url    = isEdit ? `${ADMIN_API}/api/admin/users/${uid}` : `${ADMIN_API}/api/admin/users`;
  const method = isEdit ? 'PATCH' : 'POST';

  const body = { full_name: name, email: email, designation: designation || null };
  if (pwd) body.password = pwd;

  try {
    const res = await fetch(url, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      showAdminToast(err.detail || 'Operation failed', 'error');
      return;
    }
    showAdminToast(isEdit ? 'User updated' : 'User created', 'success');
    closeUserModal();
    crudLoaded = false;
    adminLoaded = false;
    loadCrudUsers();
    loadAdminUsers();   // refresh access table too
  } catch {
    showAdminToast('Network error', 'error');
  }
}

// ── Delete User Modal ───────────────────────────────────────────
function openDeleteModal(uid, name) {
  deleteTargetId = uid;
  document.getElementById('deleteUserName').textContent = name;
  document.getElementById('deleteModal').style.display = 'flex';
}

function closeDeleteModal() {
  deleteTargetId = null;
  document.getElementById('deleteModal').style.display = 'none';
}

async function confirmDeleteUser() {
  if (!deleteTargetId) return;
  const token = localStorage.getItem('sahjanand_token');
  try {
    const res = await fetch(`${ADMIN_API}/api/admin/users/${deleteTargetId}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      showAdminToast(err.detail || 'Delete failed', 'error');
      return;
    }
    showAdminToast('User deleted', 'success');
    closeDeleteModal();
    crudLoaded = false;
    adminLoaded = false;
    loadCrudUsers();
    loadAdminUsers();
  } catch {
    showAdminToast('Network error', 'error');
  }
}

// Expose globally
window.openAddUserModal   = openAddUserModal;
window.openEditUserModal  = openEditUserModal;
window.closeUserModal     = closeUserModal;
window.submitUserForm     = submitUserForm;
window.openDeleteModal    = openDeleteModal;
window.closeDeleteModal   = closeDeleteModal;
window.confirmDeleteUser  = confirmDeleteUser;
window.initAdminCrud      = initAdminCrud;
