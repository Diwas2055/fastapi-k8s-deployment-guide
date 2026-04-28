#!/usr/bin/env bash
# Post-deploy smoke tests — run after every deployment to verify basic functionality.
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
PASS=0
FAIL=0

check() {
  local name="$1"
  local expected="$2"
  local actual
  actual="$(eval "${@:3}" 2>&1)"
  if echo "$actual" | grep -q "$expected"; then
    echo "  [PASS] $name"
    PASS=$((PASS + 1))
  else
    echo "  [FAIL] $name — expected '$expected', got: $actual"
    FAIL=$((FAIL + 1))
  fi
}

echo "==> Running smoke tests against $BASE_URL"

check "liveness probe"    '"alive"'    curl -sf "$BASE_URL/healthz/live"
check "startup probe"     '"started"'  curl -sf "$BASE_URL/healthz/startup"
check "readiness probe"   '"ready"'    curl -sf "$BASE_URL/healthz/ready"
check "metrics endpoint"  "# HELP"     curl -sf "$BASE_URL/metrics"

# CRUD round-trip
ITEM=$(curl -sf -X POST "$BASE_URL/api/v1/items/" \
  -H "Content-Type: application/json" \
  -d '{"name":"SmokeItem","price":1.00}')
ITEM_ID=$(echo "$ITEM" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)

check "create item"       '"SmokeItem"'           echo "$ITEM"
check "get item"          '"SmokeItem"'           curl -sf "$BASE_URL/api/v1/items/$ITEM_ID"
check "update item"       '"price":2.0'           curl -sf -X PATCH "$BASE_URL/api/v1/items/$ITEM_ID" \
                                                    -H "Content-Type: application/json" \
                                                    -d '{"price":2.00}'
check "delete item"       ""                      curl -sf -o /dev/null -w "%{http_code}" \
                                                    -X DELETE "$BASE_URL/api/v1/items/$ITEM_ID" | grep 204

echo ""
echo "==> Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
