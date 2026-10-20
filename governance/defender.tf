# Security contact for Defender for Cloud (SEC-021). Without it, a High
# severity alert reaches no one. The email comes from a variable so it is not
# stored in this public repository; it is kept in the state, which only
# Entra ID identities with a role on the state account can read (ADR-005).
resource "azurerm_security_center_contact" "main" {
  #checkov:skip=CKV_AZURE_20:Lab accepted risk. The phone is only for Microsoft to call about a confirmed compromise, not for alerts. Email covers the Defender recommendations; production uses a security team number, not a personal one.
  name                = "default1"
  email               = var.security_contact_email
  alert_notifications = true
  alerts_to_admins    = true
}