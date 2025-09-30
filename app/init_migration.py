# init_migration.py
from app import create_app, db
from app.models import User, UserLimit

app = create_app()

with app.app_context():
    # ایجاد جداول
    db.create_all()
    
    # ایجاد کاربر پیش‌فرض
    admin = User.query.filter_by(username='ITBity').first()
    if not admin:
        admin = User(
            username='ITBity',
            role='admin',
            is_active=True
        )
        admin.set_password('Admin')
        db.session.add(admin)
        db.session.flush()
        
        # ایجاد limits برای ادمین
        admin_limits = UserLimit(
            user_id=admin.id,
            traffic_limit_gb=999999,
            max_connections=999,
            download_speed_mbps=0
        )
        db.session.add(admin_limits)
        db.session.commit()
        
        print('✓ Admin user created: ITBity / Admin')
    else:
        print('✓ Admin user already exists')