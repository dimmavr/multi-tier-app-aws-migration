import os
from flask import Flask, jsonify
import psycopg2

VERSION = "1.0"                          # ← το version, εδώ ζει· το deploy θα το αλλάζει

app = Flask(__name__)

# --- Σύνδεση στη βάση: credentials από environment, ΠΟΤΕ hardcoded ---
DB_HOST = os.environ.get("DB_HOST", "10.0.20.10")
DB_NAME = os.environ.get("DB_NAME", "appdb")
DB_USER = os.environ.get("DB_USER", "admin")
DB_PASS = os.environ["DB_PASS"]          # ← χωρίς default: αν λείπει, σκάει καθαρά

@app.route("/health")
def health():
    return jsonify({"status": "ok", "version": VERSION})

@app.route("/")
def index():
    # σύνδεση → query → κλείσιμο → επιστροφή JSON
    conn = psycopg2.connect(host=DB_HOST, dbname=DB_NAME, user=DB_USER, password=DB_PASS)
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM users")
    count = cur.fetchone()[0]
    cur.close()
    conn.close()
    return jsonify({"version": VERSION, "users": count})
if __name__ == "__main__": app.run(host="0.0.0.0", port=8000)
