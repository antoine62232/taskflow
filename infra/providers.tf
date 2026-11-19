# Le provider lit DOCKER_HOST s'il est défini (Podman, Docker distant via ssh://),
# sinon il utilise unix:///var/run/docker.sock.
provider "docker" {
  # Authentification à ghcr.io, seulement si un jeton est fourni (paquets privés).
  # Dans le pipeline : TF_VAR_ghcr_token = secrets.GITHUB_TOKEN. Le jeton sert à
  # configurer le provider : il n'est PAS écrit dans le state.
  dynamic "registry_auth" {
    for_each = var.ghcr_token == null ? [] : [1]
    content {
      address  = "ghcr.io"
      username = var.ghcr_username
      password = var.ghcr_token
    }
  }
}
