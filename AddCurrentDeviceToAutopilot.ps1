
<#PSScriptInfo

.VERSION 1.0

.GUID ec909599-b3ae-48fa-a331-72c40493d267

.AUTHOR PiotrG.

.COMPANYNAME

.COPYRIGHT

.TAGS

.LICENSEURI

.PROJECTURI

.ICONURI

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES


.PRIVATEDATA

#>

<# 

.DESCRIPTION 
 A sample script to register current device into Autopilot. It waits till profile is applied then restart

#>

Write-host "$((get-date).ToLongTimeString()) : Installing modules"
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
Install-Module AzureAD -Force
Install-Module WindowsAutopilotIntune -Force
Install-Module Microsoft.Graph.Intune -Force

$isok = $false

Connect-MSGraph | Out-Null

#Get Hardware Hash
$hwid = ((Get-WMIObject -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'").DeviceHardwareData)
#Get SerialNumber
$ser = (Get-WmiObject win32_bios).SerialNumber

$dev = Get-AutopilotDevice  -serial $ser -ErrorAction SilentlyContinue
if ($null -eq $dev) {
    Write-host "$((get-date).ToLongTimeString()) : Adding device to Autopilot"
    Add-AutoPilotImportedDevice -serialNumber $ser -hardwareIdentifier $hwid
}
else {
    Write-host "$((get-date).ToLongTimeString()) : Device already exists in Autopilot"
}

try { Invoke-AutopilotSync -ErrorAction SilentlyContinue | out-null } catch {}

do {
    
    Start-Sleep -Seconds 30
    $dev = Get-AutopilotDevice  -serial $ser
    if ($null -ne $dev) {
        Write-host "$((get-date).ToLongTimeString()) : $($dev.deploymentProfileAssignmentStatus)"
        if (($dev.deploymentProfileAssignmentStatus -ine "notAssigned") -and ($dev.deploymentProfileAssignmentStatus -ine "pending") ) {
            $isok = $true
        }
    }
    else {
        Write-host "$((get-date).ToLongTimeString()) : Not available in Autopilot service yet"
    }
} while (!$isok)
write-host
if ($isok) {
    Write-Host "Now you can proceed with Autopilot. Restarting in 30 seconds" -ForegroundColor Green
    Start-Sleep -Seconds 30
    Restart-Computer -Force
}
else {
    Write-Error "Something was wrong while adding device to Autopilot"
}