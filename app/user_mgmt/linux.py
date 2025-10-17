# app/user_mgmt/linux.py
import subprocess
import pwd

def reload_sshd():
    try:
        subprocess.run(['sudo', 'systemctl', 'reload', 'ssh'], check=True)
    except subprocess.CalledProcessError:
        try:
            subprocess.run(['sudo', 'systemctl', 'reload', 'sshd'], check=True)
        except subprocess.CalledProcessError:
            pass

def get_all_linux_users():
    try:
        return [u.pw_name for u in pwd.getpwall() if 1000 <= u.pw_uid < 65534]
    except Exception:
        return []

def check_linux_user_exists(username: str) -> bool:
    try:
        pwd.getpwnam(username)
        return True
    except KeyError:
        return False

def safe_kill_user_processes(username: str):
    subprocess.run(['sudo', 'pkill', '-KILL', '-u', username], check=False)

def create_linux_user(username: str, password: str):
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
        subprocess.run(['sudo', 'bash', '-lc', f'printf "%s" "{ssh_config}" >> /etc/ssh/sshd_config'], check=True)
        reload_sshd()
        return True, "User created successfully"
    except subprocess.CalledProcessError as e:
        return False, f"Failed to create user: {e}"
    except Exception as e:
        return False, f"Error: {e}"

def reset_linux_password(username: str, new_password: str):
    try:
        if not check_linux_user_exists(username):
            return False, "Linux user does not exist"
        proc = subprocess.Popen(['sudo', 'chpasswd'], stdin=subprocess.PIPE, text=True)
        proc.communicate(f'{username}:{new_password}')
        return True, "Password updated"
    except Exception as e:
        return False, f"Error resetting password: {e}"

def rename_linux_user(old_username: str, new_username: str):
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
        reload_sshd()
        return True, "Linux user renamed"
    except subprocess.CalledProcessError as e:
        return False, f"Failed to rename user: {e}"

def delete_linux_user(username: str):
    try:
        if not check_linux_user_exists(username):
            return True, "Linux user does not exist"
        safe_kill_user_processes(username)
        subprocess.run(['sudo', 'userdel', '-r', username], check=True)
        subprocess.run(['sudo', 'sed', '-i', f'/^Match User {username}$/,/^$/d', '/etc/ssh/sshd_config'], check=True)
        reload_sshd()
        return True, "User deleted successfully"
    except subprocess.CalledProcessError as e:
        return False, f"Failed to delete user: {e}"
    except Exception as e:
        return False, f"Error deleting user: {e}"

def get_current_connections(username: str) -> int:
    # TODO: پیاده‌سازی واقعی با ss -tp یا لاگ‌ها. فعلاً صفر.
    return 0

def get_user_traffic(username: str) -> float:
    # TODO: vnstat/iptables. فعلاً صفر.
    return 0.0
