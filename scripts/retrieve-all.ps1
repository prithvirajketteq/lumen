param(
    [Parameter(Mandatory=$true)]
    [string]$OrgAlias
)

# STEP 1 - Confirm org alias
Write-Host "Verifying org connection for $OrgAlias..." -ForegroundColor Cyan
sf org display --target-org $OrgAlias 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Could not connect to org $OrgAlias. Check your alias and try again." -ForegroundColor Red
    exit 1
}
Write-Host "OK: Org $OrgAlias connected successfully." -ForegroundColor Green

# STEP 2 - Safety confirmation
Write-Host "WARNING: This will DELETE all local components in:" -ForegroundColor Yellow
Write-Host "  -> force-app/main/default/" -ForegroundColor Yellow
Write-Host "  -> force-app-unpackaged/main/default/" -ForegroundColor Yellow
Write-Host "  And retrieve fresh from org: $OrgAlias" -ForegroundColor Yellow

$confirm = Read-Host "Continue? (y/n)"
if ($confirm -ne "y") {
    Write-Host "Aborted by user." -ForegroundColor Red
    exit 1
}

# STEP 3 - Clean local folders
Write-Host "Cleaning force-app/main/default/..." -ForegroundColor Yellow
if (Test-Path "force-app/main/default") {
    Remove-Item -Recurse -Force "force-app/main/default/*" -ErrorAction SilentlyContinue
    Write-Host "OK: force-app/main/default/ cleaned." -ForegroundColor Green
} else {
    New-Item -ItemType Directory -Force -Path "force-app/main/default" | Out-Null
    Write-Host "OK: force-app/main/default/ created." -ForegroundColor Green
}

Write-Host "Cleaning force-app-unpackaged/main/default/..." -ForegroundColor Yellow
if (Test-Path "force-app-unpackaged/main/default") {
    Remove-Item -Recurse -Force "force-app-unpackaged/main/default/*" -ErrorAction SilentlyContinue
    Write-Host "OK: force-app-unpackaged/main/default/ cleaned." -ForegroundColor Green
} else {
    New-Item -ItemType Directory -Force -Path "force-app-unpackaged/main/default" | Out-Null
    Write-Host "OK: force-app-unpackaged/main/default/ created." -ForegroundColor Green
}

# STEP 4 - Retrieve managed package components
Write-Host "Setting force-app as default directory..." -ForegroundColor Cyan
$projectJson = Get-Content "sfdx-project.json" -Raw | ConvertFrom-Json
$projectJson.packageDirectories | ForEach-Object { $_.default = ($_.path -eq "force-app") }
$projectJson | ConvertTo-Json -Depth 10 | Set-Content "sfdx-project.json"

Write-Host "Retrieving managed package components..." -ForegroundColor Cyan
sf project retrieve start --manifest manifest/package.xml --target-org $OrgAlias
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to retrieve managed package components." -ForegroundColor Red
    exit 1
}
Write-Host "OK: Managed package components retrieved." -ForegroundColor Green

# STEP 5 - Retrieve unpackaged components
Write-Host "Setting force-app-unpackaged as default directory..." -ForegroundColor Cyan
$projectJson.packageDirectories | ForEach-Object { $_.default = ($_.path -eq "force-app-unpackaged") }
$projectJson | ConvertTo-Json -Depth 10 | Set-Content "sfdx-project.json"

Write-Host "Retrieving unpackaged components..." -ForegroundColor Cyan
sf project retrieve start --manifest manifest/unpackaged.xml --target-org $OrgAlias
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to retrieve unpackaged components." -ForegroundColor Red
    exit 1
}
Write-Host "OK: Unpackaged components retrieved." -ForegroundColor Green

# STEP 6 - Restore sfdx-project.json to force-app as default
Write-Host "Restoring sfdx-project.json defaults..." -ForegroundColor Cyan
$projectJson.packageDirectories | ForEach-Object { $_.default = ($_.path -eq "force-app") }
$projectJson | ConvertTo-Json -Depth 10 | Set-Content "sfdx-project.json"
Write-Host "OK: sfdx-project.json restored." -ForegroundColor Green

# STEP 7 - Remove FlexiPage actionOverrides from Item__c object
Write-Host "Cleaning FlexiPage actionOverrides from Item__c..." -ForegroundColor Cyan
$itemObjectPath = "force-app/main/default/objects/Item__c/Item__c.object-meta.xml"
if (Test-Path $itemObjectPath) {
    $content = Get-Content $itemObjectPath -Raw
    $pattern = '(?s)\s*<actionOverrides>.*?<type>Flexipage</type>.*?</actionOverrides>'
    $cleaned = [regex]::Replace($content, $pattern, '')
    Set-Content $itemObjectPath $cleaned
    Write-Host "OK: FlexiPage actionOverrides removed from Item__c." -ForegroundColor Green
} else {
    Write-Host "WARNING: Item__c object file not found - skipping." -ForegroundColor Yellow
}

# STEP 8 - Remove externalCredentialPrincipalAccesses from PermissionSet
Write-Host "Cleaning externalCredentialPrincipalAccesses from PermissionSet..." -ForegroundColor Cyan
$permSetPath = "force-app-unpackaged/main/default/permissionsets/Lumen_Planning_Permission_Set_1.permissionset-meta.xml"
if (Test-Path $permSetPath) {
    $content = Get-Content $permSetPath -Raw
    $pattern = '(?s)\s*<externalCredentialPrincipalAccesses>.*?</externalCredentialPrincipalAccesses>'
    $cleaned = [regex]::Replace($content, $pattern, '')
    Set-Content $permSetPath $cleaned
    Write-Host "OK: externalCredentialPrincipalAccesses removed from PermissionSet." -ForegroundColor Green
} else {
    Write-Host "WARNING: PermissionSet file not found - skipping." -ForegroundColor Yellow
}

# STEP 9 - Remove AttachedContentNotes from Item_Record_Page FlexiPage
Write-Host "Cleaning AttachedContentNotes from Item_Record_Page..." -ForegroundColor Cyan
$flexiPagePath = "force-app-unpackaged/main/default/flexipages/Item_Record_Page.flexipage-meta.xml"
if (Test-Path $flexiPagePath) {
    $content = Get-Content $flexiPagePath -Raw
    $pattern = '(?s)\s*<flexiPageRegions>(?:(?!<flexiPageRegions>).)*?AttachedContentNotes.*?</flexiPageRegions>'
    $cleaned = [regex]::Replace($content, $pattern, '')
    Set-Content $flexiPagePath $cleaned
    Write-Host "OK: AttachedContentNotes removed from Item_Record_Page." -ForegroundColor Green
} else {
    Write-Host "WARNING: Item_Record_Page flexipage not found - skipping." -ForegroundColor Yellow
}