# =============================================================================
# variables.tf : les entrées du module. Valeurs dans terraform.tfvars (local),
# -var en ligne de commande, ou variables d'environnement TF_VAR_<nom> (CI).
# =============================================================================

variable "ghcr_owner" {
  description = "Propriétaire des images sur ghcr.io, en minuscules (ex. : alice-cda)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.ghcr_owner))
    error_message = "ghcr_owner doit être en minuscules (ghcr.io refuse les majuscules)."
  }
}

variable "image_tag" {
  description = "Tag des images à déployer : SHA court du commit (7 caractères) ou latest."
  type        = string
  default     = "latest"

  validation {
    condition     = can(regex("^([0-9a-f]{7}|latest)$", var.image_tag))
    error_message = "image_tag doit être un SHA court de 7 caractères hexadécimaux ou « latest »."
  }
}

variable "front_port" {
  description = "Port publié sur le poste pour le front du staging."
  type        = number
  default     = 8081

  validation {
    condition     = var.front_port >= 1024 && var.front_port <= 65535
    error_message = "front_port doit être un port non privilégié (1024-65535)."
  }
}

variable "environment" {
  description = "Nom de l'environnement : préfixe des ressources et valeur de APP_ENV."
  type        = string
  default     = "staging"
}

variable "ghcr_username" {
  description = "Utilisateur ghcr.io (github.actor dans le pipeline)."
  type        = string
  default     = null
}

variable "ghcr_token" {
  description = "Jeton de lecture ghcr.io (GITHUB_TOKEN dans le pipeline). null = images publiques ou déjà présentes."
  type        = string
  default     = null
  sensitive   = true
}

variable "db_password" {
  description = "Mot de passe PostgreSQL imposé (ex. : celui du staging Compose du Jour 3, dont le volume est déjà initialisé). null = mot de passe aléatoire généré par OpenTofu."
  type        = string
  default     = null
  sensitive   = true
}
