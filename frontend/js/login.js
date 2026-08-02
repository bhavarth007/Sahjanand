const API = 'http://localhost:8000';

// ── If already logged in, go straight to dashboard ──────
if (localStorage.getItem('sahjanand_token')) {
  window.location.replace('dashboard.html');
}

// ── Password visibility toggle ───────────────────────────
document.getElementById('togglePwd').addEventListener('click', () => {
  const input = document.getElementById('password');
  const icon  = document.getElementById('eyeIcon');
  const hidden = input.type === 'password';
  input.type      = hidden ? 'text' : 'password';
  icon.className  = hidden ? 'fa-regular fa-eye-slash' : 'fa-regular fa-eye';
});

// ── Form submit ──────────────────────────────────────────
document.getElementById('loginForm').addEventListener('submit', async (e) => {
  e.preventDefault();

  const email    = document.getElementById('email').value.trim();
  const password = document.getElementById('password').value;
  const btn      = document.getElementById('loginBtn');
  const alertBox = document.getElementById('alertBox');
  const alertMsg = document.getElementById('alertMsg');

  // Reset errors
  alertBox.classList.remove('show');
  document.getElementById('emailGroup').classList.remove('has-error');
  document.getElementById('passwordGroup').classList.remove('has-error');

  // Validate
  let valid = true;
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    document.getElementById('emailGroup').classList.add('has-error');
    valid = false;
  }
  if (!password) {
    document.getElementById('passwordGroup').classList.add('has-error');
    valid = false;
  }
  if (!valid) return;

  btn.classList.add('loading');

  try {
    const response = await fetch(`${API}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });

    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.detail || 'Invalid email or password.');
    }

    // Save session
    localStorage.setItem('sahjanand_token', data.access_token);
    localStorage.setItem('sahjanand_user', JSON.stringify(data.user));

    // Go to dashboard — Sales section loads by default
    window.location.replace('dashboard.html');

  } catch (err) {
    alertMsg.textContent = err.message || 'Something went wrong. Please try again.';
    alertBox.classList.add('show');
    btn.classList.remove('loading');
  }
});
