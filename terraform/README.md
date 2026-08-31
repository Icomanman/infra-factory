
# Beginner: single Resource Group and VM (Azure)

This simplified example creates a single Azure Resource Group and one Ubuntu Linux VM (with the minimal networking required).

Prerequisites
- Terraform >= 1.0
- Azure CLI (for `az login`) or service principal env vars

Authenticate (interactive - easiest for learning):

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID_OR_NAME>"
```

Quick steps (recommended)

1. Export your SSH public key so Terraform can set the VM's admin key. Replace the example with your actual public key:

```bash
export TF_VAR_admin_ssh_key='ssh-rsa AAAA... your-public-key ... user@host'
```

2. Create resources (run from this folder):

```bash
./create.sh
```

3. Connect to the VM (after `apply` finishes, Terraform prints the IP and suggested ssh command):

```bash
ssh azureuser@<IP_FROM_OUTPUT>
```

4. Destroy resources when finished:

```bash
./destroy.sh
```

Notes
- `admin_ssh_key` is required. You can also pass it via `-var 'admin_ssh_key="..."'`, but exporting `TF_VAR_admin_ssh_key` is easier for repeated runs.
- Scripts call `terraform init` automatically; they run `apply`/`destroy` with `-auto-approve` for simplicity. Review the plan output if you want to inspect changes before applying.

