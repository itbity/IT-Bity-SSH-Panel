from flask import Blueprint, jsonify, session
from flask_babel import gettext as _
import paramiko

api_bp = Blueprint('api', __name__)

@api_bp.route('/connect', methods=['POST'])
def connect():
    if 'logged_in' not in session:
        return jsonify({'success': False, 'message': _('Not authenticated')})
    
    # SSH connection logic
    return jsonify({'success': True, 'message': _('Connected successfully')})