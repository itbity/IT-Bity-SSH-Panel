from flask import Blueprint, render_template, request, jsonify, flash, redirect, url_for
from flask_login import login_required, current_user
from flask_babel import gettext as _
from app import db
from app.models import User, UserLimit
from functools import wraps
from datetime import datetime, timedelta
import subprocess
import secrets
import string
import pwd

user_management_bp = Blueprint('user_management', __name__)

# ------------------------ helpers ------------------------

def admin_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not current_user.is_authenticated or current_user.role != 'admin':
            flash(_('Access denied. Admin privileges required.'), 'error')
            return redirect(url_for('main.dashboard'))
        return f(*args, **kwargs)
    return decorated_function

def generate_random_password(length=16):
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    return ''.join(secrets.choice(alphabet) for _ in range(length))

def get_all_linux_users():
    try:
        linux_users = []
        for user in pwd.getpwall():
            if 1000 <= user.pw_uid < 65534:
                linux_users.append(user.pw_name)
        return linux_users
    except Exception as e:
        print(f"Error getting Linux users: {e}")
        return []

def check_linux_user_exists(username):
    try:
        pwd.getpwnam(username)
        return True
    except KeyError:
        return False

def get_current_connections(username):
    """Return current concurrent SSH connections for the user (placeholder)."""
    try:
        # TODO: implement using `ss -tp | grep 'ssh'` or logs
        return 0
    except Exception:
        return 0

def get_user_traffic(username):
    """Placeholder: wire up vnstat/iptables later."""
    return 0.0

def reset_linux_password(username, new_password):
    try:
        if not check_linux_user_exists(username):
            return False, "Linux user does not exist"
        proc = subprocess.Popen(['sudo', 'chpasswd'], stdin=subprocess.PIPE, text=True)
        proc.communicate(f'{username}:{new_password}')
        return True, "Password updated"
    except Exception as e:
        return False, f"Error resetting password: {e}"

def rename_linux_user(old_username, new_username):
    try:
        if not check_linux_user_exists(old_username):
            return False, "Old Linux user not found"
        if check_linux_user_exists(new_username):
            return False, "New username already exists in Linux"
        subprocess.run(['sudo', 'usermod', '-l', new_username, old_username], check=True)
        subprocess.run(['sudo', 'usermod', '-d', f'/home/{new_username}', '-m', new_username], check=True)
        subprocess.run(['sudo', 'sed', '-i',
                        f's/^Match User {old_username}$/Match User {new_username}/',
                        '/etc/ssh/sshd_config'], check=True)
        try:
            subprocess.run(['sudo', 'systemctl', 'reload', 'ssh'], check=True)
        except subprocess.CalledProcessError:
            try:
                subprocess.run(['sudo', 'systemctl', 'reload', 'sshd'], check=True)
            except subprocess.CalledProcessError:
                pass
        return True, "Linux user renamed"
    except subprocess.CalledProcessError as e:
        return False, f"Failed to rename user: {e}"

def create_linux_user(username, password):
    try:
        if check_linux_user_exists(username):
            return False, "Linux user already exists"
        subprocess.run(['sudo', 'useradd', '-m', '-s', '/bin/false', username], check=True)
        proc = subprocess.Popen(['sudo', 'chpasswd'], stdin=subprocess.PIPE, text=True)
        proc.communicate(f'{username}:{password}')
        ssh_config = f"""
Match User {username}
    PermitTunnel yes
    AllowTcpForwarding yes
    X11Forwarding no
    AllowAgentForwarding no
    ForceCommand /bin/false
"""
        with open('/tmp/ssh_user_config', 'w') as f:
            f.write(ssh_config)
        subprocess.run(['sudo', 'bash', '-c', 'cat /tmp/ssh_user_config >> /etc/ssh/sshd_config'], check=True)
        subprocess.run(['sudo', 'rm', '/tmp/ssh_user_config'], check=True)
        try:
            subprocess.run(['sudo', 'systemctl', 'reload', 'ssh'], check=True)
        except subprocess.CalledProcessError:
            try:
                subprocess.run(['sudo', 'systemctl', 'reload', 'sshd'], check=True)
            except subprocess.CalledProcessError:
                # اگر هیچکدام از سرویس‌ها وجود ندارد، بی‌خیال
                pass
        return True, "User created successfully"
    except subprocess.CalledProcessError as e:
        return False, f"Failed to create user: {str(e)}"
    except Exception as e:
        return False, f"Error: {str(e)}"

