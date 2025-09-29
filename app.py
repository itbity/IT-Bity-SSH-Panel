from app import create_app, db
from app.models import User

app = create_app()

@app.cli.command()
def init_db():

    db.create_all()
    
    # Create default admin user
    admin = User.query.filter_by(username='ITBity').first()
    if not admin:
        admin = User(username='ITBity', user_type='admin')
        admin.set_password('Admin')
        db.session.add(admin)
        db.session.commit()
        print('Default admin user created: ITBity / Admin')

if __name__ == '__main__':
    with app.app_context():
        db.create_all()
    app.run(
        host=app.config['HOST'],
        port=app.config['PORT'],
        debug=app.config['DEBUG']
    )