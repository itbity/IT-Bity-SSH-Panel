// User Management JavaScript

let allUsers = [];
let currentFilter = 'all';

document.addEventListener('DOMContentLoaded', function() {
    // Load users on page load
    loadUsers();
    
    // Setup event listeners
    setupEventListeners();
});

function setupEventListeners() {
    // Search functionality
    const searchInput = document.getElementById('searchInput');
    if (searchInput) {
        searchInput.addEventListener('input', filterUsers);
    }
    
    // Filter buttons
    const filterButtons = document.querySelectorAll('.filter-btn');
    filterButtons.forEach(btn => {
        btn.addEventListener('click', function() {
            filterButtons.forEach(b => b.classList.remove('active'));
            this.classList.add('active');
            currentFilter = this.dataset.filter;
            filterUsers();
        });
    });
    
    // Add user button
    const addUserBtn = document.getElementById('addUserBtn');
    if (addUserBtn) {
        addUserBtn.addEventListener('click', function() {
            alert('Add User functionality - Coming soon!');
        });
    }
}

async function loadUsers() {
    try {
        const response = await fetch('/user_management/api/users');
        const data = await response.json();
        
        if (data.success) {
            allUsers = data.users;
            updateStats();
            displayUsers(allUsers);
        } else {
            showError('Failed to load users');
        }
    } catch (error) {
        console.error('Error loading users:', error);
        showError('Error loading users');
    }
}

function updateStats() {
    const total = allUsers.length;
    const active = allUsers.filter(u => u.is_active).length;
    const inactive = total - active;
    const admins = allUsers.filter(u => u.role === 'admin').length;
    
    document.getElementById('totalUsers').textContent = total;
    document.getElementById('activeUsers').textContent = active;
    document.getElementById('inactiveUsers').textContent = inactive;
    document.getElementById('adminUsers').textContent = admins;
}

function displayUsers(users) {
    const tbody = document.getElementById('usersTableBody');
    
    if (users.length === 0) {
        tbody.innerHTML = `
            <tr>
                <td colspan="7" class="text-center">
                    <div style="padding: 40px; color: var(--text-secondary);">
                        <i class="fas fa-users" style="font-size: 48px; margin-bottom: 16px; opacity: 0.3;"></i>
                        <p>No users found</p>
                    </div>
                </td>
            </tr>
        `;
        return;
    }
    
    tbody.innerHTML = users.map(user => `
        <tr>
            <td>
                <div style="display: flex; align-items: center; gap: 10px;">
                    <div style="width: 36px; height: 36px; border-radius: 8px; background: ${getRoleColor(user.role)}; display: flex; align-items: center; justify-content: center; color: white; font-weight: 600;">
                        ${user.username.charAt(0).toUpperCase()}
                    </div>
                    <strong>${user.username}</strong>
                </div>
            </td>
            <td>
                <span class="badge badge-${user.role}">
                    <i class="fas fa-${user.role === 'admin' ? 'user-shield' : 'user'}"></i>
                    ${user.role}
                </span>
            </td>
            <td>
                <span class="badge badge-${user.is_active ? 'active' : 'inactive'}">
                    <i class="fas fa-${user.is_active ? 'check-circle' : 'times-circle'}"></i>
                    ${user.is_active ? 'Active' : 'Inactive'}
                </span>
            </td>
            <td>${user.created_at}</td>
            <td>${user.last_login}</td>
            <td>
                ${user.limits ? `
                    <div style="font-size: 12px;">
                        <div>${user.limits.traffic_used_gb} / ${user.limits.traffic_limit_gb} GB</div>
                        <div style="margin-top: 4px; background: var(--bg-secondary); height: 6px; border-radius: 3px; overflow: hidden;">
                            <div style="width: ${Math.min((user.limits.traffic_used_gb / user.limits.traffic_limit_gb) * 100, 100)}%; height: 100%; background: ${getTrafficColor(user.limits.traffic_used_gb, user.limits.traffic_limit_gb)};"></div>
                        </div>
                    </div>
                ` : '-'}
            </td>
            <td>
                <div class="action-buttons">
                    <button class="btn-action edit" onclick="editUser(${user.id})" title="Edit">
                        <i class="fas fa-edit"></i>
                    </button>
                    <button class="btn-action delete" onclick="deleteUser(${user.id})" title="Delete">
                        <i class="fas fa-trash"></i>
                    </button>
                </div>
            </td>
        </tr>
    `).join('');
}

function filterUsers() {
    const searchTerm = document.getElementById('searchInput').value.toLowerCase();
    
    let filtered = allUsers;
    
    // Apply role/status filter
    if (currentFilter !== 'all') {
        if (currentFilter === 'active') {
            filtered = filtered.filter(u => u.is_active);
        } else if (currentFilter === 'inactive') {
            filtered = filtered.filter(u => !u.is_active);
        } else if (currentFilter === 'admin') {
            filtered = filtered.filter(u => u.role === 'admin');
        }
    }
    
    // Apply search filter
    if (searchTerm) {
        filtered = filtered.filter(u => 
            u.username.toLowerCase().includes(searchTerm) ||
            u.role.toLowerCase().includes(searchTerm)
        );
    }
    
    displayUsers(filtered);
}

function getRoleColor(role) {
    return role === 'admin' ? 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)' : 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)';
}

function getTrafficColor(used, limit) {
    const percentage = (used / limit) * 100;
    if (percentage >= 90) return '#ef4444';
    if (percentage >= 75) return '#f59e0b';
    return '#10b981';
}

function editUser(userId) {
    alert(`Edit user ${userId} - Coming soon!`);
    // TODO: Implement edit user modal
}

function deleteUser(userId) {
    const confirmed = confirm('Are you sure you want to delete this user?');
    if (confirmed) {
        alert(`Delete user ${userId} - Coming soon!`);
        // TODO: Implement delete user functionality
    }
}

function showError(message) {
    const tbody = document.getElementById('usersTableBody');
    tbody.innerHTML = `
        <tr>
            <td colspan="7" class="text-center">
                <div style="padding: 40px; color: var(--danger);">
                    <i class="fas fa-exclamation-triangle" style="font-size: 48px; margin-bottom: 16px;"></i>
                    <p>${message}</p>
                </div>
            </td>
        </tr>
    `;
}