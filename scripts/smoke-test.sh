#!/usr/bin/env bash
# Smoke-test a running instance of the site.
#
# Usage: scripts/smoke-test.sh [BASE_URL]
#   BASE_URL defaults to http://localhost:8080
set -euo pipefail

BASE_URL="${1:-http://localhost:8080}"
BASE_URL="${BASE_URL%/}"
RETRIES="${RETRIES:-15}"

fail() { echo "❌ $*" >&2; exit 1; }
pass() { echo "✅ $*"; }

echo "🔎 Smoke-testing ${BASE_URL}"

# 1. Wait for the container to come up.
for ((i = 1; i <= RETRIES; i++)); do
    if curl -fsS -o /dev/null "${BASE_URL}/healthz"; then
        break
    fi
    [[ $i -eq $RETRIES ]] && fail "/healthz did not respond after ${RETRIES} attempts"
    sleep 1
done
pass "/healthz responds"

# 2. Home page is served and is the right page.
body="$(curl -fsS "${BASE_URL}/")" || fail "GET / failed"
grep -q "<title>CI/CD Pipeline Demo</title>" <<<"$body" || fail "GET / did not return the site"
pass "GET / returns the site"

# 3. Static assets resolve.
for path in assets/app.js assets/styles.css images/ci-cd-diagram-v2.webp; do
    curl -fsS -o /dev/null "${BASE_URL}/${path}" || fail "GET /${path} failed"
done
pass "static assets are served"

# 4. Build metadata is served with the expected keys.
info="$(curl -fsS "${BASE_URL}/build-info.json")" || fail "GET /build-info.json failed"
for key in buildNumber gitCommit gitBranch buildDate; do
    grep -q "\"${key}\": \"" <<<"$info" || fail "build-info.json is missing ${key}"
done
echo "   $(tr -d '\n' <<<"$info")"
pass "build-info.json is valid"

# 5. Security headers are present.
headers="$(curl -fsSI "${BASE_URL}/")"
for h in X-Content-Type-Options X-Frame-Options Content-Security-Policy Referrer-Policy; do
    grep -qi "^${h}:" <<<"$headers" || fail "missing security header: ${h}"
done
if grep -qi '^Server: nginx/' <<<"$headers"; then
    fail "nginx version is exposed in the Server header"
fi
pass "security headers present, server version hidden"

# 6. Unknown paths return 404, not the home page.
code="$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/does-not-exist")"
[[ "$code" == "404" ]] || fail "expected 404 for unknown path, got ${code}"
pass "unknown paths return 404"

echo "🎉 All smoke tests passed"
