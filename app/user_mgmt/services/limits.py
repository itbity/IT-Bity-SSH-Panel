# app/user_mgmt/services/limits.py
from datetime import datetime, timedelta
from app.models import User

def apply_limits_updates(user: User, data: dict) -> None:
    if not user.limits:
        return
    if 'traffic_limit' in data:
        user.limits.traffic_limit_gb = int(data['traffic_limit'])
    if 'max_connections' in data:
        user.limits.max_connections = int(data['max_connections'])
    if 'download_speed' in data:
        user.limits.download_speed_mbps = int(data['download_speed'])
    if 'expiry_days' in data:
        user.limits.expires_at = datetime.utcnow() + timedelta(days=int(data['expiry_days']))
