"""Minimal App Store Connect API client.

Only what this project needs: mint an ES256 JWT from the .p8 key and make
authenticated calls. Kept dependency-light (cryptography only, no PyJWT) so it
runs on a stock Python 3.
"""
import base64, json, os, sys, time, urllib.request, urllib.error
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

BASE = "https://api.appstoreconnect.apple.com/v1"


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def token(key_id: str, issuer_id: str, key_path: str) -> str:
    with open(key_path, "rb") as handle:
        key = serialization.load_pem_private_key(handle.read(), password=None)
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": now, "exp": now + 900,
               "aud": "appstoreconnect-v1"}
    signing_input = f"{_b64(json.dumps(header).encode())}.{_b64(json.dumps(payload).encode())}"
    der = key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256()))
    r, s = utils.decode_dss_signature(der)
    raw = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return f"{signing_input}.{_b64(raw)}"


def call(method: str, path: str, jwt: str, body=None):
    url = path if path.startswith("http") else BASE + path
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Authorization", f"Bearer {jwt}")
    request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            raw = response.read()
            return response.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            return error.code, json.loads(raw)
        except Exception:
            return error.code, {"raw": raw.decode(errors="replace")[:400]}


def credentials():
    env = {}
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, ".env.local")) as handle:
        for line in handle:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                name, value = line.split("=", 1)
                env[name] = value
    key_id = env["APP_STORE_CONNECT_KEY_ID"]
    issuer = env["APP_STORE_CONNECT_ISSUER_ID"]
    path = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8")
    return key_id, issuer, path
