<#PSScriptInfo
.VERSION 2.7
.GUID ec909599-b3ae-48fa-a331-72c40493d267
.AUTHOR Piotr Gardy
.COMPANYNAME
.COPYRIGHT
.TAGS Windows AutoPilot
.LICENSEURI
.PROJECTURI
.ICONURI
.EXTERNALMODULEDEPENDENCIES 
.REQUIREDSCRIPTS
.EXTERNALSCRIPTDEPENDENCIES
.RELEASENOTES
Version 2.6: Going away from  DeviceManagementWindowsAutopilotDeviceIdentity
Version 2.5: Using Beta modules (and /Beta endpoint) for DeviceManagementWindowsAutopilotDeviceIdentity commandlets
Version 2.4: Fixing errors after Microsoft.Graph modules have been upgraded to 2.0
Version 2.3: Bugfixing after testing 2.0 version
Version 2.0: Migrated to new Powershell module (Microsoft.Graph.Authentication + Microsoft.Graph.DeviceManagement.Enrolment) p;us more functionalities
Version 1.0: Original published version
#>

<# 

.SYNOPSIS
 A sample script to register current device into Windows Autopilot. It waits till profile is applied then restarts

.DESCRIPTION 
 A sample script to register current device into Windows Autopilot. It waits till profile is applied then restarts
 If you want to provide feedback or contribute, please use Github website: https://github.com/pgardy/AddCurrentDeviceToAutopilot


.PARAMETER Scopes
Scopes to be used. By default script only asks what it needs, which is : DeviceManagementServiceConfig.ReadWrite.All, User.Read

.PARAMETER GroupTag
(Optional) Grouptag value

.PARAMETER AssignedUserPrincipalName
(Optional) Assigned UserPrincipalNam

.PARAMETER UseLegacyAppId
(Optional) In case that new Powershell Module AzureAD is not approved yet by Global Administrator, you can try to use AppId for legacy module. That would require a login to AzureAD by retyping Device Code

.PARAMETER UseDeviceAuth
(Optional) If you want to perform AAD Login from another computer, use this option and retype Device Code as intructed

.PARAMETER DeviceHashFilePath
Path where to save and use hardware hash data. By default it is: c:\windows\temp\DeviceHardwareData.txt

.PARAMETER DoRestart
Specify if you want to restart a device when import was finished. $true by default


.EXAMPLE
.\AddCurrentDeviceToAutopilot.ps1 -GroupTag Test123 -DoRestart $false
Assing GroupTag for this device and do not restart when import is finished

.EXAMPLE
.\AddCurrentDeviceToAutopilot.ps1 -GroupTag Test123 -UseLegacyAppId
Use "Microsoft Intune PowerShell" (legacy Azure AD Enterprise Applications App id) . Might be helpfull if new, correct, module hasn't been aproved by Global Administrator yet
 #>


#Let's define parameters
[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false,
        HelpMessage = "Scopes to be used. By default script only asks what it needs, which is : DeviceManagementServiceConfig.ReadWrite.All, User.Read")]
    [string]$Scopes = "DeviceManagementServiceConfig.ReadWrite.All, User.Read",
    
    [Parameter(Mandatory = $false,
        HelpMessage = "(Optional) Grouptag value")]
    [String]$GroupTag = "",

    [Parameter(Mandatory = $false,
        HelpMessage = "(Optional) Assigned UserPrincipalName")]
    [String]$AssignedUserPrincipalName = "",

    [Parameter(Mandatory = $false,
        HelpMessage = "(Optional) In case that new Powershell Module AzureAD is not approved yet by Global Administrator, you can try to use AppId for legacy module. That would require a login to AzureAD by retyping Device Code")]
    [switch]$UseLegacyAppId,
    
    [Parameter(Mandatory = $false,
        HelpMessage = "(Optional) If you want to perform AAD Login from another computer, use this option and retype Device Code as intructed")]
    [switch]$UseDeviceAuth ,

    [Parameter(Mandatory = $false,
        HelpMessage = "Specify if you want to restart a device when import was finished. `$true by default")]
    [bool]$DoRestart = $true 
)

##### Main Part #################

Write-host "Checking and installing, missing, modules"
#Installing modules
$InstalledModules = Get-Module -ListAvailable -Name Microsoft.Graph.Authentication
if ($InstalledModules.Name -inotcontains "Microsoft.Graph.Authentication") { Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force }

