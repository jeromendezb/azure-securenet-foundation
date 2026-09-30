#!/usr/bin/env bash
# Checks network reachability to the Key Vault private endpoint without authenticating.
# 401 = the request reached the vault (network path open).
# 000 = no response within the timeout (blocked by the network).
set -uo pipefail
VAULT="kv-securenet-dev-eus-001"
echo "Resolves to: $(getent hosts ${VAULT}.vault.azure.net | awk '{print $1}')"
curl -s -o /dev/null -m 10 -w "HTTP status: %{http_code}  Time: %{time_total}s\n" \
  "https://${VAULT}.vault.azure.net/secrets?api-version=7.4"