# app/user_mgmt/services/telemetry/connections.py
from typing import Protocol

class ConnectionsProvider(Protocol):
    def get_current_connections(self, username: str) -> int: ...

class NullConnections(ConnectionsProvider):
    def get_current_connections(self, username: str) -> int:
        return 0

# TODO: نمونه‌ی ss -tp
# class SsConnections(ConnectionsProvider):
#     ...

_provider: ConnectionsProvider = NullConnections()

def set_connections_provider(provider: ConnectionsProvider) -> None:
    global _provider
    _provider = provider

def get_conns(username: str) -> int:
    return _provider.get_current_connections(username)
