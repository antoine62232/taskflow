# =============================================================================
# versions.tf : version d'OpenTofu, providers utilisés et backend du state.
# =============================================================================
terraform {
  # Ce code fonctionne avec OpenTofu 1.6 et plus (et Terraform 1.5+).
  required_version = ">= 1.6.0"

  required_providers {
    # Le provider Docker pilote le daemon Docker du poste (ou du runner) via son
    # socket : il crée réseaux, volumes, images et conteneurs comme le ferait
    # un provider AWS avec des VPC et des instances.
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.6"
    }
    # Génère le mot de passe PostgreSQL du staging (il vivra dans le state).
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # State local, mais HORS du dépôt : le chemin est donné à l'init.
  #   tofu init -backend-config="path=$STAGING_DIR/terraform.tfstate"
  # Sans -backend-config, le state est écrit ici (infra/terraform.tfstate), ignoré
  # par Git. En équipe ou dans le cloud, on utiliserait un backend distant avec
  # verrou (S3, GCS, azurerm, pg, http de GitLab...) : voir README.md.
  backend "local" {}
}
