// User Management JavaScript

let allUsers = [];
let currentFilter = 'all';

document.addEventListener('DOMContentLoaded', function () {
  setupEventListeners();
  loadUsers();
});

function setupEventListeners() {
  const searchInput = document.getElementById('searchInput');
  if (searchInput) {
    searchInput.addEventListener('input', filterUsers);
  }

  const filterButtons = document.querySelectorAll('.filter-btn');
  filterButtons.forEach((btn) => {
    btn.addEventListener('click', function () {
      filterButtons.forEach((b) => b.classList.remove('active'));
      this.classList.add('active');
      currentFilter = this.dataset.filter;
      filterUsers();
    });
  });

  const addUserBtn = document.getElementById('addUserBtn');
  if (addUserBtn) {
    addUserBtn.addEventListener('click', showAddUserModal);
  }
}

async function loadUsers() {
  try {
    const pathParts = window.location.pathname.split('/');
    const panelPath = pathParts[1];

    const res = await fetch(`/${panelPath}/user_management/api/users`);
    const data = await res.json();

    if (!data.success) {
      showError('Failed to load users');
      return;
    }

    // 1) دریافت لیست
    allUsers = data.users || [];

    // 2) آپدیت آمار و تعداد Problematic (بدون پاپ‌آپ)
    updateStats();
    updateProblemBadge();

    // 3) رندر طبق فیلتر فعلی و سرچ
    filterUsers();
  } catch (err) {
    console.error('Error loading users:', err);
    showError('Error loading users');
  }
}

function updateProblemBadge() {
  const el = document.getElementById('problemCount');
  if (!el) return;
  const count = allUsers.filter(
    (u) => !!u.problematic && u.role !== 'admin'
  ).length;
  el.textContent = String(count);
  el.style.display = count > 0 ? 'inline-block' : 'none';
}

// ---- Create User modal ----
function showAddUserModal() {
  const randomPass = generatePassword(16);

  Swal.fire({
    title:
      '<div style="display:flex;align-items:center;gap:10px;justify-content:center;"><i class="fas fa-user-plus" style="color:#667eea;"></i><span>Add New User</span></div>',
    html: `
      <style>
        .modal-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:15px;text-align:left}
        .modal-grid-full{grid-column:1/-1}
        .form-label{display:block;margin-bottom:6px;font-weight:500;font-size:14px;color:#374151}
        .form-input{width:100%;padding:10px 12px;border:1px solid #d1d5db;border-radius:8px;font-size:14px;transition:all .2s}
        .form-input:focus{outline:none;border-color:#667eea;box-shadow:0 0 0 3px rgba(102,126,234,.1)}
        .password-group{display:flex;gap:8px;align-items:center}
        .refresh-btn{padding:10px 14px;background:#667eea;color:white;border:none;border-radius:8px;cursor:pointer;transition:all .2s;flex-shrink:0}
        .refresh-btn:hover{background:#5568d3;transform:scale(1.05)}
        @media (max-width:600px){.modal-grid{grid-template-columns:1fr}}
      </style>
      <div class="modal-grid">
        <div class="modal-grid-full">
          <label class="form-label"><i class="fas fa-user"></i> Username</label>
          <input id="swal-username" class="form-input" placeholder="Enter username" autocomplete="off">
        </div>
        <div class="modal-grid-full">
          <label class="form-label"><i class="fas fa-key"></i> Password</label>
          <div class="password-group">
            <input id="swal-password" class="form-input" value="${randomPass}" autocomplete="off">
            <button type="button" onclick="document.getElementById('swal-password').value = generatePassword(16)" class="refresh-btn">
              <i class="fas fa-sync-alt"></i>
            </button>
          </div>
        </div>
        <div>
          <label class="form-label"><i class="fas fa-database"></i> Traffic Limit (GB)</label>
          <input id="swal-traffic" type="number" class="form-input" value="50" min="1">
        </div>
        <div>
          <label class="form-label"><i class="fas fa-plug"></i> Max Connections</label>
          <input id="swal-connections" type="number" class="form-input" value="2" min="1">
        </div>
        <div>
          <label class="form-label"><i class="fas fa-tachometer-alt"></i> Speed (Mbps)</label>
          <input id="swal-speed" type="number" class="form-input" value="0" min="0" placeholder="0 = unlimited">
        </div>
        <div>
          <label class="form-label"><i class="fas fa-calendar"></i> Expiry (Days)</label>
          <input id="swal-expiry" type="number" class="form-input" value="30" min="1">
        </div>
      </div>
    `,
    width: '700px',
    showCancelButton: true,
    confirmButtonText: '<i class="fas fa-check"></i> Create User',
    cancelButtonText: '<i class="fas fa-times"></i> Cancel',
    confirmButtonColor: '#667eea',
    cancelButtonColor: '#6b7280',
    preConfirm: () => {
      const username = document.getElementById('swal-username').value.trim();
      const password = document.getElementById('swal-password').value;
      const traffic = document.getElementById('swal-traffic').value;
      const connections = document.getElementById('swal-connections').value;
      const speed = document.getElementById('swal-speed').value;
      const expiry = document.getElementById('swal-expiry').value;

      if (!username) {
        Swal.showValidationMessage('Username is required');
        return false;
      }

      return {
        username,
        password,
        traffic_limit: traffic,
        max_connections: connections,
        download_speed: speed,
        expiry_days: expiry,
      };
    },
  }).then((result) => {
    if (result.isConfirmed) {
      createUser(result.value);
    }
  });
}