#Importing modules
Import-Module Microsoft.Graph.Authentication
#Import-Module Microsoft.Graph.Beta.DeviceManagement.Enrollment


Write-host "Initiating authentication to AAD"
#connecting to AzureAD
if ($PSBoundParameters.ContainsKey('UseLegacyAppId')) {
    Connect-MgGraph -Scopes $scopes -ClientId d1ddf0e4-d672-4dae-b554-9d5bdfd93547 -UseDeviceAuthentication     
}
else {
    if ($PSBoundParameters.ContainsKey('UseDeviceAuth')) {
        Connect-MgGraph -Scopes $scopes -UseDeviceAuthentication
    }
    else {
        Connect-MgGraph -Scopes $scopes 
    }
}

$hwid = (Get-WMIObject -Namespace root/cimv2/mdm/dmmap -Class MDM_DevDetail_Ext01 -Filter "InstanceID='Ext' AND ParentID='./DevDetail'").DeviceHardwareData
#$hwbase64 = [System.Text.Encoding]::ascii.getstring([System.Convert]::FromBase64String($hwid))

#Get SerialNumber
$ser = (Get-WmiObject win32_bios).SerialNumber


#check id device is already present in the tenant
#$dev = Get-MgBetaDeviceManagementWindowsAutopilotDeviceIdentity -Filter "contains(serialNumber,'$($ser)')" -ErrorAction SilentlyContinue
$httpresult = Invoke-MgGraphRequest  -uri   "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$ser')"
$dev = $httpresult.value[0] 
if ($null -eq $dev) {
    #building importing command
    Write-host "$((get-date).ToLongTimeString()) : Adding device to Autopilot"
    $body = @{
        "@odata.type" = "#microsoft.graph.importedWindowsAutopilotDeviceIdentity"
        "serialNumber" = $ser
        "hardwareIdentifier" = $hwid 
    }
    #-Method POST -Body  $body -ContentType 'application/json'
    #$expr = "New-MgBetaDeviceManagementImportedWindowsAutopilotDeviceIdentity -SerialNumber ""$($ser)"" -HardwareIdentifierInputFile ""$($DeviceHashFilePath)"" " 
    if ($GroupTag -ne "") {
        #$expr += " -GroupTag ""$($GroupTag)"""
        $body.Add("groupTag",$GroupTag)
    }
    if ($AssignedUserPrincipalName -ne "") {
        #$expr += " -AssignedUserPrincipalName ""$($AssignedUserPrincipalName)"""
        $body.Add("assignedUserPrincipalName",$AssignedUserPrincipalName)
    }
    #invoking import of the device
    #Invoke-Expression $expr
    Invoke-MgGraphRequest -Method POST -Body  $body -ContentType 'application/json' -Uri "https://graph.microsoft.com/beta/deviceManagement/importedWindowsAutopilotDeviceIdentities"
    write-host "Added device to Autopilot"
}
else {
    Write-host "$((get-date).ToLongTimeString()) : Device already exists in Autopilot"
    break;
}

try { Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/$($GraphVersion)/deviceManagement/windowsAutopilotSettings/sync" -Method POST -ErrorAction SilentlyContinue | out-null } catch {}

do {
    
    Start-Sleep -Seconds 30
    #$dev = Get-MgBetaDeviceManagementWindowsAutopilotDeviceIdentity -Filter "contains(serialNumber,'$($ser)')" -ErrorAction SilentlyContinue
    $httpresult = Invoke-MgGraphRequest  -uri   "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$ser')"
    $dev = $httpresult.value[0] 
    if ($null -ne $dev) {
        Write-host "$((get-date).ToLongTimeString()) : $($dev.deploymentProfileAssignmentStatus)"
        if (($dev.DeploymentProfileAssignmentStatus -ine "notAssigned") -and ($dev.DeploymentProfileAssignmentStatus -ine "pending") ) {
            $isok = $true
        }
    }
    else {
        Write-host "$((get-date).ToLongTimeString()) : Not available in Autopilot service yet"
    }
} while (!$isok)
write-host
if ($isok) {
    if ($DoRestart) {
        Write-Host "Now you can proceed with Autopilot. Restarting in 30 seconds" -ForegroundColor Green
        Start-Sleep -Seconds 30
        Restart-Computer -Force
    }

}
else {
    Write-Error "Something was wrong while adding device to Autopilot"
}