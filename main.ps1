# ============================================================
# FULL SCRIPT: Create Workspace → Scan → Enable Diagnostics → Export CSV
# ============================================================
# ============================================================
# KEEP-ALIVE: Prevents Cloud Shell timeout during long scans
# ============================================================
$keepAliveJob = Start-Job -ScriptBlock {
while ($true) {
Start-Sleep -Seconds 240
Write-Output " [keep-alive] Still running..."
}
}

# ============================================================
# STEP 1: Check for Existing Log Analytics Workspaces
# ============================================================

Write-Host "Checking for existing Log Analytics workspaces..." -ForegroundColor Cyan
$existingWorkspaces = Get-AzOperationalInsightsWorkspace -ErrorAction SilentlyContinue
$skipWorkspaceCreation = $false
if ($existingWorkspaces -and $existingWorkspaces.Count -gt 0) {
Write-Host " Found $($existingWorkspaces.Count) existing workspace(s):" -ForegroundColor Yellow
$i = 1
foreach ($ws in $existingWorkspaces) {
Write-Host " [$i] $($ws.Name) | RG: $($ws.ResourceGroupName) | Location: $($ws.Location)" -ForegroundColor Gray
$i++
}
Write-Host "Would you like to:" -ForegroundColor Cyan
Write-Host " [1] Connect resources to an existing workspace" -ForegroundColor White
Write-Host " [2] Create a new workspace" -ForegroundColor White
$wsChoice = Read-Host "Enter 1 or 2"
if ($wsChoice -eq "1") {
$wsIndex = Read-Host "Enter the number of the workspace you want to use"
if ($wsIndex -match '^\d+$' -and
[int]$wsIndex -ge 1 -and
[int]$wsIndex -le $existingWorkspaces.Count) {
$selectedWs = $existingWorkspaces[[int]$wsIndex - 1]
$workspaceId = $selectedWs.ResourceId
$workspaceName = $selectedWs.Name
$workspaceRG = $selectedWs.ResourceGroupName
$skipWorkspaceCreation = $true
Write-Host " [OK] Using existing workspace: $workspaceName" -ForegroundColor Green
Write-Host " Workspace ID: $workspaceId" -ForegroundColor DarkCyan
} else {
Write-Warning "Invalid selection. Please re-run the script."
Stop-Job $keepAliveJob | Out-Null
exit
}
} elseif ($wsChoice -eq "2") {
Write-Host " Proceeding to create a new workspace..." -ForegroundColor Green
$skipWorkspaceCreation = $false
} else {
Write-Warning "Invalid choice. Please re-run the script and enter 1 or 2."
Stop-Job $keepAliveJob | Out-Null
exit
}
} else { Write-Host " No existing workspaces found. A new one will be created." -ForegroundColor Gray
$skipWorkspaceCreation = $false
}
# ============================================================
# STEP 2: Interactive Workspace Setup (only if needed)
# ============================================================
if (-not $skipWorkspaceCreation) {
# --- Workspace Name ---
$defaultName = "log-diagnostics-$(Get-Date -Format 'yyyyMMddHHmmss')"
Write-Host "Default workspace name: $defaultName" -ForegroundColor Cyan
$customName = Read-Host "Would you like to use a custom name instead? (yes/no)"
if ($customName -eq "yes") {
$workspaceName = Read-Host "Enter your desired workspace name"
} else {
$workspaceName = $defaultName
}
Write-Host "Workspace name set to: $workspaceName" -ForegroundColor Green
# --- Resource Group ---
Write-Host "Which resource group should the Log Analytics workspace be created in?" -ForegroundColor Cyan
$rgChoice = Read-Host "Type 'same' to use an existing resource group, or 'different' for a new/separate one"
if ($rgChoice -eq "same") {
$resourceGroups = Get-AzResourceGroup
Write-Host "Available Resource Groups:" -ForegroundColor Cyan
$i = 1
foreach ($rg in $resourceGroups) {
Write-Host " [$i] $($rg.ResourceGroupName)" -ForegroundColor Gray
$i++
}
$rgIndex = Read-Host "Enter the number of the resource group you want to use"
if ($rgIndex -match '^\d+$' -and
[int]$rgIndex -ge 1 -and
[int]$rgIndex -le $resourceGroups.Count) {
$workspaceRG = $resourceGroups[[int]$rgIndex - 1].ResourceGroupName
Write-Host " Selected: $workspaceRG" -ForegroundColor Green
} else {
Write-Warning "Invalid selection. Please re-run the script and enter a valid number."
Stop-Job $keepAliveJob | Out-Null
exit
}
} elseif ($rgChoice -eq "different") {
Write-Host "Would you like to name the new resource group 'rg-monitoring' or something else?" -ForegroundColor Cyan
$rgNameChoice = Read-Host "Type 'rg-monitoring' to use that, or 'custom' to enter your own"
if ($rgNameChoice -eq "rg-monitoring") {
$workspaceRG = "rg-monitoring"
} else {
$workspaceRG = Read-Host "Enter your desired resource group name"
}
$location = Read-Host "Enter the Azure region for the new resource group (e.g. eastus, westus2)"
Write-Host "Creating resource group '$workspaceRG' in '$location'..." -ForegroundColor Cyan
try {
New-AzResourceGroup -Name $workspaceRG -Location $location -ErrorAction Stop | Out-Null
Write-Host " [OK] Resource group '$workspaceRG' created." -ForegroundColor Green
} catch {
Write-Warning " [FAILED] Could not create resource group: $_"
Stop-Job $keepAliveJob | Out-Null
exit
}
} else {
Write-Warning "Invalid choice. Please re-run the script and type 'same' or 'different'."
Stop-Job $keepAliveJob | Out-Null
exit
}
# ============================================================
# STEP 3: Create the Log Analytics Workspace
# ============================================================
Write-Host "Creating Log Analytics Workspace '$workspaceName' in '$workspaceRG'..." -ForegroundColor Cyan
try {
$rgLocation = (Get-AzResourceGroup -Name $workspaceRG).Location
$workspace = New-AzOperationalInsightsWorkspace `
-ResourceGroupName $workspaceRG `
-Name $workspaceName `
-Location $rgLocation `
-Sku PerGB2018 `
-ErrorAction Stop
$workspaceId = $workspace.ResourceId
Write-Host " [OK] Workspace created." -ForegroundColor Green
Write-Host " Workspace ID: $workspaceId" -ForegroundColor DarkCyan
} catch {
Write-Warning " [FAILED] Could not create Log Analytics Workspace: $_"
Stop-Job $keepAliveJob | Out-Null
exit
}
}
# ============================================================
# STEP 4: Scan all resources in the subscription
# ============================================================
Write-Host "Scanning all resources in subscription..." -ForegroundColor Cyan
Write-Host "(Progress updates every 10 resources)" -ForegroundColor Gray
$allResources = Get-AzResource
$results = @()
$processed = 0
foreach ($resource in $allResources) {
$azureMonitorSupported = $false
$diagnosticsEnabled = $false
$sendingToLogAnalytics = $false
# Check if Monitor is supported
try {
$categories = Get-AzDiagnosticSettingCategory `
-ResourceId $resource.ResourceId -ErrorAction Stop
if ($categories -and $categories.Count -gt 0) {
$azureMonitorSupported = $true
}
} catch {
$azureMonitorSupported = $false
}
# If supported, check if diagnostics are already enabled
if ($azureMonitorSupported) {
try {
$diagSettings = Get-AzDiagnosticSetting `
-ResourceId $resource.ResourceId -ErrorAction Stop
if ($diagSettings -and $diagSettings.Count -gt 0) {
$diagnosticsEnabled = $true
$sendingToLogAnalytics = ($diagSettings | Where-Object { $_.WorkspaceId -ne $null }) -ne $null
}
} catch {
$diagnosticsEnabled = $false
$sendingToLogAnalytics = $false
}
}
$results += [PSCustomObject]@{
ResourceName = $resource.Name
ResourceType = $resource.ResourceType
ResourceGroup = $resource.ResourceGroupName
ResourceId = $resource.ResourceId
AzureMonitorSupported = $azureMonitorSupported
DiagnosticsEnabled = $diagnosticsEnabled
SendingToLogAnalytics = $sendingToLogAnalytics
}
$processed++
# Progress update every 10 resources (keeps session alive)
if ($processed % 10 -eq 0) {
Write-Host " Scanned $processed / $($allResources.Count) resources..." -ForegroundColor DarkGray
}
}
Write-Host "Scan complete. Total resources: $($results.Count)" -ForegroundColor Cyan

# After building $results, split into VM vs non-VM. Needed for AMA architecture modernization.
$vmResources = $results | Where-Object {
    $_.ResourceType -eq "Microsoft.Compute/virtualMachines"
}

#to $_.DiagnosticsEnabled -eq $false -and , to avoid duplicate diagnostic settings per resource.
$nonVmResources = $results | Where-Object {
    $_.ResourceType -ne "Microsoft.Compute/virtualMachines" -and
    $_.AzureMonitorSupported -eq $true -and
    $_.DiagnosticsEnabled -eq $false -and
    $_.ResourceType -ne "Microsoft.OperationalInsights/workspaces" -and
    $_.ResourceType -notlike "*/projects"
}

Write-Host " VMs eligible for AMA: $($vmResources.Count)" -ForegroundColor Cyan
Write-Host " Non-VM resources eligible for Diagnostic Settings: $($nonVmResources.Count)" -ForegroundColor Cyan

# ============================================================
# STEP 5: Enable diagnostics on eligible resources change up $_.DiagnosticsEnabled -eq $true -and
# ============================================================

Write-Host "Eligible for diagnostics: $($nonVmResources.Count)" -ForegroundColor Cyan
foreach ($resource in $nonVmResources) {
Write-Host " Processing: $($resource.ResourceName)" -ForegroundColor Yellow
# Get diagnostic categories
try {
$categories = Get-AzDiagnosticSettingCategory `
-ResourceId $resource.ResourceId -ErrorAction Stop
} catch {
Write-Warning " [SKIP] Could not get categories for $($resource.ResourceName): $_"
continue
}
if (-not $categories -or $categories.Count -eq 0) {
Write-Warning " [SKIP] No categories found for $($resource.ResourceName)."
continue
}
# Build log settings
$logSettings = @()
foreach ($cat in ($categories | Where-Object { $_.CategoryType -eq "Logs" })) {
$logSettings += New-AzDiagnosticSettingLogSettingsObject `
-Category $cat.Name `
-Enabled $true `
-RetentionPolicyDay 0 `
-RetentionPolicyEnabled $false
}
# Build metric settings
$metricSettings = @()
foreach ($cat in ($categories | Where-Object { $_.CategoryType -eq "Metrics" })) {
$metricSettings += New-AzDiagnosticSettingMetricSettingsObject `
-Category $cat.Name `
-Enabled $true `
-RetentionPolicyDay 0 `
-RetentionPolicyEnabled $false
}
if ($logSettings.Count -eq 0 -and $metricSettings.Count -eq 0) {
Write-Warning " [SKIP] No log or metric objects built for $($resource.ResourceName)."
continue
}
# Apply diagnostic setting
try {
$diagParams = @{
Name = "diag-to-log-$(Get-Date -Format 'yyyyMMddHHmmss')"
ResourceId = $resource.ResourceId
WorkspaceId = $workspaceId
}
if ($logSettings.Count -gt 0) { $diagParams["Log"] = $logSettings }
if ($metricSettings.Count -gt 0) { $diagParams["Metric"] = $metricSettings }
New-AzDiagnosticSetting @diagParams -ErrorAction Stop | Out-Null
Write-Host " [OK] Diagnostics enabled for $($resource.ResourceName)" -ForegroundColor Green
} catch {
Write-Warning " [FAILED] $($resource.ResourceName): $_"
}
}

# ============================================================
# STEP 5B: AMA — Install Agent + Create DCR for VMs
# ============================================================

# Get auth token once — used for DCR creation (B2) and DCRA verification (Step 6)
$token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token | ConvertFrom-SecureString -AsPlainText
$headers = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }


# --- B1: Install AMA on each eligible VM ---
foreach ($vm in $vmResources) {

    # Get full VM object — needed for OS type, location, and identity check
    $vmObj = Get-AzVM -ResourceGroupName $vm.ResourceGroup -Name $vm.ResourceName

    # Ensure VM has system-assigned managed identity — required for AMA to authenticate
    if ($vmObj.Identity.Type -notlike "*SystemAssigned*") {
        Write-Host "  Enabling system-assigned identity on $($vm.ResourceName)..." -ForegroundColor Yellow
        Update-AzVM -ResourceGroupName $vm.ResourceGroup -VM $vmObj -IdentityType SystemAssigned | Out-Null
        Write-Host "  [OK] Identity enabled on $($vm.ResourceName)" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Identity already enabled on $($vm.ResourceName)" -ForegroundColor Gray
    }

    # Determine OS type to pick the correct AMA extension name
    $osType    = $vmObj.StorageProfile.OsDisk.OsType
    $extName   = if ($osType -eq "Windows") { "AzureMonitorWindowsAgent" } else { "AzureMonitorLinuxAgent" }
    $publisher = "Microsoft.Azure.Monitor"
    $extType   = $extName

    # Check if AMA extension is already installed — avoid reinstalling
    $existingExt = Get-AzVMExtension `
        -ResourceGroupName $vm.ResourceGroup `
        -VMName           $vm.ResourceName `
        -Name             $extName `
        -ErrorAction      SilentlyContinue

    if (-not $existingExt) {
        Write-Host "  Installing $extName on $($vm.ResourceName)..." -ForegroundColor Yellow
        Set-AzVMExtension `
            -ResourceGroupName   $vm.ResourceGroup `
            -VMName              $vm.ResourceName `
            -Name                $extName `
            -Publisher           $publisher `
            -ExtensionType       $extType `
            -TypeHandlerVersion  "1.0" `
            -Location            $vmObj.Location `
            -EnableAutomaticUpgrade $true `
            -ErrorAction         Stop | Out-Null
        Write-Host "  [OK] AMA installed on $($vm.ResourceName)" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] AMA already installed on $($vm.ResourceName)" -ForegroundColor Gray
    }
}


# --- B2: Create DCR (once, shared across all VMs) ---
# DCR targets your existing Log Analytics workspace
if ($vmResources.Count -gt 0) {
$dcrName = "dcr-ama-$(Get-Date -Format 'MMddyyyy')"
$dcrLocation = (Get-AzResourceGroup -Name $workspaceRG).Location

$dcrBody = @{
    location   = $dcrLocation
    properties = @{
        destinations = @{
            logAnalytics = @(
                @{
                    workspaceResourceId = $workspaceId
                    name                = "lawDestination"
                }
            )
        }
        dataFlows = @(
            @{
                streams      = @("Microsoft-Event", "Microsoft-Syslog", "Microsoft-Perf")
                destinations = @("lawDestination")
            }
        )
        dataSources = @{
            performanceCounters = @(
                @{
                    name                    = "perfCounters"
                    streams                 = @("Microsoft-Perf")
                    samplingFrequencyInSeconds = 60
                    counterSpecifiers       = @(
                        "\\Processor(_Total)\\% Processor Time",
                        "\\Memory\\Available MBytes",
                        "\\LogicalDisk(_Total)\\Disk Read Bytes/sec",
                        "\\LogicalDisk(_Total)\\Disk Write Bytes/sec"
                    )
                }
            )
            windowsEventLogs = @(
                @{
                    name    = "windowsEventLogs"
                    streams = @("Microsoft-Event")
                    xPathQueries = @("System!*[System[(Level=1 or Level=2 or Level=3)]]", "Application!*[System[(Level=1 or Level=2)]]")
                }
            )
            syslog = @(
                @{
                    name       = "syslogDataSource"
                    streams    = @("Microsoft-Syslog")
                    facilityNames = @("auth", "cron", "daemon", "kern", "syslog")
                    logLevels  = @("Error", "Critical", "Alert", "Emergency")
                }
            )
        }
    }
} | ConvertTo-Json -Depth 10

# Deploy DCR via REST
$subscriptionId = (Get-AzContext).Subscription.Id
$dcrRgEncoded   = [uri]::EscapeDataString($workspaceRG)
$dcrUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceRG/providers/Microsoft.Insights/dataCollectionRules/$($dcrName)?api-version=2022-06-01"

$token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token | ConvertFrom-SecureString -AsPlainText
$headers = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }

$dcrResponse = Invoke-RestMethod -Method Put -Uri $dcrUri -Headers $headers -Body $dcrBody
$dcrId = $dcrResponse.id
Write-Host " [OK] DCR created: $dcrName" -ForegroundColor Green
Write-Host "  DCR ID: $dcrId" -ForegroundColor DarkCyan



# ============================================================
# STEP 5C: Associate DCR to each VM (DCRA)
# ============================================================

foreach ($vm in $vmResources) {
    $dcraName = "dcra-$($vm.ResourceName)-$(Get-Date -Format 'MMddyyyy')"
    $dcraUri  = "https://management.azure.com$($vm.ResourceId)/providers/Microsoft.Insights/dataCollectionRuleAssociations/$($dcraName)?api-version=2022-06-01"

    $dcraBody = @{
        properties = @{
            dataCollectionRuleId = $dcrId
        }
    } | ConvertTo-Json -Depth 5

    try {
        Invoke-RestMethod -Method Put -Uri $dcraUri -Headers $headers -Body $dcraBody | Out-Null
        Write-Host "  [OK] DCR associated to $($vm.ResourceName)" -ForegroundColor Green
    } catch {
        Write-Warning "  [FAILED] Could not associate DCR to $($vm.ResourceName): $_"
    }
}
} else {
    Write-Host " [SKIP] No eligible VMs found. Skipping DCR creation." -ForegroundColor Gray
}
# ============================================================
# STEP 6: Re-scan and export updated status to CSV
# ============================================================

Write-Host "Re-scanning to verify final diagnostics status..." -ForegroundColor Cyan
$refreshedResults = @()
$token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token | ConvertFrom-SecureString -AsPlainText
$headers = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }
foreach ($resource in $results) {
$diagnosticsEnabled = $false
$sendingToLogAnalytics = $false
$azureMonitorSupported = $resource.AzureMonitorSupported
if ($azureMonitorSupported) {
try {
$diagSettings = Get-AzDiagnosticSetting `
-ResourceId $resource.ResourceId -ErrorAction Stop
if ($diagSettings -and $diagSettings.Count -gt 0) {
$diagnosticsEnabled = $true
$sendingToLogAnalytics = ($diagSettings | Where-Object { $_.WorkspaceId -ne $null }) -ne $null
}
} catch {
$azureMonitorSupported = $false
}
}

