const API = 'http://localhost:8000';

// ── Password visibility toggle ──
document.getElementById('togglePwd').addEventListener('click', () => {
  const input = document.getElementById('password');
  const icon  = document.getElementById('eyeIcon');
  const isHidden = input.type === 'password';
  input.type = isHidden ? 'text' : 'password';
  icon.className = isHidden ? 'fa-regular fa-eye-slash' : 'fa-regular fa-eye';
});

// ── Form submission ──
document.getElementById('loginForm').addEventListener('submit', async (e) => {
  e.preventDefault();

  const email    = document.getElementById('email').value.trim();
  const password = document.getElementById('password').value;
  const btn      = document.getElementById('loginBtn');
  const alertBox = document.getElementById('alertBox');
  const alertMsg = document.getElementById('alertMsg');

  // Clear previous errors
  alertBox.classList.remove('show');
  document.getElementById('emailGroup').classList.remove('has-error');
  document.getElementById('passwordGroup').classList.remove('has-error');

  // Client-side validation
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

  // Show loading state
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

    // Save token and user info
    localStorage.setItem('sahjanand_token', data.access_token);
    localStorage.setItem('sahjanand_user', JSON.stringify(data.user));

    // Redirect to dashboard
    window.location.href = 'dashboard.html';

  } catch (err) {
    alertMsg.textContent = err.message || 'Something went wrong. Please try again.';
    alertBox.classList.add('show');
  } finally {
    btn.classList.remove('loading');
  }
});
