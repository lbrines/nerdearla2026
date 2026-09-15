#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
COMPOSE_PROJECT_NAME="phase5-grafana-$$"
GRAFANA_URL="http://127.0.0.1:3000"
GRAFANA_TIMEOUT_SECONDS=60
trap on_exit EXIT

ensure_lab_projects_inactive() {
  local projects

  projects="$(docker ps --format '{{.Label "com.docker.compose.project"}}' | awk 'NF && ($0 == "nerdearla2026" || $0 ~ /^phase[0-9]+-/) { print }' | LC_ALL=C sort -u)"
  if [ -n "$projects" ]; then
    fail "refusing to disrupt active lab Compose projects: $projects"
  fi
}

grafana_get() {
  curl --noproxy '*' --silent --show-error --fail --max-time 2 "$GRAFANA_URL$1"
}

wait_for_grafana() {
  local deadline=$((SECONDS + GRAFANA_TIMEOUT_SECONDS)) response

  while :; do
    if response="$(grafana_get /api/health)" &&
      python3 -c 'import json, sys; raise SystemExit(json.load(sys.stdin).get("database") != "ok")' <<<"$response"; then
      return 0
    fi
    if (( SECONDS >= deadline )); then
      compose logs --no-color grafana >&2 || true
      fail "Grafana did not become healthy at $GRAFANA_URL within ${GRAFANA_TIMEOUT_SECONDS} seconds"
      return 1
    fi
    sleep 1
  done
}

require_prometheus_datasource() {
  local response

  response="$(grafana_get /api/datasources/uid/prometheus)" || return 1
  python3 -c '
import json, sys
source = json.load(sys.stdin)
expected = {
    "uid": "prometheus",
    "type": "prometheus",
    "access": "proxy",
    "url": "http://prometheus:9090",
    "isDefault": True,
}
for key, value in expected.items():
    if source.get(key) != value:
        raise SystemExit(f"datasource {key} = {source.get(key)!r}, want {value!r}")
' <<<"$response"
}

require_dashboard_contract() {
  local uid="$1" title="$2" expected_queries="$3" response

  response="$(grafana_get "/api/dashboards/uid/$uid")" || return 1
  EXPECTED_QUERIES="$expected_queries" python3 -c '
import json, os, sys
payload = json.load(sys.stdin)
dashboard = payload.get("dashboard", {})
uid, title = sys.argv[1:3]
if dashboard.get("uid") != uid or dashboard.get("title") != title:
    raise SystemExit(f"dashboard identity = {(dashboard.get('"'"'uid'"'"'), dashboard.get('"'"'title'"'"'))!r}")
panels = dashboard.get("panels", [])
if any(panel.get("datasource", {}).get("uid") != "prometheus" for panel in panels):
    raise SystemExit("a dashboard panel is not wired to the Prometheus UID")
targets = [target for panel in panels for target in panel.get("targets", [])]
actual = {" ".join(target.get("expr", "").split()) for target in targets}
expected = set(json.loads(os.environ["EXPECTED_QUERIES"]))
if actual != expected:
    raise SystemExit("dashboard queries do not match the versioned contract")
' "$uid" "$title" <<<"$response"
}

require_overview_home() {
  local response

  response="$(grafana_get /api/dashboards/home)" || return 1
  python3 -c '
import json, sys
home = json.load(sys.stdin)
if home.get("redirectUri") != "/d/default-home-dashboard/lab-overview":
    raise SystemExit("Lab Overview is not Grafana home")
' <<<"$response"
}

query_through_grafana() {
  local query="$1" response

  response="$(curl --noproxy '*' --silent --show-error --fail --max-time 5 --request POST \
    --data-urlencode "query=$query" \
    "$GRAFANA_URL/api/datasources/proxy/uid/prometheus/api/v1/query")" || return 1
  python3 -c 'import json, sys; raise SystemExit(json.load(sys.stdin).get("status") != "success")' <<<"$response"
}

OVERVIEW_QUERIES='["sum(rate(checkout_requests_total{outcome=\"error\"}[30s])) / sum(rate(checkout_requests_total[30s]))", "histogram_quantile(0.95, sum by (le) (rate(checkout_request_duration_seconds_bucket[30s])))", "sum(rate(checkout_requests_total[30s]))", "sum(rate(pricing_requests_total{outcome=\"error\"}[30s])) / sum(rate(pricing_requests_total[30s]))", "histogram_quantile(0.95, sum by (le) (rate(pricing_request_duration_seconds_bucket[30s])))"]'
BY_INSTANCE_QUERIES='["sum by (checkout_instance) (rate(checkout_requests_total{outcome=\"error\"}[30s])) / sum by (checkout_instance) (rate(checkout_requests_total[30s]))", "sum by (checkout_instance) (rate(checkout_requests_total[30s]))", "histogram_quantile(0.95, sum by (le, checkout_instance) (rate(checkout_pricing_request_duration_seconds_bucket[30s])))"]'

ensure_lab_projects_inactive
if ! compose up --build --detach; then
  fail 'could not build and start the Phase 5.2 stack'
fi
wait_for_grafana
require_prometheus_datasource
require_dashboard_contract lab-overview 'Lab Overview' "$OVERVIEW_QUERIES"
require_dashboard_contract checkout-by-instance 'Checkout by Instance' "$BY_INSTANCE_QUERIES"
require_overview_home

while IFS= read -r query; do
  query_through_grafana "$query" || fail "Grafana could not execute dashboard query: $query"
done < <(python3 -c 'import json, sys; print("\n".join(query for group in sys.argv[1:] for query in json.loads(group)))' \
  "$OVERVIEW_QUERIES" "$BY_INSTANCE_QUERIES")

printf 'grafana acceptance passed: anonymous Viewer access received provisioned Prometheus dashboards and executed their contract queries.\n'