def delete_linux_user(username):
    try:
        if not check_linux_user_exists(username):
            return True, "Linux user does not exist"
        # kill all processes to avoid "currently used" error
        subprocess.run(['sudo', 'pkill', '-KILL', '-u', username], check=False)
        subprocess.run(['sudo', 'userdel', '-r', username], check=True)
        subprocess.run(['sudo', 'sed', '-i', f'/^Match User {username}$/,/^$/d', '/etc/ssh/sshd_config'], check=True)
        try:
            subprocess.run(['sudo', 'systemctl', 'reload', 'ssh'], check=True)
        except subprocess.CalledProcessError:
            try:
                subprocess.run(['sudo', 'systemctl', 'reload', 'sshd'], check=True)
            except subprocess.CalledProcessError:
                pass
        return True, "User deleted successfully"
    except subprocess.CalledProcessError as e:
        return False, f"Failed to delete user: {str(e)}"
    except Exception as e:
        return False, f"Error deleting user: {str(e)}"

# ------------------------ routes ------------------------

@user_management_bp.route('/users')
@login_required
@admin_required
def users_page():
    return render_template('user_management.html')

@user_management_bp.route('/api/users', methods=['GET'])
@login_required
@admin_required
def get_users():
    try:
        db_users = User.query.all()
        linux_users = get_all_linux_users()

        users_data = []
        for user in db_users:
            linux_exists = check_linux_user_exists(user.username)

            # base object
            user_data = {
                'id': user.id,
                'username': user.username,
                'role': user.role,
                'is_active': user.is_active,
                'created_at': user.created_at.strftime('%Y-%m-%d %H:%M'),
                'last_login': user.last_login.strftime('%Y-%m-%d %H:%M') if user.last_login else _('Never'),
                'sync_status': {'in_database': True, 'in_linux': linux_exists, 'synced': linux_exists},
            }

            # limits + live stats
            current_conns = 0 if user.role == 'admin' else get_current_connections(user.username)
            over_traffic = False
            is_expired = False
            max_conns = None

            if user.limits:
                current_traffic = get_user_traffic(user.username)
                if current_traffic != user.limits.traffic_used_gb:
                    user.limits.traffic_used_gb = current_traffic
                    db.session.commit()

                over_traffic = (user.limits.traffic_limit_gb is not None and
                                current_traffic > (user.limits.traffic_limit_gb or 0))
                is_expired = bool(user.limits.is_expired)
                max_conns = user.limits.max_connections

                user_data['limits'] = {
                    'traffic_limit_gb': user.limits.traffic_limit_gb,
                    'traffic_used_gb': user.limits.traffic_used_gb,
                    'max_connections': user.limits.max_connections,
                    'download_speed_mbps': user.limits.download_speed_mbps,
                    'expires_at': user.limits.expires_at.strftime('%Y-%m-%d') if user.limits.expires_at else None,
                    'is_expired': is_expired,
                }

            user_data['current_connections'] = current_conns
            user_data['max_connections'] = max_conns

            # precise problematic flag
            user_data['problematic'] = (
                (not linux_exists) or
                (user.role != 'admin' and (
                    is_expired or
                    over_traffic or
                    (max_conns is not None and current_conns > max_conns)
                ))
            )

            users_data.append(user_data)

        # still return orphans for potential manual tools, but JS won't popup
        db_usernames = [u.username for u in db_users]
        orphaned_linux_users = [u for u in linux_users if u not in db_usernames]

        return jsonify({'success': True, 'users': users_data, 'orphaned_linux_users': orphaned_linux_users})
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@user_management_bp.route('/api/users/sync', methods=['POST'])
@login_required
@admin_required
def sync_users():
    try:
        data = request.get_json() or {}
        action = data.get('action')  # 'repair_all', 'repair_user', 'clean_orphans'

        if action == 'repair_all':
            users = User.query.filter(User.role != 'admin').all()
            repaired = 0
            for user in users:
                if not check_linux_user_exists(user.username):
                    password = generate_random_password()
                    success, _ = create_linux_user(user.username, password)
                    if success:
                        repaired += 1
            return jsonify({'success': True, 'message': f'Repaired {repaired} users'})

        elif action == 'repair_user':
            user_id = data.get('user_id')
            user = User.query.get_or_404(user_id)
            if not check_linux_user_exists(user.username):
                password = generate_random_password()
                success, message = create_linux_user(user.username, password)
                if success:
                    return jsonify({'success': True, 'message': 'User repaired', 'password': password})
                return jsonify({'success': False, 'message': message}), 500
            else:
                return jsonify({'success': True, 'message': 'User already exists in Linux'})

        elif action == 'clean_orphans':
            linux_users = get_all_linux_users()
            db_usernames = [u.username for u in User.query.all()]
            orphans = [u for u in linux_users if u not in db_usernames]
            cleaned = 0
            for username in orphans:
                success, _ = delete_linux_user(username)
                if success:
                    cleaned += 1
            return jsonify({'success': True, 'message': f'Cleaned {cleaned} orphaned users'})

        return jsonify({'success': False, 'message': 'Invalid action'}), 400
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@user_management_bp.route('/api/users', methods=['POST'])
@login_required
@admin_required
def create_user():
    try:
        data = request.get_json() or {}
        username = data.get('username', '').strip()
        password = data.get('password') or generate_random_password()
        traffic_limit = int(data.get('traffic_limit', 50))
        max_connections = int(data.get('max_connections', 2))
        download_speed = int(data.get('download_speed', 0))
        expiry_days = int(data.get('expiry_days', 30))

        if not username or len(username) < 3:
            return jsonify({'success': False, 'message': 'Username must be at least 3 characters'}), 400
        if User.query.filter_by(username=username).first():
            return jsonify({'success': False, 'message': 'Username already exists in database'}), 400
        if check_linux_user_exists(username):
            return jsonify({'success': False, 'message': 'Username already exists in system'}), 400

        ok, msg = create_linux_user(username, password)
        if not ok:
            return jsonify({'success': False, 'message': msg}), 500

        new_user = User(username=username, role='user', is_active=True)
        new_user.set_password(password)
        db.session.add(new_user)
        db.session.flush()

        expires_at = datetime.utcnow() + timedelta(days=expiry_days)
        limits = UserLimit(user_id=new_user.id,
                           traffic_limit_gb=traffic_limit,
                           max_connections=max_connections,
                           download_speed_mbps=download_speed,
                           expires_at=expires_at)
        db.session.add(limits)
        db.session.commit()

        return jsonify({'success': True, 'message': 'User created successfully',
                        'user': {'id': new_user.id, 'username': username,
                                 'password': password, 'expires_at': expires_at.strftime('%Y-%m-%d')}})
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500

