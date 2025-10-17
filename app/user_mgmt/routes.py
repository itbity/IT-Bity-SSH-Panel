# app/user_mgmt/routes.py
from flask import Blueprint, render_template, request, jsonify
from flask_login import login_required
from .utils import admin_required
from .services import (
    build_users_payload, action_repair_all, action_repair_user, action_clean_orphans,
    action_import_linux_user, create_user_full, update_user_full, delete_user_full
)

user_management_bp = Blueprint('user_management', __name__)

@user_management_bp.route('/users')
@login_required
@admin_required
def users_page():
    return render_template('user_management.html')

@user_management_bp.route('/api/users', methods=['GET'])
@login_required
@admin_required
def get_users():
    try:
        users, orphans = build_users_payload()
        return jsonify({'success': True, 'users': users, 'orphaned_linux_users': orphans})
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@user_management_bp.route('/api/users/sync', methods=['POST'])
@login_required
@admin_required
def sync_users():
    try:
        data = request.get_json() or {}
        action = data.get('action')

        if action == 'repair_all':
            return jsonify(action_repair_all())

        if action == 'repair_user':
            result = action_repair_user(int(data.get('user_id')))
            status = 200 if result.get('success') else 400
            return jsonify(result), status if isinstance(result, dict) else result

        if action == 'clean_orphans':
            return jsonify(action_clean_orphans())

        if action == 'import_linux_user':
            result = action_import_linux_user(data.get('username'))
            if isinstance(result, tuple):
                body, code = result
                return jsonify(body), code
            return jsonify(result)

        return jsonify({'success': False, 'message': 'Invalid action'}), 400
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@user_management_bp.route('/api/users', methods=['POST'])
@login_required
@admin_required
def create_user():
    try:
        payload = request.get_json() or {}
        result = create_user_full(payload)
        if isinstance(result, tuple):
            body, code = result
            return jsonify(body), code
        return jsonify(result)
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@user_management_bp.route('/api/users/<int:user_id>', methods=['PUT'])
@login_required
@admin_required
def update_user(user_id):
    try:
        data = request.get_json() or {}
        result = update_user_full(user_id, data)
        if isinstance(result, tuple):
            body, code = result
            return jsonify(body), code
        return jsonify(result)
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

@user_management_bp.route('/api/users/<int:user_id>', methods=['DELETE'])
@login_required
@admin_required
def delete_user(user_id):
    try:
        result = delete_user_full(user_id)
        if isinstance(result, tuple):
            body, code = result
            return jsonify(body), code
        return jsonify(result)
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500
