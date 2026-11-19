# monitoring/ : supervision de la production TaskFlow

Prometheus + blackbox exporter + Alertmanager + Mailpit + Grafana, **en code**, raccordés au réseau `taskflow-prod`.

```bash
# la prod doit tourner (elle crée le réseau taskflow-prod)
docker compose -f ~/taskflow-prod/compose.prod.yaml ps

cd monitoring
docker compose -f compose.monitoring.yaml up -d
docker compose -f compose.monitoring.yaml ps
```

| Service | URL | Rôle |
|---|---|---|
| Grafana | http://localhost:3001 (admin / `GRAFANA_ADMIN_PASSWORD`, `admin` par défaut) | dashboard *TaskFlow : RED et disponibilité* (page d'accueil) |
| Prometheus | http://localhost:9090 | *Status > Targets*, *Alerts*, requêtes PromQL |
| Alertmanager | http://localhost:9093 | alertes actives, inhibées, silences |
| Mailpit | http://localhost:8025 | les mails envoyés par Alertmanager |
| blackbox | (non publié) | sonde `http://front/health` depuis le réseau de la prod |

Ports publiés sur `127.0.0.1` uniquement ; modifiables par `GRAFANA_PORT`, `PROMETHEUS_PORT`, `ALERTMANAGER_PORT`,
`MAILPIT_PORT`. `TASKFLOW_NETWORK` vise un autre réseau que `taskflow-prod` (utilisé par la démo du cours).

## Ce qui est collecté

| Job | Cible | Type |
|---|---|---|
| `taskflow-api` | `api:3000/metrics` (prom-client : RED, `taskflow_tasks_created_total`, `taskflow_build_info`, process Node) | boîte blanche |
| `blackbox-health` | `http://front/health` via blackbox (module `http_health` : 200 **et** `"status":"ok"`) | boîte noire |
| `prometheus`, `blackbox` | eux-mêmes | — |

## Alertes (`prometheus/rules/taskflow.yml`)

| Alerte | Condition | Sévérité |
|---|---|---|
| `TaskFlowApiDown` | sonde `/health` en échec depuis 1 min | critical |
| `TaskFlowMetricsDown` | `up{job="taskflow-api"} == 0` depuis 1 min (inhibée si `TaskFlowApiDown` est active) | warning |
| `TaskFlowHighErrorRate` | plus de 5 % de 5xx sur 5 min, pendant 5 min | warning |
| `TaskFlowHighLatency` | p95 > 300 ms pendant 5 min | warning |
| `Watchdog` | toujours active (preuve que la chaîne d'alerte fonctionne), jamais notifiée | none |

## Vérifier la configuration (à faire avant chaque commit)

```bash
docker compose -f compose.monitoring.yaml exec prometheus promtool check config /etc/prometheus/prometheus.yml
docker compose -f compose.monitoring.yaml exec prometheus promtool check rules /etc/prometheus/rules/taskflow.yml
docker compose -f compose.monitoring.yaml exec prometheus promtool test rules /etc/prometheus/tests/taskflow_test.yml
docker compose -f compose.monitoring.yaml exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml
curl -X POST http://localhost:9090/-/reload      # recharger Prometheus sans redémarrer

# Sans lancer la stack (ce que ferait un job CI) :
docker run --rm -v "$PWD/prometheus":/p -w /p/tests --entrypoint promtool docker.io/prom/prometheus:v3.15.1 test rules taskflow_test.yml
```

## Modifier le dashboard

Le dashboard est en lecture seule dans Grafana (`allowUiUpdates: false`) : c'est le fichier
`grafana/dashboards/taskflow-red.json` qui fait foi. Pour le faire évoluer : *Save as* une copie dans Grafana, modifier,
*Export > Export as JSON*, remplacer le fichier, PR.

## Tester l'alerte

```bash
docker compose -f ~/taskflow-prod/compose.prod.yaml stop api     # ~1 min 30 : mail [FIRING] dans Mailpit
docker compose -f ~/taskflow-prod/compose.prod.yaml start api    # ~2 min : mail [RESOLVED]
```