async function createUser(userData) {
  try {
    Swal.fire({
      title: 'Creating User...',
      html: 'Please wait while we create the user',
      allowOutsideClick: false,
      didOpen: () => Swal.showLoading(),
    });

    const pathParts = window.location.pathname.split('/');
    const panelPath = pathParts[1];

    const res = await fetch(`/${panelPath}/user_management/api/users`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(userData),
    });

    const data = await res.json();
    if (!data.success) {
      return Swal.fire({ icon: 'error', title: 'Error', text: data.message });
    }

    Swal.fire({
      icon: 'success',
      title: 'User Created!',
      html: `
        <div style="text-align:left;background:#f8f9fa;padding:15px;border-radius:8px;margin-top:15px;">
          <p><strong>Username:</strong> ${data.user.username}</p>
          <p><strong>Password:</strong> <code style="background:#e9ecef;padding:2px 6px;border-radius:4px;">${data.user.password}</code></p>
          <p><strong>Expires:</strong> ${data.user.expires_at}</p>
        </div>
        <p style="color:#dc3545;margin-top:15px;"><i class="fas fa-exclamation-triangle"></i> Save these credentials!</p>
      `,
      confirmButtonText: 'OK',
    }).then(loadUsers);
  } catch (err) {
    Swal.fire({ icon: 'error', title: 'Error', text: 'Failed to create user: ' + err.message });
  }
}

