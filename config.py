import os
from dotenv import load_dotenv

load_dotenv()

class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'dev-secret-key-change-me'
    PANEL_PATH = os.environ.get('PANEL_PATH') or 'admin'
    HOST = os.environ.get('HOST') or '127.0.0.1'
    PORT = int(os.environ.get('PORT') or 5000)
    DEBUG = os.environ.get('DEBUG') == 'True'
    
    # Database
    SQLALCHEMY_DATABASE_URI = 'sqlite:///panel.db'
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    
    # Babel Configuration
    BABEL_DEFAULT_LOCALE = 'fa'
    BABEL_DEFAULT_TIMEZONE = 'Asia/Tehran'
    LANGUAGES = {
        'en': 'English',
        'fa': 'فارسی'
    }
    

    SESSION_COOKIE_SECURE = False  
    SESSION_COOKIE_HTTPONLY = True
    PERMANENT_SESSION_LIFETIME = 3600