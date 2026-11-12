# Keycloak dashboards

Copied from https://github.com/keycloak/keycloak-grafana-dashboard (branch
`main`, for Keycloak 26.3+), licensed Apache-2.0, as recommended by
https://www.keycloak.org/observability/grafana-dashboards.

Local change: the `${DS_PROMETHEUS}` import placeholder is replaced with the
provisioned data source UID `prometheus`, and `__inputs`/`__requires` are
removed, so Grafana can provision them from files.

The dashboards expect `namespace`, `container` and `pod` labels; the scrape
job in `prometheus/prometheus.yml` adds them.