// ---- Edit user modal (username read-only فعلاً) ----
function editUser(userId) {
  const user = allUsers.find((u) => u.id === userId);
  if (!user) return;

  Swal.fire({
    title: `<div style="display:flex;align-items:center;gap:10px;justify-content:center;">
              <i class="fas fa-edit" style="color:#667eea;"></i>
              <span>Edit User: ${user.username}</span>
            </div>`,
    html: `
      <style>
        .modal-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:15px;text-align:left}
        .modal-grid-full{grid-column:1/-1}
        .form-label{display:block;margin-bottom:6px;font-weight:500;font-size:14px;color:#374151}
        .form-input{width:100%;padding:10px 12px;border:1px solid #d1d5db;border-radius:8px;font-size:14px}
        .password-group{display:flex;gap:8px}
        .refresh-btn{padding:10px 14px;background:#667eea;color:white;border:none;border-radius:8px;cursor:pointer;flex-shrink:0}
      </style>
      <div class="modal-grid">
        <div class="modal-grid-full">
          <label class="form-label"><i class="fas fa-user"></i> Username</label>
          <input class="form-input" value="${user.username}" disabled>
        </div>
        <div class="modal-grid-full">
          <label class="form-label"><i class="fas fa-key"></i> New Password (leave empty to keep current)</label>
          <div class="password-group">
            <input id="edit-password" class="form-input" placeholder="Leave empty to keep current">
            <button type="button" onclick="document.getElementById('edit-password').value = generatePassword(16)" class="refresh-btn">
              <i class="fas fa-sync-alt"></i>
            </button>
          </div>
        </div>
        <div>
          <label class="form-label"><i class="fas fa-database"></i> Traffic Limit (GB)</label>
          <input id="edit-traffic" type="number" class="form-input" value="${user.limits?.traffic_limit_gb || 50}">
        </div>
        <div>
          <label class="form-label"><i class="fas fa-plug"></i> Max Connections</label>
          <input id="edit-connections" type="number" class="form-input" value="${user.limits?.max_connections || 2}">
        </div>
        <div>
          <label class="form-label"><i class="fas fa-tachometer-alt"></i> Speed (Mbps)</label>
          <input id="edit-speed" type="number" class="form-input" value="${user.limits?.download_speed_mbps || 0}">
        </div>
        <div>
          <label class="form-label"><i class="fas fa-calendar"></i> Extend Expiry (Days)</label>
          <input id="edit-expiry" type="number" class="form-input" value="30">
        </div>
        <div class="modal-grid-full">
          <label style="display:flex;align-items:center;gap:8px;cursor:pointer;">
            <input id="edit-active" type="checkbox" ${user.is_active ? 'checked' : ''} style="width:18px;height:18px;">
            <span class="form-label" style="margin:0;">Active</span>
          </label>
        </div>
      </div>
    `,
    width: '700px',
    showCancelButton: true,
    confirmButtonText: '<i class="fas fa-save"></i> Update',
    cancelButtonText: '<i class="fas fa-times"></i> Cancel',
    confirmButtonColor: '#667eea',
    preConfirm: () => {
      const password = document.getElementById('edit-password').value;
      return {
        password: password || undefined,
        traffic_limit: document.getElementById('edit-traffic').value,
        max_connections: document.getElementById('edit-connections').value,
        download_speed: document.getElementById('edit-speed').value,
        expiry_days: document.getElementById('edit-expiry').value,
        is_active: document.getElementById('edit-active').checked,
      };
    },
  }).then(async (result) => {
    if (!result.isConfirmed) return;
    try {
      const pathParts = window.location.pathname.split('/');
      const panelPath = pathParts[1];
      const res = await fetch(`/${panelPath}/user_management/api/users/${userId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(result.value),
      });
      const data = await res.json();
      if (!data.success) return Swal.fire('Error', data.message, 'error');
      Swal.fire('Updated!', 'User updated successfully', 'success');
      loadUsers();
    } catch (err) {
      Swal.fire('Error', 'Failed to update user', 'error');
    }
  });
}

// ---- Reset password (uses PUT password) ----
async function resetPassword(userId) {
  const user = allUsers.find((u) => u.id === userId);
  if (!user) return;

  const newPassword = generatePassword(16);

  Swal.fire({
    title: 'Reset Password?',
    html: `Generate new password for <strong>${user.username}</strong>?<br><br>New password: <code style="background:#f3f4f6;padding:4px 8px;border-radius:4px;">${newPassword}</code>`,
    icon: 'question',
    showCancelButton: true,
    confirmButtonText: 'Yes, reset it!',
    cancelButtonText: 'Cancel',
  }).then(async (result) => {
    if (!result.isConfirmed) return;
    try {
      const pathParts = window.location.pathname.split('/');
      const panelPath = pathParts[1];

      const res = await fetch(`/${panelPath}/user_management/api/users/${userId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password: newPassword }),
      });
      const data = await res.json();
      if (!data.success) return Swal.fire('Error', data.message, 'error');

      Swal.fire({
        icon: 'success',
        title: 'Password Reset!',
        html: `New password: <code style="background:#f3f4f6;padding:4px 8px;border-radius:4px;">${newPassword}</code><br><br><span style="color:#dc3545;">Save this password!</span>`,
      });
    } catch (err) {
      Swal.fire('Error', 'Failed to reset password', 'error');
    }
  });
}

