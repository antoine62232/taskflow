# infra/ : le staging de TaskFlow en OpenTofu

Ce dossier décrit l'environnement **staging** (le même que la stack Compose du Jour 3) avec le provider
[`kreuzwerker/docker`](https://search.opentofu.org/provider/kreuzwerker/docker/latest).

| Ressource | Nom Docker |
|---|---|
| `docker_network.this` | `taskflow-staging` |
| `docker_volume.pgdata` | `taskflow-staging-pgdata` |
| `docker_container.db` / `.api` / `.front` | `taskflow-staging-db` / `-api` / `-front` (front sur `var.front_port`, 8081) |
| `random_password.db` | mot de passe PostgreSQL, **stocké dans le state** |

## Utilisation locale

```bash
cd infra
export STAGING_DIR="$HOME/taskflow-staging"; mkdir -p "$STAGING_DIR"
tofu init -backend-config="path=$STAGING_DIR/terraform.tfstate"
tofu plan  -var ghcr_owner=<vous-en-minuscules> -var image_tag=<sha7>
tofu apply -var ghcr_owner=<vous-en-minuscules> -var image_tag=<sha7>
curl -s "$(tofu output -raw health_url)"
tofu destroy -var ghcr_owner=<vous-en-minuscules>      # supprime aussi le volume (données de staging)
```

Images privées sur ghcr.io : `export TF_VAR_ghcr_username=<vous> TF_VAR_ghcr_token=<PAT read:packages>`.

## Ce qui est versionné, ce qui ne l'est pas

| Versionné | Jamais versionné (`.gitignore`) |
|---|---|
| `*.tf`, `terraform.tfvars.example`, **`.terraform.lock.hcl`** (versions exactes et empreintes des providers, pour 5 plateformes) | `terraform.tfstate*` (contient le mot de passe de la base), `.terraform/` (binaires des providers), `terraform.tfvars`, `tfplan` |

Mettre à jour les providers : `tofu init -upgrade` puis
`tofu providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_amd64 -platform=darwin_arm64 -platform=windows_amd64`.

## Dans le pipeline

- `.github/workflows/iac.yml` : sur une PR qui touche `infra/**` : `fmt -check`, `validate`, puis `plan` contre le **vrai** state du staging (runner self-hosted), publié dans le résumé du job et en commentaire de PR.
- `release.yml`, job `deploy-staging` : `tofu apply` du plan avec `image_tag` = SHA court, puis smoke test sur `:8081/health`.

## En vrai (cloud, équipe)

Le state local suffit pour un poste et un runner. En équipe, on le met dans un **backend distant avec verrou**, par exemple :

```hcl
terraform {
  backend "s3" {
    bucket       = "taskflow-tfstate"
    key          = "staging/terraform.tfstate"
    region       = "eu-west-3"
    use_lockfile = true # verrou natif S3 (avant : table DynamoDB)
    encrypt      = true
  }
}
```

Podman (et non Docker Engine) : le provider voit des différences permanentes (`ipam_options`, `ulimit`, `pid_mode`) et
propose de tout recréer à chaque `plan`. Ce n'est pas un problème du code : utilisez Docker Engine pour ce TP.
