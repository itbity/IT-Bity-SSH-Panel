from flask import Blueprint, render_template, request, jsonify, flash, redirect, url_for
from flask_login import login_required, current_user
from flask_babel import gettext as _
from app import db
from app.models import User, UserLimit
from functools import wraps

user_management_bp = Blueprint('user_management', __name__)

# Decorator to check if user is admin
def admin_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not current_user.is_authenticated or current_user.role != 'admin':
            flash(_('Access denied. Admin privileges required.'), 'error')
            return redirect(url_for('main.dashboard'))
        return f(*args, **kwargs)
    return decorated_function

@user_management_bp.route('/users')
@login_required
@admin_required
def users_page():
    """Display user management page"""
    return render_template('user_management.html')

@user_management_bp.route('/api/users', methods=['GET'])
@login_required
@admin_required
def get_users():
    """Get all users - API endpoint"""
    try:
        users = User.query.all()
        users_data = []
        
        for user in users:
            user_data = {
                'id': user.id,
                'username': user.username,
                'role': user.role,
                'is_active': user.is_active,
                'created_at': user.created_at.strftime('%Y-%m-%d %H:%M'),
                'last_login': user.last_login.strftime('%Y-%m-%d %H:%M') if user.last_login else _('Never'),
            }
            
            # Add limits if exists
            if user.limits:
                user_data['limits'] = {
                    'traffic_limit_gb': user.limits.traffic_limit_gb,
                    'traffic_used_gb': user.limits.traffic_used_gb,
                    'max_connections': user.limits.max_connections,
                }
            
            users_data.append(user_data)
        
        return jsonify({'success': True, 'users': users_data})
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@user_management_bp.route('/api/users/<int:user_id>', methods=['GET'])
@login_required
@admin_required
def get_user(user_id):
    """Get single user details - API endpoint"""
    try:
        user = User.query.get_or_404(user_id)
        user_data = {
            'id': user.id,
            'username': user.username,
            'role': user.role,
            'is_active': user.is_active,
            'created_at': user.created_at.strftime('%Y-%m-%d %H:%M'),
            'last_login': user.last_login.strftime('%Y-%m-%d %H:%M') if user.last_login else None,
        }
        
        if user.limits:
            user_data['limits'] = {
                'traffic_limit_gb': user.limits.traffic_limit_gb,
                'traffic_used_gb': user.limits.traffic_used_gb,
                'max_connections': user.limits.max_connections,
                'download_speed_mbps': user.limits.download_speed_mbps,
            }
        
        return jsonify({'success': True, 'user': user_data})
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 404

# Placeholder for future functions
@user_management_bp.route('/api/users', methods=['POST'])
@login_required
@admin_required
def create_user():
    """Create new user - TODO: Implement"""
    return jsonify({'success': False, 'message': 'Not implemented yet'}), 501

@user_management_bp.route('/api/users/<int:user_id>', methods=['PUT'])
@login_required
@admin_required
def update_user(user_id):
    """Update user - TODO: Implement"""
    return jsonify({'success': False, 'message': 'Not implemented yet'}), 501

@user_management_bp.route('/api/users/<int:user_id>', methods=['DELETE'])
@login_required
@admin_required
def delete_user(user_id):
    """Delete user - TODO: Implement"""
    return jsonify({'success': False, 'message': 'Not implemented yet'}), 501