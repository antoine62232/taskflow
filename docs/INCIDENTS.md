# Journal des incidents TaskFlow

## INC-001 : API de production indisponible (20/11/2026)

**Statut** : résolu
**Sévérité** : majeure (production entièrement indisponible pour les utilisateurs)
**Rédigé par** : Antoine
**Format** : post-mortem sans recherche de coupable (blameless)

### Résumé

Le 20/11/2026 vers 09:22, l'API de production a cessé de démarrer après la recréation de son conteneur. La variable `DATABASE_URL` du fichier `.env` de production avait été renommée en `DATABASE_UR`. Sans URL de connexion, le client PostgreSQL visait `localhost:5432` à l'intérieur du conteneur de l'API et échouait (`ECONNREFUSED`). L'API redémarrait en boucle. Le service a été rétabli à 09:37 après correction de la variable et recréation du conteneur.

### Impact

- Durée d'indisponibilité : environ 15 minutes (09:22 à 09:37).
- Front accessible, mais toutes les routes `/api/*` et `/health` en échec : aucune lecture ni création de tâche possible.
- Aucune perte de données : PostgreSQL est resté sain pendant tout l'incident.

### Chronologie (heure de Paris)

| Heure | Événement |
|-------|-----------|
| 09:21:42 | Recréation du conteneur `api` avec un `.env` modifié. Premier log `fatal : Démarrage impossible : ECONNREFUSED`. |
| 09:22 | L'API redémarre en boucle, le healthcheck échoue. Début de l'impact. |
| 09:23 | Alertmanager envoie `[FIRING:1] TaskFlowApiDown` et `[FIRING:1] TaskFlowMetricsDown` (reçus dans Mailpit). |
| 09:25 | Prise en charge. `docker compose ps` : api `restarting`/`unhealthy`, db et front sains. |
| 09:28 | Lecture des logs de l'API : `ECONNREFUSED`, avec l'indice « Vérifiez DATABASE_URL ». |
| 09:32 | `docker inspect` : aucune variable `DATABASE_URL` dans le conteneur. |
| 09:33 | `grep DATABASE .env` : la ligne 14 contient `DATABASE_UR=postgres://taskflow:***@db:5432/taskflow`. Cause racine identifiée. |
| 09:35 | Correction du `.env` (`DATABASE_URL=`), recréation de l'API avec l'image déjà déployée (`.deployed_tag`), suppression de `.env.bak`. |
| 09:36 | API `healthy`, `/health` répond, création d'une tâche réussie. |
| 09:37 | `[RESOLVED]` reçu pour les deux alertes. Fin de l'incident. |

### Indicateurs

- **Délai de détection** : environ 1 minute (impact à 09:22, alerte à 09:23 ; la règle a un `for: 1m`).
- **Délai de diagnostic** : environ 10 minutes (09:23 à 09:33).
- **Délai de résolution (MTTR)** : environ 15 minutes (09:22 à 09:37).

### Analyse : les 5 pourquoi

1. **Pourquoi l'API était-elle indisponible ?** Parce qu'elle s'arrêtait au démarrage sur `ECONNREFUSED` et redémarrait en boucle.
2. **Pourquoi `ECONNREFUSED` ?** Parce que le client PostgreSQL, sans `DATABASE_URL`, utilise ses valeurs par défaut et tente `localhost:5432`, où aucune base ne tourne.
3. **Pourquoi `DATABASE_URL` était-elle absente ?** Parce que la ligne du `.env` de production s'appelait `DATABASE_UR` : Docker Compose a transmis une variable que l'application ne lit pas.
4. **Pourquoi ce fichier modifié a-t-il pu être chargé ?** Parce que le `.env` de production est édité à la main sur le serveur, hors du dépôt, et que rien ne compare son contenu à `.env.example` avant un redémarrage.
5. **Pourquoi l'erreur n'était-elle pas explicite ?** Parce que l'API ne vérifie pas sa configuration au démarrage : elle échoue plus tard, sur la connexion, avec un message qui oriente vers le réseau plutôt que vers la variable manquante.

**Cause racine** : une configuration de production modifiée manuellement, sans validation automatique ni au déploiement ni au démarrage de l'API.

### Ce qui a bien fonctionné

- Les alertes `TaskFlowApiDown` et `TaskFlowMetricsDown` se sont déclenchées en une minute et sont arrivées par mail.
- Les logs structurés en JSON contenaient un indice (`hint`) qui pointait directement vers `DATABASE_URL`.
- La recréation de l'API avec `.deployed_tag` a remis exactement la même version, sans redéploiement complet.
- La base de données, isolée dans son propre conteneur, n'a pas été touchée.

### Ce qui a moins bien fonctionné

- Le message `ECONNREFUSED` laisse d'abord penser à une base arrêtée ou à un problème réseau.
- Aucun contrôle n'a empêché le démarrage avec une configuration incomplète.
- Une sauvegarde `.env.bak`, contenant le mot de passe de la base, traînait sur le serveur.
- Un rollback de l'image n'aurait servi à rien : la nouvelle image et l'ancienne lisent le même `.env`.

### Actions correctives

| # | Action | Type | Responsable | Échéance | Suivi |
|---|--------|------|-------------|----------|-------|
| 1 | L'API refuse de démarrer en production si `DATABASE_URL` est absente, avec un message explicite | Prévention | Antoine | Prochain sprint | Issue GitHub #30 |
| 2 | `deploy.sh` compare les clés du `.env` à `.env.example` et bloque le déploiement s'il en manque une | Prévention | Antoine | Prochain sprint | à créer |
| 3 | Ajouter une alerte sur les redémarrages en boucle d'un conteneur | Détection | Antoine | Plus tard | à créer |
| 4 | Ne jamais laisser de copie du `.env` sur le serveur (`.env.bak`) | Hygiène | Équipe | Immédiat | fait |
