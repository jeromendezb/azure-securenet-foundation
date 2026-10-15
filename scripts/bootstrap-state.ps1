# Creates the storage account that holds the Terraform state (ADR-005).
# Run once, before the first `terraform init` with the azurerm backend.
# Safe to run again: anything that already exists is left as it is.
# Requires: Azure CLI, signed in (`az login`) with an account that can create
# resources and role assignments in the subscription.

param(
    [string]$Location           = "eastus",
    [string]$ResourceGroupName  = "rg-securenet-tfstate-dev-eus-001",
    [string]$StorageAccountName = "stsecurenettfstate001",
    [string]$ContainerName      = "tfstate"
)

# Azure CLI is an external program: PowerShell does not stop when it fails,
# so every call that must succeed goes through this check.
function Invoke-Az {
    $output = & az @args
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed: az $($args -join ' ')" }
    return $output
}

$tags = @("project=securenet", "environment=dev", "owner=jeromendezb", "managed_by=bootstrap-script")

# 1. Resource group, separate from the workload and from governance/.
Write-Host "1/5 Resource group $ResourceGroupName"
Invoke-Az group create --name $ResourceGroupName --location $Location --tags $tags --output none

# 2. Storage account. Created only if it does not exist yet.
Write-Host "2/5 Storage account $StorageAccountName"
$existingId = az storage account show --name $StorageAccountName --resource-group $ResourceGroupName --query id --output tsv 2>$null
if (-not $existingId) {
    # Storage account names are global across all of Azure.
    $available = Invoke-Az storage account check-name --name $StorageAccountName --query nameAvailable --output tsv
    if ($available -ne "true") {
        throw "The name $StorageAccountName is taken. Run again with -StorageAccountName <another name> (3-24 lowercase letters and digits)."
    }
    # No shared keys (Entra ID only), no anonymous blob access, HTTPS with TLS 1.2 or later.
    Invoke-Az storage account create `
        --name $StorageAccountName `
        --resource-group $ResourceGroupName `
        --location $Location `
        --sku Standard_LRS `
        --kind StorageV2 `
        --https-only true `
        --min-tls-version TLS1_2 `
        --allow-blob-public-access false `
        --allow-shared-key-access false `
        --tags $tags `
        --output none
} else {
    Write-Host "    Already exists, left unchanged."
}

# 3. Recovery: keep previous versions of the state and recover deleted blobs or containers for 7 days.
Write-Host "3/5 Versioning and soft delete"
Invoke-Az storage account blob-service-properties update `
    --account-name $StorageAccountName `
    --resource-group $ResourceGroupName `
    --enable-versioning true `
    --enable-delete-retention true `
    --delete-retention-days 7 `
    --enable-container-delete-retention true `
    --container-delete-retention-days 7 `
    --output none

# 4. Data access for the signed-in operator only, scoped to this account.
Write-Host "4/5 Role assignment for the signed-in user"
$userId    = Invoke-Az ad signed-in-user show --query id --output tsv
$accountId = Invoke-Az storage account show --name $StorageAccountName --resource-group $ResourceGroupName --query id --output tsv
$existingRole = Invoke-Az role assignment list --assignee $userId --scope $accountId --role "Storage Blob Data Contributor" --query "[].id" --output tsv
if (-not $existingRole) {
    Invoke-Az role assignment create `
        --assignee-object-id $userId `
        --assignee-principal-type User `
        --role "Storage Blob Data Contributor" `
        --scope $accountId `
        --output none
} else {
    Write-Host "    Already assigned."
}

# 5. Container for the state files. A new role assignment can take a few
#    minutes to apply, so the first attempts may be denied; retry until it works.
Write-Host "5/5 Container $ContainerName"
$created = $false
for ($attempt = 1; $attempt -le 10; $attempt++) {
    az storage container create --name $ContainerName --account-name $StorageAccountName --auth-mode login --output none 2>$null
    if ($LASTEXITCODE -eq 0) { $created = $true; break }
    Write-Host "    Attempt $attempt denied, waiting 30 s for the role to apply..."
    Start-Sleep -Seconds 30
}
if (-not $created) { throw "Could not create the container. Check the role assignment and run the script again." }

Write-Host ""
Write-Host "Done. Backend values for both roots:"
Write-Host "  resource_group_name  = $ResourceGroupName"
Write-Host "  storage_account_name = $StorageAccountName"
Write-Host "  container_name       = $ContainerName"