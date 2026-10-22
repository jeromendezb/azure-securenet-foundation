variable "kv_public_access_effect" {
  description = "Effect of the Key Vault public network access policy. Roll out as Audit, switch to Deny once existing vaults comply."
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.kv_public_access_effect)
    error_message = "The effect must be Audit, Deny or Disabled."
  }
}

variable "location" {
  description = "Azure region for the monitoring resources."
  type        = string
  default     = "eastus"
}

variable "security_contact_email" {
  description = "Email that receives Defender for Cloud alerts. Set through TF_VAR_security_contact_email; never stored in the repository."
  type        = string
  sensitive   = true
}

variable "operators_group_object_id" {
  description = "Object ID of the sg-securenet-operators Entra ID group (TKT-004)."
  type        = string
}

variable "developers_group_object_id" {
  description = "Object ID of the sg-securenet-developers Entra ID group (TKT-004)."
  type        = string
}