# Check AMA association for VMs
$amaInstalled = $false
$dcrAssociated = $false

if ($resource.ResourceType -eq "Microsoft.Compute/virtualMachines") {
    $winExt = Get-AzVMExtension -ResourceGroupName $resource.ResourceGroup `
                                 -VMName $resource.ResourceName `
                                 -Name "AzureMonitorWindowsAgent" -ErrorAction SilentlyContinue
    $linExt = Get-AzVMExtension -ResourceGroupName $resource.ResourceGroup `
                                 -VMName $resource.ResourceName `
                                 -Name "AzureMonitorLinuxAgent" -ErrorAction SilentlyContinue
    $amaInstalled = ($winExt -or $linExt) -ne $null

    # Check if a DCRA exists for this VM
    $dcraCheck = Invoke-RestMethod -Method Get `
        -Uri "https://management.azure.com$($resource.ResourceId)/providers/Microsoft.Insights/dataCollectionRuleAssociations?api-version=2022-06-01" `
        -Headers $headers -ErrorAction SilentlyContinue
    $dcrAssociated = ($dcraCheck.value.Count -gt 0)
}

$refreshedResults += [PSCustomObject]@{
    ResourceName          = $resource.ResourceName
    ResourceType          = $resource.ResourceType
    ResourceGroup         = $resource.ResourceGroup
    ResourceId            = $resource.ResourceId
    AzureMonitorSupported = $azureMonitorSupported
    DiagnosticsEnabled    = $diagnosticsEnabled
    SendingToLogAnalytics = $sendingToLogAnalytics
    AMAInstalled          = $amaInstalled      # NEW
    DCRAssociated         = $dcrAssociated     # NEW
}
}
$csvPath = Join-Path $PWD.Path "diagnostics-status-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$refreshedResults | Export-Csv -Path $csvPath -NoTypeInformation
# ============================================================
# STEP 7: Print summary
# ============================================================
$total         = $refreshedResults.Count
$diagEnabled   = ($refreshedResults | Where-Object { $_.DiagnosticsEnabled    -eq $true }).Count
$sendingToLOG  = ($refreshedResults | Where-Object { $_.SendingToLogAnalytics -eq $true }).Count
$notSupported  = ($refreshedResults | Where-Object { $_.AzureMonitorSupported -eq $false }).Count
$amaCount      = ($refreshedResults | Where-Object { $_.AMAInstalled          -eq $true }).Count
$dcrCount      = ($refreshedResults | Where-Object { $_.DCRAssociated         -eq $true }).Count
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Final Diagnostics Summary"                                    -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Total Resources          : $total"
Write-Host " Diagnostics Enabled      : $diagEnabled"                     -ForegroundColor Green
Write-Host " Sending to Log Analytics : $sendingToLOG"                    -ForegroundColor Green
Write-Host " AMA Installed (VMs)      : $amaCount"                        -ForegroundColor Green
Write-Host " DCR Associated (VMs)     : $dcrCount"                        -ForegroundColor Green
Write-Host " Monitor Not Supported    : $notSupported"                    -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Workspace Used           : $workspaceName"                   -ForegroundColor White
Write-Host " Workspace Resource ID    : $workspaceId"                     -ForegroundColor White
Write-Host " CSV saved to             : $csvPath"                         -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Stop-Job $keepAliveJob | Out-Null
download $csvPath
