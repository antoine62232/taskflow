# Les outputs s'affichent à la fin d'un apply, et se relisent avec :
#   tofu output            tofu output -raw url
output "url" {
  description = "Adresse du staging sur le poste."
  value       = "http://localhost:${var.front_port}"
}

output "health_url" {
  description = "Route lue par le smoke test."
  value       = "http://localhost:${var.front_port}/health"
}

output "image_tag" {
  description = "Version déployée (relue par iac.yml pour planifier sans changer de version)."
  value       = var.image_tag
}

output "containers" {
  description = "Noms des conteneurs créés."
  value       = [docker_container.db.name, docker_container.api.name, docker_container.front.name]
}

output "network" {
  description = "Réseau Docker du staging."
  value       = docker_network.this.name
}
