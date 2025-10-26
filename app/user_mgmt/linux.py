import subprocess
import pwd
import os
import shutil

# Automatically detect sudo path, fallback if missing
SUDO_PATH = shutil.which("sudo") or "/usr/bin/sudo"


def _run(cmd, check=True, text=True):
    """
    Execute a system command safely.
    - Adds sudo automatically when running as www-data
    - Captures stderr/stdout for debugging
    """
    # Only prepend sudo if not root
    if os.geteuid() != 0 and SUDO_PATH and not cmd[0].startswith(SUDO_PATH):
        cmd = [SUDO_PATH] + cmd

    try:
        result = subprocess.run(cmd, check=check, text=text, capture_output=True)
        return result
    except FileNotFoundError as e:
        raise RuntimeError(f"Sudo not found at {SUDO_PATH}. Install sudo or fix PATH.") from e
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"Command failed: {cmd}\nSTDERR: {e.stderr.strip()}")


def reload_sshd():
    """Reload SSHD service (ssh or sshd)."""
    for svc in ("ssh", "sshd"):
        try:
            _run(["systemctl", "reload", svc])
            return True
        except Exception:
            continue
    return False


def get_all_linux_users():
    """Return all standard Linux users."""
    try:
        return [u.pw_name for u in pwd.getpwall() if 1000 <= u.pw_uid < 65534]
    except Exception:
        return []


def check_linux_user_exists(username: str) -> bool:
    """Check if a user exists in the system."""
    try:
        pwd.getpwnam(username)
        return True
    except KeyError:
        return False


def safe_kill_user_processes(username: str):
    """Kill all processes belonging to the given user."""
    _run(["pkill", "-KILL", "-u", username], check=False)


def create_linux_user(username: str, password: str):
    """Create a Linux user, set password, and append SSHD config."""
    try:
        if check_linux_user_exists(username):
            return False, "Linux user already exists"

        # 1️⃣ Create user
        _run(["useradd", "-m", "-s", "/bin/false", username])

        # 2️⃣ Set password
        proc = subprocess.Popen([SUDO_PATH, "chpasswd"], stdin=subprocess.PIPE, text=True)
        proc.communicate(f"{username}:{password}")

        # 3️⃣ Generate SSHD rule
        ssh_config = f"""
Match User {username}
    PermitTunnel yes
    AllowTcpForwarding yes
    X11Forwarding no
    AllowAgentForwarding no
    ForceCommand /bin/false
"""
        tmp_file = f"/tmp/ssh_user_{username}.conf"
        with open(tmp_file, "w") as f:
            f.write(ssh_config)

        # 4️⃣ Append rule to sshd_config via tee
        cmd = [SUDO_PATH, "tee", "-a", "/etc/ssh/sshd_config"]
        with open(tmp_file, "r") as f:
            proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, text=True)
            proc.communicate(f.read())
        if proc.returncode != 0:
            return False, "Failed to update sshd_config"

        # 5️⃣ Clean temp file
        _run(["rm", "-f", tmp_file])

        # 6️⃣ Reload SSH
        reload_sshd()
        return True, "User created successfully"

    except Exception as e:
        return False, f"Error: {e}"


def reset_linux_password(username: str, new_password: str):
    """Reset user's password."""
    try:
        if not check_linux_user_exists(username):
            return False, "User does not exist"
        proc = subprocess.Popen([SUDO_PATH, "chpasswd"], stdin=subprocess.PIPE, text=True)
        proc.communicate(f"{username}:{new_password}")
        return True, "Password updated"
    except Exception as e:
        return False, f"Error resetting password: {e}"


def rename_linux_user(old_username: str, new_username: str):
    """Rename an existing Linux user and update SSHD rule."""
    try:
        if not check_linux_user_exists(old_username):
            return False, "Old user not found"
        if check_linux_user_exists(new_username):
            return False, "New username already exists"

        _run(["usermod", "-l", new_username, old_username])
        _run(["usermod", "-d", f"/home/{new_username}", "-m", new_username])
        _run(["sed", "-i",
              f"s/^Match User {old_username}$/Match User {new_username}/",
              "/etc/ssh/sshd_config"])
        reload_sshd()
        return True, "User renamed successfully"
    except Exception as e:
        return False, f"Error renaming user: {e}"


def delete_linux_user(username: str):
    """Delete a user and its SSHD rule."""
    try:
        if not check_linux_user_exists(username):
            return True, "User does not exist"
        safe_kill_user_processes(username)
        _run(["userdel", "-r", username])
        _run(["sed", "-i", f"/^Match User {username}$/,/^$/d", "/etc/ssh/sshd_config"])
        reload_sshd()
        return True, "User deleted successfully"
    except Exception as e:
        return False, f"Error deleting user: {e}"


# Optional placeholders for later extensions
def get_current_connections(username: str) -> int:
    """Count active SSH connections (to be implemented)."""
    return 0


def get_user_traffic(username: str) -> float:
    """Get traffic usage (to be implemented via vnstat)."""
    return 0.0
