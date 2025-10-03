from app import create_app, db
from app.models import User

app = create_app()
with app.app_context():
    # بررسی کاربر ادمین
    admin = User.query.filter_by(username='ITBity').first()
    
    if admin:
        print(f'✓ کاربر پیدا شد')
        print(f'  Username: {admin.username}')
        print(f'  Role: {admin.role}')
        print(f'  Active: {admin.is_active}')
        print(f'  Password Hash: {admin.password_hash[:20]}...')
        
        # تست پسورد
        if admin.check_password('Admin'):
            print('✓ پسورد "Admin" صحیح است')
        else:
            print('✗ پسورد "Admin" اشتباه است')
            print('→ باید پسورد را دوباره تنظیم کنیم')
            
            # تنظیم مجدد پسورد
            admin.set_password('Admin')
            db.session.commit()
            print('✓ پسورد به "Admin" تغییر یافت')
            
            # تست مجدد
            if admin.check_password('Admin'):
                print('✓ تست مجدد موفق')
    else:
        print('✗ کاربر ITBity وجود ندارد')
        print('→ باید کاربر جدید بسازیم')

exit()