variable "location" {
  description = "Azure location to create resources in"
  type        = string
  default     = "eastus"
}

variable "prefix" {
  description = "Prefix used for resource names"
  type        = string
  default     = "tfexample"
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_key" {
  description = "Public SSH key (OpenSSH format) for the VM. Required."
  type        = string
}

variable "vm_size" {
  description = "Size of the VM"
  type        = string
  default     = "Standard_B1s"
}

# 
variable "owner" {
  description = "Owner name for tagging resources"
  type        = string
  default     = "dev"
}

variable "environment" {
  description = "Environment tag (e.g. dev, staging, prod)"
  type        = string
  default     = "tf-test"
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}
