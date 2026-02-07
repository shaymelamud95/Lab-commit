#!/usr/bin/env python3
"""
Lab-Commit Backend Service
Connects to RDS MySQL and returns application version
"""
import os
import json
import mysql.connector
from flask import Flask, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)  # Enable CORS for frontend polling

# Database configuration from environment variables
DB_HOST = os.environ.get('DB_HOST', 'localhost')
DB_PORT = int(os.environ.get('DB_PORT', 3306))
DB_NAME = os.environ.get('DB_NAME', 'labcommit')
DB_USER = os.environ.get('DB_USER', 'admin')
DB_PASSWORD = os.environ.get('DB_PASSWORD', '')

# Application version (can be overridden by DB)
APP_VERSION = os.environ.get('APP_VERSION', '1.0.0')


def get_db_connection():
    """Create database connection"""
    try:
        conn = mysql.connector.connect(
            host=DB_HOST,
            port=DB_PORT,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            connect_timeout=5
        )
        return conn
    except mysql.connector.Error as e:
        print(f"Database connection error: {e}")
        return None

def init_database():
    """Initialize database with version table if not exists"""
    conn = get_db_connection()
    if conn:
        try:
            cursor = conn.cursor()
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS version (
                    id INT PRIMARY KEY AUTO_INCREMENT,
                    value VARCHAR(255) NOT NULL
                )
            """)
            # Insert default version if not exists
            cursor.execute("SELECT COUNT(*) FROM version;")
            count = cursor.fetchone()[0]
            if count == 0:
                cursor.execute("INSERT INTO version (value) VALUES (%s)", (APP_VERSION,))
            conn.commit()
            cursor.close()
            conn.close()
            print("Database initialized successfully")
        except mysql.connector.Error as e:
            print(f"Database initialization error: {e}")


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'lab-commit-backend'
    }), 200


@app.route('/ready', methods=['GET'])
def ready():
    """Readiness check - verifies DB connection"""
    conn = get_db_connection()
    if conn:
        conn.close()
        return jsonify({'status': 'ready', 'database': 'connected'}), 200
    return jsonify({'status': 'not ready', 'database': 'disconnected'}), 503


@app.route('/version', methods=['GET'])
def get_version():
    """Get application version from database"""
    conn = get_db_connection()
    if conn:
        try:
            cursor = conn.cursor(dictionary=True)
            cursor.execute("SELECT value FROM version ORDER BY id DESC LIMIT 1")
            result = cursor.fetchone()
            cursor.close()
            conn.close()
            if result:
                return jsonify({
                    'version': result['value'],
                    'source': 'database'
                }), 200
        except mysql.connector.Error as e:
            print(f"Query error: {e}")
    # Fallback to environment variable
    return jsonify({
        'version': APP_VERSION,
        'source': 'environment'
    }), 200


@app.route('/version/<new_version>', methods=['PUT', 'POST'])
def set_version(new_version):
    """Update application version in database"""
    conn = get_db_connection()
    if conn:
        try:
            cursor = conn.cursor()
            # Always insert a new version row
            cursor.execute("INSERT INTO version (value) VALUES (%s)", (new_version,))
            conn.commit()
            cursor.close()
            conn.close()
            return jsonify({
                'status': 'updated',
                'version': new_version
            }), 200
        except mysql.connector.Error as e:
            return jsonify({'error': str(e)}), 500
    return jsonify({'error': 'Database connection failed'}), 503


@app.route('/', methods=['GET'])
def root():
    """Root endpoint"""
    return jsonify({
        'service': 'lab-commit-backend',
        'endpoints': ['/health', '/ready', '/version']
    }), 200


if __name__ == '__main__':
    # Initialize database on startup
    init_database()
    
    # Run Flask app
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)
