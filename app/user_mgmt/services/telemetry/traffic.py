# app/user_mgmt/services/telemetry/traffic.py
from typing import Protocol

class TrafficProvider(Protocol):
    def get_user_traffic_gb(self, username: str) -> float: ...

class NullTraffic(TrafficProvider):
    def get_user_traffic_gb(self, username: str) -> float:
        return 0.0

# TODO: نمونه‌ی واقعی vnstat
# class VnstatTraffic(TrafficProvider):
#     ...

# ـــــ رجیستری/DI ساده
_provider: TrafficProvider = NullTraffic()

def set_traffic_provider(provider: TrafficProvider) -> None:
    global _provider
    _provider = provider

def get_traffic_gb(username: str) -> float:
    return _provider.get_user_traffic_gb(username)
