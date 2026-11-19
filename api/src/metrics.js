// Instrumentation Prometheus de l'API (Jour 4).
//
// Prometheus fonctionne en mode PULL : il vient lire GET /metrics toutes les 15 s.
// On y expose trois familles de métriques :
//   1. les métriques par défaut de prom-client (CPU, mémoire, event loop du process Node) ;
//   2. les métriques HTTP de la méthode RED : Rate et Errors (compteur
//      http_requests_total, label status_code), Duration (histogramme) ;
//   3. des métriques métier : tâches créées, et la version en ligne (build_info).
//
// Conventions Prometheus :
//   - suffixe _total pour un compteur, unité de base dans le nom (_seconds) ;
//   - labels à FAIBLE cardinalité : la route normalisée (/api/tasks/:id/toggle),
//     jamais l'id réel (chaque valeur de label crée une série temporelle).
import client from 'prom-client';

// Buckets de l'histogramme : de 5 ms à 2 s, adaptés à une petite API.
const DURATION_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2];

// Requête qui ne correspond à aucune route (404) : un label unique, sinon un
// robot qui teste 10 000 URL créerait 10 000 séries.
const UNMATCHED_ROUTE = 'unmatched';

// Route normalisée : Express a matché "/:id/toggle" sous "/api/tasks".
// "/api/tasks" + "/" donnerait "/api/tasks/" : on retire la barre finale.
function routeLabel(req) {
  if (!req.route) return UNMATCHED_ROUTE;
  const route = `${req.baseUrl}${req.route.path}`;
  return route.length > 1 ? route.replace(/\/$/, '') : route;
}

// createMetrics() renvoie un registre NEUF à chaque appel (pas le registre global
// de prom-client) : chaque test peut créer son application sans hériter des
// compteurs du test précédent.
export function createMetrics({
  appVersion = 'dev',
  collectDefaults = true,
} = {}) {
  const register = new client.Registry();

  if (collectDefaults) {
    client.collectDefaultMetrics({ register });
  }

  const httpRequestsTotal = new client.Counter({
    name: 'http_requests_total',
    help: 'Nombre de requêtes HTTP traitées',
    labelNames: ['method', 'route', 'status_code'],
    registers: [register],
  });

  const httpRequestDuration = new client.Histogram({
    name: 'http_request_duration_seconds',
    help: 'Durée de traitement des requêtes HTTP, en secondes',
    labelNames: ['method', 'route', 'status_code'],
    buckets: DURATION_BUCKETS,
    registers: [register],
  });

  const tasksCreatedTotal = new client.Counter({
    name: 'taskflow_tasks_created_total',
    help: 'Nombre de tâches créées depuis le démarrage',
    registers: [register],
  });

  // Gauge toujours à 1 : sert à afficher la version en ligne dans Grafana et à
  // repérer un déploiement (le label version change).
  const buildInfo = new client.Gauge({
    name: 'taskflow_build_info',
    help: "Version de l'API en cours d'exécution (valeur toujours 1)",
    labelNames: ['version'],
    registers: [register],
  });
  buildInfo.set({ version: appVersion }, 1);

  // Middleware : mesure chaque requête quand la réponse est terminée (le code
  // HTTP est alors connu). À monter AVANT les routes.
  function middleware(req, res, next) {
    const stopTimer = httpRequestDuration.startTimer();

    res.on('finish', () => {
      const labels = {
        method: req.method,
        route: routeLabel(req),
        status_code: String(res.statusCode),
      };
      httpRequestsTotal.inc(labels);
      stopTimer(labels);
    });

    next();
  }

  // Handler de GET /metrics : le format texte attendu par Prometheus.
  async function handler(_req, res) {
    res.set('Content-Type', register.contentType);
    res.send(await register.metrics());
  }

  return Object.freeze({
    register,
    middleware,
    handler,
    taskCreated: () => tasksCreatedTotal.inc(),
  });
}
