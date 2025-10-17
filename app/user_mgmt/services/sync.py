# app/user_mgmt/services/sync.py
from app.models import User
from ..utils import generate_random_password
from ..linux import check_linux_user_exists, create_linux_user

def repair_all():
    users = User.query.filter(User.role != 'admin').all()
    repaired = 0
    for user in users:
        if not check_linux_user_exists(user.username):
            password = generate_random_password()
            ok, _ = create_linux_user(user.username, password)
            if ok:
                repaired += 1
    return {'success': True, 'message': f'Repaired {repaired} users'}

def repair_user(user_id: int):
    user = User.query.get_or_404(user_id)
    if not check_linux_user_exists(user.username):
        password = generate_random_password()
        ok, msg = create_linux_user(user.username, password)
        if ok:
            return {'success': True, 'message': 'User repaired', 'password': password}
        return {'success': False, 'message': msg}, 500
    return {'success': True, 'message': 'User already exists in Linux'}
