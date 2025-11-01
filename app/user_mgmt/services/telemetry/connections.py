# app/user_mgmt/services/telemetry/connections.py
import subprocess
from typing import Protocol

class ConnectionsProvider(Protocol):
    def get_current_connections(self, username: str) -> int: ...

class NullConnections(ConnectionsProvider):
    def get_current_connections(self, username: str) -> int:
        return 0

class WhoConnections(ConnectionsProvider):
    """Get current SSH connections using 'who' command (works only with shell sessions)"""
    
    def get_current_connections(self, username: str) -> int:
        try:
            result = subprocess.run(['who'], capture_output=True, text=True, timeout=5)
            if result.returncode != 0:
                return 0
            
            sessions = [line for line in result.stdout.split('\n') if line.startswith(username)]
            return len(sessions)
        except Exception as e:
            return 0

class SsConnectionsImproved(ConnectionsProvider):
    """Get current SSH connections using 'ss' with process info (most accurate for SFTP/tunnel users)"""
    
    def get_current_connections(self, username: str) -> int:
        try:
            import re
            
            result = subprocess.run(
                ['/usr/bin/sudo', '/usr/bin/ss', '-tnp', 'state', 'established', '( sport = :22 )'],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            if result.returncode != 0:
                return 0
            
            pids = re.findall(r'pid=(\d+)', result.stdout)
            
            count = 0
            for pid in set(pids):
                try:
                    ps_result = subprocess.run(
                        ['/usr/bin/ps', '-o', 'user=', '-p', pid],
                        capture_output=True,
                        text=True,
                        timeout=2
                    )
                    if ps_result.returncode == 0 and ps_result.stdout.strip() == username:
                        count += 1
                except:
                    continue
            
            return count
        except Exception as e:
            return 0

_provider: ConnectionsProvider = SsConnectionsImproved()

def set_connections_provider(provider: ConnectionsProvider) -> None:
    global _provider
    _provider = provider

def get_conns(username: str) -> int:
    return _provider.get_current_connections(username)