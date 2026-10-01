variable "kv_public_access_effect" {
  description = "Effect of the Key Vault public network access policy. Roll out as Audit, switch to Deny once existing vaults comply."
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.kv_public_access_effect)
    error_message = "The effect must be Audit, Deny or Disabled."
  }
}