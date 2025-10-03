from app import create_app, db
from app.models import User

# Create Flask application instance
application = create_app()
app = application

@app.cli.command()
def init_db():
    """Initialize database with default admin user"""
    db.create_all()
    
    admin = User.query.filter_by(username='ITBity').first()
    if not admin:
        admin = User(username='ITBity', user_type='admin')
        admin.set_password('Admin')
        db.session.add(admin)
        db.session.commit()
        print('Default admin user created: ITBity / Admin')
    else:
        print('Admin user already exists')

if __name__ == '__main__':
    with app.app_context():
        db.create_all()
    app.run(
        host=app.config.get('HOST', '127.0.0.1'),
        port=app.config.get('PORT', 5001),
        debug=app.config.get('DEBUG', False)
    )