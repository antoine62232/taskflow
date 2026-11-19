# =============================================================================
# main.tf : l'environnement « staging » de TaskFlow, décrit en code.
#
# Mêmes noms que la stack Compose du Jour 3, pour que le staging reste le même :
#   réseau    taskflow-staging
#   volume    taskflow-staging-pgdata
#   conteneurs taskflow-staging-db | -api | -front   (front publié sur var.front_port)
#
#   tofu init -backend-config="path=$STAGING_DIR/terraform.tfstate"
#   tofu plan  -var ghcr_owner=<vous> -var image_tag=<sha>
#   tofu apply -var ghcr_owner=<vous> -var image_tag=<sha>
# =============================================================================

locals {
  prefix    = "taskflow-${var.environment}"
  api_image = "ghcr.io/${var.ghcr_owner}/taskflow-api:${var.image_tag}"
  # Le front et l'API sont publiés ensemble, avec le même tag
  front_image = "ghcr.io/${var.ghcr_owner}/taskflow-front:${var.image_tag}"
  # PostgreSQL n'utilise POSTGRES_PASSWORD qu'à l'initialisation d'un volume VIDE :
  # si le volume existe déjà (staging Compose du Jour 3), il faut reprendre son mot de passe.
  db_password = var.db_password != null ? var.db_password : random_password.db.result
}

# ---------- Réseau et stockage ------------------------------------------------

resource "docker_network" "this" {
  name = local.prefix
}

resource "docker_volume" "pgdata" {
  name = "${local.prefix}-pgdata"

  # Le volume du staging Compose (Jour 3) est REPRIS par « tofu import » : il porte
  # des labels com.docker.compose.*. Les labels d'un volume ne se modifient pas :
  # sans cette ligne, OpenTofu voudrait le DÉTRUIRE et le recréer (perte des données).
  lifecycle {
    ignore_changes = [labels]
  }
  # En production, on ajouterait un garde-fou contre la perte de données :
  #   lifecycle { prevent_destroy = true }
  # (tofu destroy échoue tant que la ligne est là). Inutile pour un staging jetable.
}

resource "random_password" "db" {
  length  = 32
  special = false # le mot de passe est réutilisé dans une URL (DATABASE_URL)
}

# ---------- Images --------------------------------------------------------------
# docker_image télécharge l'image (pull). keep_locally : un « destroy » ne
# supprime pas l'image du poste (utile pour revenir vite à une version).

resource "docker_image" "db" {
  name         = "docker.io/library/postgres:16-alpine"
  keep_locally = true
}

resource "docker_image" "api" {
  name         = local.api_image
  keep_locally = true
}

resource "docker_image" "front" {
  name         = local.front_image
  keep_locally = true
}

# ---------- Conteneurs ------------------------------------------------------------

resource "docker_container" "db" {
  name    = "${local.prefix}-db"
  image   = docker_image.db.image_id
  restart = "unless-stopped"

  env = [
    "POSTGRES_USER=taskflow",
    "POSTGRES_PASSWORD=${local.db_password}",
    "POSTGRES_DB=taskflow",
  ]

  volumes {
    volume_name    = docker_volume.pgdata.name
    container_path = "/var/lib/postgresql/data"
  }

  # L'alias « db » : l'API se connecte à db:5432, comme dans Compose.
  networks_advanced {
    name    = docker_network.this.id
    aliases = ["db"]
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U taskflow -d taskflow"]
    interval = "5s"
    timeout  = "3s"
    retries  = 10
  }

  # apply attend que la base soit « healthy » avant de créer l'API
  # (l'équivalent de depends_on: condition: service_healthy).
  wait         = true
  wait_timeout = 90
}

resource "docker_container" "api" {
  name    = "${local.prefix}-api"
  image   = docker_image.api.image_id
  restart = "unless-stopped"

  env = [
    "PORT=3000",
    "APP_ENV=${var.environment}",
    "DATABASE_URL=postgres://taskflow:${local.db_password}@db:5432/taskflow",
  ]

  # Pas de ports : l'API n'est joignable que par le front, sur le réseau privé.
  networks_advanced {
    name    = docker_network.this.id
    aliases = ["api"] # nom attendu par front/nginx.conf
  }

  # Même sonde que le HEALTHCHECK de api/Dockerfile, répétée ici : « wait »
  # l'exige, et certaines images (format OCI, construites par Podman) le perdent.
  healthcheck {
    test         = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1:3000/health || exit 1"]
    interval     = "5s"
    timeout      = "3s"
    retries      = 10
    start_period = "5s"
  }

  wait         = true
  wait_timeout = 90

  depends_on = [docker_container.db]
}

resource "docker_container" "front" {
  name    = "${local.prefix}-front"
  image   = docker_image.front.image_id
  restart = "unless-stopped"

  ports {
    internal = 80
    external = var.front_port
  }

  networks_advanced {
    name    = docker_network.this.id
    aliases = ["front"]
  }

  healthcheck {
    test     = ["CMD-SHELL", "wget -q -O /dev/null http://127.0.0.1/ || exit 1"]
    interval = "10s"
    timeout  = "3s"
    retries  = 3
  }

  depends_on = [docker_container.api]
}
