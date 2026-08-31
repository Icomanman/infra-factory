#!/usr/bin/env bash
set -euo pipefail

if [ -f "$(dirname "$0")/.env" ]; then
  # export all variables from the .env file
  set -o allexport
  # shellcheck disable=SC1091
  source "$(dirname "$0")/.env"
  set +o allexport
  echo "Loaded variables from .env"
fi

for v in admin_ssh_key subscription_id; do
  val="${!v-}"
  if [ -n "$val" ]; then
    export "TF_VAR_${v}=$val"
  fi
done

echo "Initializing Terraform..."
terraform init

echo "Destroying Terraform-managed resources..."
# terraform destroy -auto-approve
terraform destroy -auto-approve

echo "Destroy complete."
