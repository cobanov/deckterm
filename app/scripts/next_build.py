#!/usr/bin/env python3
"""Prints the next build number for a version: one past the highest App Store Connect has, 1 for a new version.

    scripts/next_build.py KEY_ID ISSUER BUNDLE_ID VERSION

Signs the API token with openssl, so it needs no packages. The key is where altool looks for it.
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request

key_id, issuer, bundle_id, version = sys.argv[1:5]
key = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8")


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def token():
    now = int(time.time())
    head = b64(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    body = b64(json.dumps({"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}).encode())
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key], input=head + b"." + body,
                         capture_output=True, check=True).stdout
    # openssl writes a DER sequence of two integers; the token wants r and s as 32 bytes each.
    r_at = 4 if der[1] < 0x80 else 5
    r = der[r_at:r_at + der[r_at - 1]]
    s_at = r_at + len(r) + 2
    s = der[s_at:s_at + der[s_at - 1]]
    signature = r[-32:].rjust(32, b"\0") + s[-32:].rjust(32, b"\0")
    return (head + b"." + body + b"." + b64(signature)).decode()


def get(path, **query):
    url = f"https://api.appstoreconnect.apple.com/v1/{path}?{urllib.parse.urlencode(query)}"
    request = urllib.request.Request(url, headers={"Authorization": "Bearer " + token()})
    return json.load(urllib.request.urlopen(request))["data"]


app = get("apps", **{"filter[bundleId]": bundle_id})[0]["id"]
# shortcut: one page of 200 builds per version; page through `links.next` if a version ever gets more.
builds = get("builds", **{"filter[app]": app, "filter[preReleaseVersion.version]": version,
                          "fields[builds]": "version", "limit": 200})
print(max((int(build["attributes"]["version"]) for build in builds), default=0) + 1)