// ---- Repair (always available) ----
async function repairUser(userId) {
  const user = allUsers.find((u) => u.id === userId);
  if (!user) return;

  Swal.fire({
    title: 'Repair User?',
    html: `Create/sync Linux user for <strong>${user.username}</strong>?`,
    icon: 'info',
    showCancelButton: true,
    confirmButtonText: 'Yes, repair it!',
    cancelButtonText: 'Cancel',
  }).then(async (result) => {
    if (!result.isConfirmed) return;
    try {
      const pathParts = window.location.pathname.split('/');
      const panelPath = pathParts[1];

      const res = await fetch(`/${panelPath}/user_management/api/users/sync`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'repair_user', user_id: userId }),
      });

      const data = await res.json();
      if (!data.success) return Swal.fire('Error', data.message, 'error');

      Swal.fire({
        icon: 'success',
        title: 'User Repaired!',
        html: data.password
          ? `New password: <code style="background:#f3f4f6;padding:4px 8px;border-radius:4px;">${data.password}</code>`
          : 'User synced successfully.',
      });
      loadUsers();
    } catch (err) {
      Swal.fire('Error', 'Failed to repair user', 'error');
    }
  });
}

// ---- Delete ----
function deleteUser(userId) {
  const user = allUsers.find((u) => u.id === userId);
  if (!user) return;

  Swal.fire({
    title: 'Delete User?',
    html: `Are you sure you want to delete <strong>${user.username}</strong>?<br><br>
           <span style="color:#dc3545;">⚠️ This will also delete the Linux user and cannot be undone!</span>`,
    icon: 'warning',
    showCancelButton: true,
    confirmButtonColor: '#dc3545',
    confirmButtonText: 'Yes, delete it!',
    cancelButtonText: 'Cancel',
  }).then(async (result) => {
    if (!result.isConfirmed) return;
    try {
      const pathParts = window.location.pathname.split('/');
      const panelPath = pathParts[1];

      const res = await fetch(`/${panelPath}/user_management/api/users/${userId}`, {
        method: 'DELETE',
      });
      const data = await res.json();
      if (!data.success) return Swal.fire('Error', data.message, 'error');

      Swal.fire('Deleted!', 'User has been deleted', 'success');
      loadUsers();
    } catch (err) {
      Swal.fire('Error', 'Failed to delete user', 'error');
    }
  });
}

// ---- Helpers ----
function generatePassword(length) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*';
  let password = '';
  for (let i = 0; i < length; i++) {
    password += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return password;
}

function updateStats() {
  const total = allUsers.filter((u) => u.role !== 'admin').length;
  const active = allUsers.filter((u) => u.is_active && u.role !== 'admin').length;
  const inactive = total - active;
  const admins = allUsers.filter((u) => u.role === 'admin').length;

  document.getElementById('totalUsers').textContent = total;
  document.getElementById('activeUsers').textContent = active;
  document.getElementById('inactiveUsers').textContent = inactive;
  document.getElementById('adminUsers').textContent = admins;
}

function filterUsers() {
  const searchTerm = document.getElementById('searchInput').value.toLowerCase().trim();
  let filtered = [...allUsers];

  if (currentFilter === 'active') {
    filtered = filtered.filter((u) => u.is_active && u.role !== 'admin');
  } else if (currentFilter === 'inactive') {
    filtered = filtered.filter((u) => !u.is_active && u.role !== 'admin');
  } else if (currentFilter === 'admin') {
    filtered = filtered.filter((u) => u.role === 'admin');
  } else if (currentFilter === 'problematic') {
    filtered = filtered.filter((u) => !!u.problematic && u.role !== 'admin');
  }

  if (searchTerm) {
    filtered = filtered.filter(
      (u) =>
        u.username.toLowerCase().includes(searchTerm) ||
        u.role.toLowerCase().includes(searchTerm)
    );
  }

  displayUsers(filtered);
}

