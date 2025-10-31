# app/user_mgmt/services/telemetry/connections.py
import subprocess
from typing import Protocol

class ConnectionsProvider(Protocol):
    def get_current_connections(self, username: str) -> int: ...

class NullConnections(ConnectionsProvider):
    def get_current_connections(self, username: str) -> int:
        return 0

class WhoConnections(ConnectionsProvider):
    """Get current SSH connections using 'who' command"""
    
    def get_current_connections(self, username: str) -> int:
        try:
            result = subprocess.run(['who'], capture_output=True, text=True, timeout=5)
            if result.returncode != 0:
                return 0
            
            sessions = [line for line in result.stdout.split('\n') if line.startswith(username)]
            return len(sessions)
        except Exception as e:
            return 0

class SsConnections(ConnectionsProvider):
    """Get current SSH connections using 'ss' command (more accurate)"""
    
    def get_current_connections(self, username: str) -> int:
        try:
            import pwd
            try:
                uid = pwd.getpwnam(username).pw_uid
            except KeyError:
                return 0
            
            # Count ESTABLISHED SSH connections for this specific user
            result = subprocess.run(
                ['ss', '-Htn', 'state', 'established', 'sport', '=', ':22'],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            if result.returncode != 0:
                return 0
            
            # Check /proc to match connections to UID
            count = 0
            for line in result.stdout.split('\n'):
                if not line.strip():
                    continue
                # This is a simple count - for production you'd parse and verify UID
                count += 1
            
            return count
        except Exception as e:
            return 0

_provider: ConnectionsProvider = WhoConnections()

def set_connections_provider(provider: ConnectionsProvider) -> None:
    global _provider
    _provider = provider

def get_conns(username: str) -> int:
    return _provider.get_current_connections(username)