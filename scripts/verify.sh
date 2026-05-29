#!/bin/bash
set -e

APP_PORT="3000"
BASE_URL="http://localhost"
APP_URL="http://localhost:${APP_PORT}"

info()  { echo -e "\e[32m[INFO]\e[0m  $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m  $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*"; exit 1; }

FAILED=0

check() {
    local description="$1"
    local result="$2"
    if [ "$result" = "ok" ]; then
        info "PASS: $description"
    else
        warn "FAIL: $description — $result"
        FAILED=1
    fi
}

info "checking systemd service..."
if sudo systemctl is-active mywebapp > /dev/null 2>&1; then
    check "mywebapp service is active" "ok"
else
    check "mywebapp service is active" "service is not running"
fi

info "checking nginx..."
if sudo systemctl is-active nginx > /dev/null 2>&1; then
    check "nginx service is active" "ok"
else
    check "nginx service is active" "nginx is not running"
fi

if sudo nginx -t > /dev/null 2>&1; then
    check "nginx config is valid" "ok"
else
    check "nginx config is valid" "nginx -t failed"
fi

status=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/tasks")
if [ "$status" = "200" ]; then
    check "nginx proxies GET /tasks" "ok"
else
    check "nginx proxies GET /tasks" "expected 200, got $status"
fi

status=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/notaroute")
if [ "$status" = "404" ]; then
    check "nginx blocks unknown routes with 404" "ok"
else
    check "nginx blocks unknown routes with 404" "expected 404, got $status"
fi

info "checking app health endpoints (bypassing nginx)..."

status=$(curl -s -o /dev/null -w "%{http_code}" "$APP_URL/health/alive")
if [ "$status" = "200" ]; then
    check "GET /health/alive returns 200" "ok"
else
    check "GET /health/alive returns 200" "expected 200, got $status"
fi

response=$(curl -s "$APP_URL/health/ready")
status=$(curl -s -o /dev/null -w "%{http_code}" "$APP_URL/health/ready")
if [ "$status" = "200" ]; then
    check "GET /health/ready returns 200 (DB reachable)" "ok"
else
    check "GET /health/ready returns 200 (DB reachable)" "expected 200, got $status — $response"
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
    info "><>    =======================    <><"
    info "      verification successful        "
    info "><>    =======================    <><"
    exit 0
else
    error "verification failed — see warnings above"
fi