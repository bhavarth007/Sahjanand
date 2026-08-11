const API = '';  // empty = same origin (localhost:8000 serves both)

// ── Already logged in → go to dashboard ─────────────────
if (localStorage.getItem('sahjanand_token')) {
  window.location.replace('/dashboard');
}

// ── Tab switching ────────────────────────────────────────
function switchTab(tab) {
  const isLogin = tab === 'login';

  document.getElementById('loginForm').style.display    = isLogin ? 'block' : 'none';
  document.getElementById('registerForm').style.display = isLogin ? 'none'  : 'block';

  document.getElementById('tabLogin').classList.toggle('active',    isLogin);
  document.getElementById('tabRegister').classList.toggle('active', !isLogin);

  // Clear alerts
  document.getElementById('alertBox').classList.remove('show');
  document.getElementById('successBox').classList.remove('show');
}

// ── Password visibility ──────────────────────────────────
document.getElementById('togglePwd').addEventListener('click', () => {
  const input = document.getElementById('loginPassword');
  const icon  = document.getElementById('eyeIcon');
  const hidden = input.type === 'password';
  input.type     = hidden ? 'text' : 'password';
  icon.className = hidden ? 'fa-regular fa-eye-slash' : 'fa-regular fa-eye';
});

document.getElementById('toggleRegPwd').addEventListener('click', () => {
  const input = document.getElementById('regPassword');
  const icon  = document.getElementById('eyeIconReg');
  const hidden = input.type === 'password';
  input.type     = hidden ? 'text' : 'password';
  icon.className = hidden ? 'fa-regular fa-eye-slash' : 'fa-regular fa-eye';
});

// ── Helpers ──────────────────────────────────────────────
function showError(msg) {
  const box = document.getElementById('alertBox');
  document.getElementById('alertMsg').textContent = msg;
  box.classList.add('show');
  document.getElementById('successBox').classList.remove('show');
}

function showSuccess(msg) {
  const box = document.getElementById('successBox');
  document.getElementById('successMsg').textContent = msg;
  box.classList.add('show');
  document.getElementById('alertBox').classList.remove('show');
}

function clearErrors() {
  document.querySelectorAll('.form-group').forEach(g => g.classList.remove('has-error'));
  document.getElementById('alertBox').classList.remove('show');
  document.getElementById('successBox').classList.remove('show');
}

function setError(groupId) {
  document.getElementById(groupId)?.classList.add('has-error');
}

// ── LOGIN ────────────────────────────────────────────────
document.getElementById('loginForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  clearErrors();

  const email    = document.getElementById('loginEmail').value.trim();
  const password = document.getElementById('loginPassword').value;
  const btn      = document.getElementById('loginBtn');

  let valid = true;
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) { setError('loginEmailGroup');    valid = false; }
  if (!password)                                             { setError('loginPasswordGroup'); valid = false; }
  if (!valid) return;

  btn.classList.add('loading');

  try {
    const res  = await fetch(`${API}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });

    let data;
    try {
      data = await res.json();
    } catch {
      throw new Error('Server error. Please try again later.');
    }

    if (!res.ok) throw new Error(data.detail || 'Invalid email or password.');

    localStorage.setItem('sahjanand_token', data.access_token);
    localStorage.setItem('sahjanand_user', JSON.stringify(data.user));
    window.location.replace('/dashboard');

  } catch (err) {
    showError(err.message || 'Something went wrong. Please try again.');
    btn.classList.remove('loading');
  }
});

// ── REGISTER ─────────────────────────────────────────────
document.getElementById('registerForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  clearErrors();

  const fullName  = document.getElementById('regName').value.trim();
  const email     = document.getElementById('regEmail').value.trim();
  const password  = document.getElementById('regPassword').value;
  const confirm   = document.getElementById('regConfirm').value;
  const btn       = document.getElementById('registerBtn');

  let valid = true;
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) { setError('regEmailGroup');    valid = false; }
  if (!password || password.length < 6)                     { setError('regPasswordGroup'); valid = false; }
  if (!confirm || confirm !== password)                      { setError('regConfirmGroup');  valid = false; }
  if (!valid) return;

  btn.classList.add('loading');

  try {
    const res  = await fetch(`${API}/api/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, full_name: fullName }),
    });

    let data;
    try {
      data = await res.json();
    } catch {
      throw new Error('Server error. Please try again later.');
    }

    if (!res.ok) throw new Error(data.detail || 'Registration failed. Please try again.');

    showSuccess('Account created successfully! You can now sign in.');
    document.getElementById('registerForm').reset();
    setTimeout(() => switchTab('login'), 2000);

  } catch (err) {
    showError(err.message || 'Registration failed. Please try again.');
  } finally {
    btn.classList.remove('loading');
  }
});