function displayUsers(users) {
  const tbody = document.getElementById('usersTableBody');

  if (!users || users.length === 0) {
    tbody.innerHTML = `
      <tr>
        <td colspan="8" class="text-center">
          <div style="padding:40px;color:var(--text-secondary);">
            <i class="fas fa-users" style="font-size:48px;margin-bottom:16px;opacity:.3;"></i>
            <p>No users found</p>
          </div>
        </td>
      </tr>
    `;
    return;
  }

  tbody.innerHTML = users
    .map((user) => {
      const isAdmin = user.role === 'admin';
      const problematic = !!user.problematic;

      return `
      <tr ${problematic ? 'style="background: rgba(239,68,68,.06)"' : ''}>
        <td>
          <div style="display:flex;align-items:center;gap:10px;">
            <div style="width:36px;height:36px;border-radius:8px;background:${getRoleColor(
              user.role
            )};display:flex;align-items:center;justify-content:center;color:white;font-weight:600;">
              ${user.username?.charAt(0)?.toUpperCase() || '?'}
            </div>
            <div>
              <strong>${user.username}</strong>
              ${problematic ? '<br><span style="font-size:11px;color:#ef4444;"><i class="fas fa-exclamation-triangle"></i> Problematic</span>' : ''}
              ${
                user.sync_status && !user.sync_status.synced
                  ? '<br><span style="font-size:11px;color:#ef4444;"><i class="fas fa-link-slash"></i> Out of sync</span>'
                  : ''
              }
            </div>
          </div>
        </td>
        <td>
          <span class="badge badge-${user.role}">
            <i class="fas fa-${isAdmin ? 'user-shield' : 'user'}"></i>
            ${user.role}
          </span>
        </td>
        <td>
          <span class="badge badge-${user.is_active && !user?.limits?.is_expired ? 'active' : 'inactive'}">
            <i class="fas fa-${user.is_active && !user?.limits?.is_expired ? 'check-circle' : 'times-circle'}"></i>
            ${user?.limits?.is_expired ? 'Expired' : user.is_active ? 'Active' : 'Inactive'}
          </span>
        </td>
        <td>${user.created_at}</td>
        <td>${user.last_login}</td>
        <td>
          ${
            isAdmin
              ? '<span style="color:var(--text-secondary);">N/A</span>'
              : user.limits
              ? `
              <div style="font-size:12px;">
                <div>${user.limits.traffic_used_gb} / ${user.limits.traffic_limit_gb} GB</div>
                <div style="margin-top:4px;background:var(--bg-secondary);height:6px;border-radius:3px;overflow:hidden;">
                  <div style="width:${Math.min(
                    (user.limits.traffic_used_gb / user.limits.traffic_limit_gb) * 100,
                    100
                  )}%;height:100%;background:${getTrafficColor(
                  user.limits.traffic_used_gb,
                  user.limits.traffic_limit_gb
                )};"></div>
                </div>
                ${
                  user.limits.expires_at
                    ? `<div style="margin-top:4px;color:var(--text-secondary);">Expires: ${user.limits.expires_at}</div>`
                    : ''
                }
              </div>`
              : '-'
          }
        </td>
        <td>
          ${
            isAdmin
              ? '<span style="color:var(--text-secondary);">N/A</span>'
              : `${user.current_connections ?? 0} / ${user.max_connections ?? '-'}`
          }
        </td>
        <td>
          <div class="action-buttons">
            <button class="btn-action edit" onclick="editUser(${user.id})" title="Edit">
              <i class="fas fa-edit"></i>
            </button>
            ${
              !isAdmin
                ? `
              <button class="btn-action reset" onclick="resetPassword(${user.id})" title="Reset Password">
                <i class="fas fa-key"></i>
              </button>
              <button class="btn-action repair" onclick="repairUser(${user.id})" title="Repair User">
                <i class="fas fa-wrench"></i>
              </button>
              <button class="btn-action delete" onclick="deleteUser(${user.id})" title="Delete">
                <i class="fas fa-trash"></i>
              </button>`
                : `
              <button class="btn-action view" onclick="editUser(${user.id})" title="View">
                <i class="fas fa-eye"></i>
              </button>`
            }
          </div>
        </td>
      </tr>`;
    })
    .join('');
}

function getRoleColor(role) {
  return role === 'admin'
    ? 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)'
    : 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)';
}

function getTrafficColor(used, limit) {
  const percentage = (used / (limit || 1)) * 100;
  if (percentage >= 90) return '#ef4444';
  if (percentage >= 75) return '#f59e0b';
  return '#10b981';
}

function showError(message) {
  const tbody = document.getElementById('usersTableBody');
  tbody.innerHTML = `
    <tr>
      <td colspan="8" class="text-center">
        <div style="padding:40px;color:var(--danger);">
          <i class="fas fa-exclamation-triangle" style="font-size:48px;margin-bottom:16px;"></i>
          <p>${message}</p>
        </div>
      </td>
    </tr>
  `;
}