@user_management_bp.route('/api/users/<int:user_id>', methods=['PUT'])
@login_required
@admin_required
def update_user(user_id):
    try:
        user = User.query.get_or_404(user_id)
        data = request.get_json() or {}

        # optional username change (disabled در UI فعلاً، ولی آماده)
        if 'username' in data:
            new_username = data['username'].strip()
            if new_username and new_username != user.username:
                if User.query.filter_by(username=new_username).first():
                    return jsonify({'success': False, 'message': 'Username already exists in database'}), 400
                if check_linux_user_exists(user.username):
                    ok, msg = rename_linux_user(user.username, new_username)
                    if not ok:
                        return jsonify({'success': False, 'message': msg}), 500
                user.username = new_username

        # password reset
        if 'password' in data and data['password']:
            ok, msg = reset_linux_password(user.username, data['password'])
            if not ok:
                return jsonify({'success': False, 'message': msg}), 500
            user.set_password(data['password'])

        if user.limits:
            if 'traffic_limit' in data:
                user.limits.traffic_limit_gb = int(data['traffic_limit'])
            if 'max_connections' in data:
                user.limits.max_connections = int(data['max_connections'])
            if 'download_speed' in data:
                user.limits.download_speed_mbps = int(data['download_speed'])
            if 'expiry_days' in data:
                user.limits.expires_at = datetime.utcnow() + timedelta(days=int(data['expiry_days']))

        if 'is_active' in data:
            user.is_active = bool(data['is_active'])

        db.session.commit()
        return jsonify({'success': True, 'message': 'User updated successfully'})
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500

@user_management_bp.route('/api/users/<int:user_id>', methods=['DELETE'])
@login_required
@admin_required
def delete_user(user_id):
    try:
        user = User.query.get_or_404(user_id)
        if user.role == 'admin':
            return jsonify({'success': False, 'message': 'Cannot delete admin user'}), 403

        username = user.username
        ok, msg = delete_linux_user(username)
        if not ok:
            return jsonify({'success': False, 'message': msg}), 500

        db.session.delete(user)
        db.session.commit()
        return jsonify({'success': True, 'message': 'User deleted successfully'})
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500
