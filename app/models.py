# app/models.py
from app import db
from flask_login import UserMixin
from werkzeug.security import generate_password_hash, check_password_hash
from datetime import datetime

class User(UserMixin, db.Model):
    __tablename__ = 'users'
    
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(255), nullable=False)
    role = db.Column(db.String(20), default='user', nullable=False)  # admin, user
    is_active = db.Column(db.Boolean, default=True, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    last_login = db.Column(db.DateTime)
    
    # Relationship
    limits = db.relationship('UserLimit', backref='user', uselist=False, cascade='all, delete-orphan')
    
    def set_password(self, password):
        self.password_hash = generate_password_hash(password)
    
    def check_password(self, password):
        return check_password_hash(self.password_hash, password)
    
    @property
    def user_type(self):
        return self.role
    
    def __repr__(self):
        return f'<User {self.username}>'


class UserLimit(db.Model):
    __tablename__ = 'user_limits'
    
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, unique=True)
    
    traffic_limit_gb = db.Column(db.Integer, default=50, nullable=False)
    traffic_used_gb = db.Column(db.Float, default=0.0, nullable=False)
    max_connections = db.Column(db.Integer, default=2, nullable=False)
    download_speed_mbps = db.Column(db.Integer, default=0, nullable=False)  # 0 = unlimited
    expires_at = db.Column(db.DateTime)
    
    @property
    def traffic_remaining_gb(self):
        return max(0, self.traffic_limit_gb - self.traffic_used_gb)
    
    @property
    def is_expired(self):
        if self.expires_at:
            return datetime.utcnow() > self.expires_at
        return False
    
    def __repr__(self):
        return f'<UserLimit user_id={self.user_id}>'