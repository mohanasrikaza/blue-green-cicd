import os
from flask import Flask, jsonify

app = Flask(__name__)

VERSION = os.getenv("APP_VERSION", "local")
HEALTHY = os.getenv("APP_HEALTHY", "true").lower() == "true"


@app.route("/")
def home():
    return jsonify({
        "project": "Blue-Green CI/CD",
        "version": VERSION,
        "message": f"Hello from version {VERSION}"
    })


@app.route("/health")
def health():
    if not HEALTHY:
        return jsonify({
            "status": "unhealthy",
            "version": VERSION
        }), 503

    return jsonify({
        "status": "healthy",
        "version": VERSION
    }), 200


@app.route("/api/status")
def status():
    return jsonify({
        "deployment": "blue-green",
        "version": VERSION,
        "status": "running"
    })



if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
