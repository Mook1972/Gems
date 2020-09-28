#---------------------------------------------------------
#
#  Application: Microsoft SQL Server Configuration
#
#  Author: Amauri Viguera
#  Original Release: 2016-Dec-30
#
#   2016-Dec-30     - original release
#   2017-Jan-19     - removed unused Binn folder reference
#   2017-Apr-26     - updated to remove nonprod-specific jobMainDBFile
#   2017-May-01     - updated to add service account to GO-SG System 
#   2017-May-10     - added ntrights call for GO-SG System 
#   2017-Jul-13     - updated sqlcmd / osql calls to use windows authentication
#   2017-Jul-24     - removed conditional for removing built=in admins 
#   2017-Jul-31     - updated SQL files at request of DMG 
#                       - JobMainSched_prod file to JobMainSched_prod_rev1a 
#                       - JobMainSched_nonprod updated to JobMainSched_nonprod_rev1a
#   2018-Jan-25     - updated to disable services at request of DMG
#                       - disable sql vss writer on virtual machines due to NBU conflict 
#                       - disable all customer experience services 
#   2018-Feb-24     - updated with new DMV t-sql script from DMG
#
#---------------------------------------------------------

Import-Module KSTools
Import-Module SQLPS -DisableNameChecking -ErrorAction SilentlyContinue

#-------------------------------------------
#  Script Constants
#-------------------------------------------

$ErrorActionPreference = "Stop"
$AppFName = "Microsoft SQL Server Post Install Configuration"
$AppVer = "1"
$AppKey = "MSSQL\2016\SQLServerPostInstallConfig"
$RepoServer = $env:REPOSERVER
$ScriptRoot = $PSScriptRoot
$ErrorFlag = -90210
$sqlEdition = Get-TattooValue "sqlEdition"
if (!($sqlEdition)) { $sqlEdition = "Standard" }
$SQLPath = "Microsoft\MSSQL\2016\$($sqlEdition)\SQLServer\files"
$keyfile = "$Reposerver\$SQLPath\crypto\AES.key"
$tmpFolder = "$env:windir\temp"

#-------------------------------------------
#  Script Variables
#-------------------------------------------

# before we do anything, check if a reboot is pending

if (Get-PendingReboot) { Write-HostStatus "A pending reboot has been detected." "FAIL" ; exit 3010 }

# find out if we're using the new SQL cell functionality
$sqlCell = Get-TattooValue "sqlCell"
$sqlMountPoint = Get-TattooValue "sqlMountPoint" 

if (!($sqlCell)) { $sqlCell = "false" }

# so we don't run into issues with SQLPS import changing the path (results in get-content issues for %reposerver%)
set-location $tmpFolder

$TCPPort = Get-TattooValue "sqlPort"
if (!($TCPPort)) { $TCPPort = "1113" }

$defaultSQLAccount = "us-svcsqlspinup"
$defaultSQLDomain = "US"
# default account password
$encrpass= "76492d1116743f0423413b16050a5345MgB8AE8ATABJAHoAaQA0AGcAVAB4ADQANQBYAHcAUwBHAEIASgBjAFEAQQBIAHcAPQA9AHwAZQA0AGMAMgAwAGIANgBhADIAMABhADIANQA1ADcAMQBlADQAYgAxADkANwAwADIAMwAyAGUANQA4AGUAMABkADMANAAzAGUAYwA4ADkANABjAGYAYwA1ADYANQAzADQAZgBiADAANwAxADQANwBhADgAYgAyADAANQAzADYAOAA="

# if we read an encrypted password from the tattoo, use that instead of the default
$sqlServiceAccountPassword = Get-TattooValue "sqlServiceAccountPassword"
if ($sqlServiceAccountPassword.length -gt 0) { $encrpass = $sqlServiceAccountPassword }

# if we're unable to retrieve the encrypted password from the repo AND
# if we're unable to retrieve the encrypted password from the tattoo, abort
if (!($encrpass)) { Write-HostStatus "Unable to retrieve service account password" "FAIL" ; exit 3 }

$secpass = $encrpass | ConvertTo-SecureString -Key (Get-Content "$keyfile")
$SQLPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secpass))

# read custom instance name from tattoo.  if not found, use default 
$INSTANCENAME = Get-TattooValue "sqlInstanceName"
if ($INSTANCENAME.length -eq 0) { Write-HostStatus "SQL Instance was found blank, assuming default" "INFO" ; $INSTANCENAME = "MSSQLSERVER" }

$CustomPort = Get-TattooValue "sqlPort"
if ($CustomPort.length -gt 0) { $TCPPort = $CustomPort }
Write-HostStatus "Configured SQL installation to use port $($TcpPort)" "INFO"

$ComputerName = $env:ComputerName

$DMGMontvaleGroup = "US-SG TechOps DMG SQL"
$SGGroup = "GO-SG ServiceAccounts"
$SGSystem = "GO-SG System"

$ComputerDomain = Get-ComputerDomain
if ($ComputerDomain -eq "DALLASLAB.LOCAL") 
{
    # do nothing for the lab machines
} else {
    # outside of the lab, read service account information from the tattoo 
    $sqlSvcAccount = Get-TattooValue "sqlServiceAccount"
    $sqlSvcDomain = Get-TattooValue "sqlServiceDomain"
}

if (!($sqlSvcAccount)) { $sqlSvcAccount = $defaultSQLAccount }
if (!($sqlSvcDomain)) { $sqlSvcDomain = $defaultSQLDomain }

Add-TattooValue "sqlServiceAccount" "$($sqlSvcAccount)"
Add-TattooValue "sqlServiceDomain" "$($sqlSvcDomain)"

$SQLAccount = "$SQLSVCDomain\$SQLSVCAccount"

Write-HostStatus "Configured SQL installation to use $($SQLAccount) account" "INFO"

# error path 
$ErrorLogPath = "E:\MSSQL13.$INSTANCENAME\MSSQL\ErrorLogs"

if ($sqlCell -eq "true") { 
    $ErrorLogPath = "$sqlMountPoint\SQL_$($INSTANCENAME)_LOG01\ErrorLogs"

}

# read prod / nonprod server classification
$serverType = Get-TattooValue "kpmg_env"
if (!($serverType)) { $serverType = "prod" }

# default post-installation files
$postInstallFile = "postinstall2016_prod.sql"
$jobMainDBFile = "jobMainDB.sql"
$jobMainSchedFile = "JobMainSched_Prod.sql"
$pcaobFile = "PCAOB_Deployment_4c_prod.sql"
$DMVFile = "DMV_Deployment.sql"

# post-installation files for non-prod
if ($serverType -eq "nonprod") {
    $postInstallFile = "postinstall2016_nonprod.sql"
    $jobMainSchedFile = "JobMainSched_NonProd.sql"
    $pcaobFile = "PCAOB_Deployment_4c_NONProd.sql"
}

Write-hoststatus "Configured SQL installation as $($serverType)" "INFO"

write-host "-----------------------------------------"
write-host "Configuration summary"
write-host "server is $($serverType)"
write-host "SQL edition is $($sqlEdition)"
write-host "service account is $($SQLAccount)"
write-host "instance name is $($INSTANCENAME)"
write-host "SG Group is $($SGGroup)"
write-host "SG System group is $($SGSystem)"
write-host "-----------------------------------------"

#-------------------------------------------
#  Installation Subsystems
#-------------------------------------------

# add account to SG-GO System group and grant rights
# add DMG Montvale group to local admins
if (Add-Subsystem $AppKey "AddADGroupToLocalAdmin" "SYSTEM" $AppVer) 
{
    Write-hoststatus "Configuring group permissions " "INFO"

    # disable error checking in case the accounts are already in the group
    $ErrorActionPreference = "SilentlyContinue"

    # create groups and add accounts
    Add-Localgroup "$SGGroup" "$($SGGroup)"
    Add-Localgroupmember "$SGGroup" "$SQLSVCAccount" "$SQLSVCDomain"
    Add-Localgroupmember "$SGSystem" "$SQLSVCAccount" "$SQLSVCDomain"
    Add-Localgroupmember "Administrators" "$DMGMontvaleGroup" "$SQLSVCDomain"

    $ErrorFlag = Run "ntrights +r SeServiceLogonRight -u ""$SGGroup""" True True # log on as a service 
    $ErrorFlag = Run "ntrights +r SeLockMemoryPrivilege  -u ""$SGGroup""" True True # lock pages in memory
    $ErrorFlag = Run "ntrights +r SeTcbPrivilege -u ""$SGGroup""" True True # act as part of the operating system 
    $ErrorFlag = Run "ntrights +r SeChangeNotifyPrivilege -u ""$SGGroup""" True True # bypass traverse checking 
    $ErrorFlag = Run "ntrights +r SeBatchLogonRight -u ""$SGGroup""" True True # log on as a batch job 
    $ErrorFlag = Run "ntrights +r SeAssignPrimaryTokenPrivilege -u ""$SGGroup""" True True # replace a process level token 
    $ErrorFlag = Run "ntrights +r SeIncreaseQuotaPrivilege -u ""$SGGroup""" True True # adjust / increase memory quotas 

    $ErrorFlag = Run "ntrights +r SeServiceLogonRight -u ""$SGSystem""" True True # log on as a service 
    $ErrorFlag = Run "ntrights +r SeLockMemoryPrivilege  -u ""$SGSystem""" True True # lock pages in memory
    $ErrorFlag = Run "ntrights +r SeTcbPrivilege -u ""$SGSystem""" True True # act as part of the operating system 
    $ErrorFlag = Run "ntrights +r SeChangeNotifyPrivilege -u ""$SGSystem""" True True # bypass traverse checking 
    $ErrorFlag = Run "ntrights +r SeBatchLogonRight -u ""$SGSystem""" True True # log on as a batch job 
    $ErrorFlag = Run "ntrights +r SeAssignPrimaryTokenPrivilege -u ""$SGSystem""" True True # replace a process level token 
    $ErrorFlag = Run "ntrights +r SeIncreaseQuotaPrivilege -u ""$SGSystem""" True True # adjust / increase memory quotas 

    # turn error checking back on
    $ErrorActionPreference = "Stop"

    Close-Subsystem $AppKey "AddADGroupToLocalAdmin" SYSTEM $AppVer
}

# edit registry to set errorlog path specifically to log folder & \ERRORLOG 
if (Add-Subsystem $AppKey "SetErrorLogPath" "SYSTEM" $AppVer) 
{
    Write-hoststatus "Configuring error log " "INFO"

    # change the value in the registry for error logging (even using .ini file does not set this and is left as C:)
    # for SQL 2012 value is under MSSQL11.  for 2014 value is under MSSQL12. for 2016 value is under MSSQL13
    New-Item $ErrorLogPath -type directory -force

    $errorLogRegistry = "HKLM:\software\microsoft\Microsoft Sql server\MSSQL13.$INSTANCENAME\MSSQLSERVER\parameters"
    Add-RegistryValue $errorLogRegistry "sqlARG1" "-e$ErrorLogPath\ErrorLog" "STRING"

    Close-Subsystem $AppKey "SetErrorLogPath" SYSTEM $AppVer
}

# call setacls with service account name
if (Add-Subsystem $AppKey "SetACLS" "SYSTEM" $AppVer) 
{
    Write-hoststatus "Configuring folder permissions " "INFO"

    # icacls FTW... :)
    # (OI) - object inheritance
    # (CI) - container inheritance
    # (F) - full control / (M) - modify 
    # /grant [account]:(OI)(CI)(F) - grant full control to files, folders and subfolders
    # have to use ${variable}: for account name because $variable: will result in a PS mess because of the namespace

    # if we're using a SQL cell, all folders are subfolders of the sqlMountPoint, so we only need to do this once

    if ($sqlCell -eq "true") {
        $ErrorFlag = Run "cmd /c icacls.exe $sqlMountPoint\ /grant ${SQLSVCAccount}:(OI)(CI)(F) /grant administrators:(OI)(CI)(F) /grant ""Backup Operators"":(OI)(CI)(M) /remove Everyone " True True        
    } else {

        # permission individual root folders on all drives
        $ErrorFlag = Run "cmd /c icacls.exe E:\ /grant ${SQLSVCAccount}:(OI)(CI)(F) /grant administrators:(OI)(CI)(F) /grant ""Backup Operators"":(OI)(CI)(M) /remove Everyone " True True
        $ErrorFlag = Run "cmd /c icacls.exe F:\ /grant ${SQLSVCAccount}:(OI)(CI)(F) /grant administrators:(OI)(CI)(F) /grant ""Backup Operators"":(OI)(CI)(M) /remove Everyone " True True

        # only prod servers will have a G: drive 
        if ($serverType -eq "prod") { 
            $ErrorFlag = Run "cmd /c icacls.exe G:\ /grant ${SQLSVCAccount}:(OI)(CI)(F) /grant administrators:(OI)(CI)(F) /grant ""Backup Operators"":(OI)(CI)(M) /remove Everyone " True True
        }

        $ErrorFlag = Run "cmd /c icacls.exe H:\ /grant ${SQLSVCAccount}:(OI)(CI)(F) /grant administrators:(OI)(CI)(F) /grant ""Backup Operators"":(OI)(CI)(M) /remove Everyone " True True
        $ErrorFlag = Run "cmd /c icacls.exe ""C:\Program Files\Microsoft SQL Server"" /grant ${SQLSVCAccount}:(OI)(CI)(F) /grant administrators:(OI)(CI)(F) /grant system:(OI)(CI)(F) " True True
    }

    Close-Subsystem $AppKey "SetACLS" SYSTEM $AppVer
}

# configure services
if (Add-Subsystem $AppKey "ServiceConfig" "SYSTEM" $AppVer) 
{
    Write-hoststatus "Configuring SQL Agent Service" "INFO"
    # default service name is SQLAGENT$[instance]
    $serviceName = ("SQLAGENT$" + "$INSTANCENAME")
    # if we're using a custom instance name, the service name changes
    if ($INSTANCENAME -eq "MSSQLSERVER") { $serviceName = "SQLSERVERAGENT" }

    Set-Service "$serviceName" -startuptype automatic
    $ErrorFlag = Run "sc config $serviceName obj= $SQLAccount password= $SQLPassword" True True Hidden | Out-Null

    Write-hoststatus "Configuring SQL Server Service" "INFO"

    $serviceName = ("MSSQL$" + "$INSTANCENAME")
    if ($INSTANCENAME -eq "MSSQLSERVER") { $serviceName = "MSSQLSERVER" }
    $ErrorFlag = Run "sc config $serviceName obj= $SQLAccount password= $SQLPassword" True True Hidden | Out-Null

    if (Get-IsVirtual) {
        Write-HostStatus "Disabling SQL Writer on Virtual Machine" "INFO"
        Get-Service -Name "sqlwriter" | Stop-Service 
        Get-Service -Name "sqlwriter" | Set-Service -StartupType "Disabled"
    }

    Write-HostStatus "Disabling telemetry" "INFO"
    Get-Service -DisplayName "*CEIP*" | Stop-Service 
    Get-Service -DisplayName "*CEIP*" | Set-Service -StartupType "Disabled"

    Close-Subsystem $AppKey "ServiceConfig" SYSTEM $AppVer
}

# change SQL Server Port to 1113
if (Add-Subsystem $AppKey "SQLServerPort" "SYSTEM" $AppVer) 
{
    Write-hoststatus "Changing MSSQL service port " "INFO"

    $ErrorActionPreference = "SilentlyContinue"
    # loop through interfaces and change port from default
    $smo = 'Microsoft.SqlServer.Management.Smo.'
    $wmi = New-Object ($smo + 'Wmi.ManagedComputer')

    $uri = "ManagedComputer[@Name='$computerName']/ ServerInstance[@Name='$INSTANCENAME']/ServerProtocol[@Name='Tcp']"
    $Tcp = $wmi.GetSmoObject($uri)
    foreach ($ipAddress in $Tcp.IPAddresses)
    {
        $ipAddress.IPAddressProperties["TcpDynamicPorts"].Value = ""
        $ipAddress.IPAddressProperties["TcpPort"].Value = "$TcpPort"
    }
    $Tcp.Alter()
    $ErrorFlag = 0
    $ErrorActionPreference = "Stop"
    Close-Subsystem $AppKey "SQLServerPort" SYSTEM $AppVer
}

# update native client default to match
if (Add-Subsystem $AppKey "UpdateNativeClient" "SYSTEM" $AppVer) 
{
    Write-HostStatus "Changing Native Client default port" "INFO"
    # the key requires a DWORD called "Value" with 0x459 HEX (Decimal 1113)
    $errorLogRegistry = "HKLM:\software\Microsoft\MSSQLSERVER\Client\SNI11.0\tcp\Property1"
    Add-RegistryValue $errorLogRegistry "Value" "0x459" "DWORD"
    Close-Subsystem $AppKey "UpdateNativeClient" SYSTEM $AppVer
}

if (Add-Subsystem $AppKey "DisableTelemetry" "EXECUTE" $AppVer) 
{
    Write-HostStatus "Disabling telemetry" "INFO"
    Add-RegistryValue "HKLM:\Software\Microsoft\Microsoft SQL Server\130" "CustomerFeedback" "0" "STRING"
    Add-RegistryValue "HKLM:\Software\Microsoft\Microsoft SQL Server\130" "EnableErrorReporting" "0" "STRING"
    Close-Subsystem $AppKey "DisableTelemetry" EXECUTE $AppVer
}

# restart services
if (Add-Subsystem $AppKey "RestartService" "EXECUTE" $AppVer) 
{

    Write-HostStatus "Starting services" "INFO"

    $agentService = ("SQLAGENT$" + "$INSTANCENAME")
    $serverService = ("MSSQL$" + "$INSTANCENAME")

    # if we're using a custom instance name, the service name changes
    if ($INSTANCENAME -eq "MSSQLSERVER") { $agentService = "SQLSERVERAGENT" ; $serverService = "MSSQLSERVER" }

    Restart-Service "$serverService" -force
    Start-Service "$agentService"

    Close-Subsystem $AppKey "RestartService" EXECUTE $AppVer
}

if (Add-Subsystem $AppKey "PostInstall2016" "SYSTEM" $AppVer) 
{
    Write-hoststatus "Executing $($postInstallFile) script" "INFO"
    $launchCmd = "sqlcmd.exe -E -S .\$($INSTANCENAME) -i ""$ScriptRoot\files\$($postInstallFile)"" "

    if ($InstanceName -eq "MSSQLSERVER") { $launchCmd = "sqlcmd.exe -E -i ""$ScriptRoot\files\$($postInstallFile)"" " }

    write-host "executing $($launchCmd)"
    $ErrorFlag = Run $launchCmd True True
    write-host "execution complete... exit code $($ErrorFlag)"
    Close-Subsystem $AppKey "PostInstall2016" SYSTEM $AppVer
}

if (Add-Subsystem $AppKey "JobMainDB" "SYSTEM" $AppVer) 
{
    Write-hoststatus "Executing $($jobMainDBFile) script" "INFO"
    $launchCmd = "sqlcmd.exe -E -S .\$($InstanceName) -i ""$ScriptRoot\files\$($jobMainDBFile)"" " 

    if ($InstanceName -eq "MSSQLSERVER") { $launchCmd = "sqlcmd.exe -E -i ""$ScriptRoot\files\$($jobMainDBFile)"" " }

    write-host "executing $($launchCmd)"
    $ErrorFlag = Run $launchCmd True True
    write-host "execution complete... exit code $($ErrorFlag)"
    Close-Subsystem $AppKey "JobMainDB" SYSTEM $AppVer
}

if (Add-Subsystem $AppKey "JobMainSched" "SYSTEM" $AppVer) 
{
    Write-hoststatus "Executing $($jobMainSchedFile) script" "INFO"
    $launchCmd = "sqlcmd.exe -E -S .\$($InstanceName) -i ""$ScriptRoot\files\$($jobMainSchedFile)"" "

    if ($InstanceName -eq "MSSQLSERVER") { $launchCmd = "sqlcmd.exe -E -i ""$ScriptRoot\files\$($jobMainSchedFile)"" "
}

    write-host "executing $($launchCmd)"
    $ErrorFlag = Run $launchCmd True True
    write-host "execution complete... exit code $($ErrorFlag)"
    Close-Subsystem $AppKey "JobMainSched" SYSTEM $AppVer
}

if (Add-Subsystem $AppKey "DeployPCAOB" "SYSTEM" $AppVer) 
{
    Write-hoststatus "Executing $($pcaobFile) to $($computername)\$($INSTANCENAME) script" "INFO"
    $launchCmd = "sqlcmd.exe -E -S .\$($InstanceName) -i ""$ScriptRoot\files\$($pcaobFile)"" "

    if ($InstanceName -eq "MSSQLSERVER") { $launchCmd = "sqlcmd.exe -E -i ""$ScriptRoot\files\$($pcaobFile)"" " }

    write-host "executing $($launchCmd)"
    $ErrorFlag = Run $launchCmd True True
    write-host "execution complete... exit code $($ErrorFlag)"
    Close-Subsystem $AppKey "DeployPCAOB" SYSTEM $AppVer
}

if (Add-Subsystem $AppKey "DeployDMV" "SYSTEM" $AppVer) 
{
    Write-hoststatus "Executing $($DMVFile)" "INFO"
    $launchCmd = "sqlcmd.exe -E -S .\$($InstanceName) -i ""$ScriptRoot\files\$($DMVFile)"" "

    if ($InstanceName -eq "MSSQLSERVER") { $launchCmd = "sqlcmd.exe -E -i ""$ScriptRoot\files\$($DMVFile)"" " }

    write-host "executing $($launchCmd)"
    $ErrorFlag = Run $launchCmd True True
    write-host "execution complete... exit code $($ErrorFlag)"
    Close-Subsystem $AppKey "DeployDMV" SYSTEM $AppVer
}

# remove local admins (used for install only)
# at this point everything should be running as the service account 
if (Add-Subsystem $AppKey "AdminConfig" "SYSTEM" $AppVer) 
{

    Write-hoststatus "Removing built-in admins " "INFO"
    $launchCmd = "sqlcmd.exe -E -S .\$($InstanceName) -i ""$ScriptRoot\files\remove_admin.sql"""

    if ($InstanceName -eq "MSSQLSERVER") { $launchCmd = "sqlcmd.exe -E -i ""$ScriptRoot\files\remove_admin.sql""" }

    write-host "executing $($launchCmd)"
    $ErrorFlag = Run $launchCmd True True
    write-host "execution complete... exit code $($ErrorFlag)"

    Close-Subsystem $AppKey "AdminConfig" SYSTEM $AppVer
}

# remove tattoo information 
if (Add-Subsystem $AppKey "CleanupTattoo" "EXECUTE" $AppVer) 
{

    Write-HostStatus "Cleaning up server tattoo" "INFO"

    # remove registry values after installation to avoid conflicts with next installer
    Remove-RegistryValue "HKLM:\SOFTWARE\KPMG\Global Server" "sqlServiceAccountPassword"
    Remove-RegistryValue "HKLM:\SOFTWARE\KPMG\Global Server" "sqlVersion"
    Remove-RegistryValue "HKLM:\SOFTWARE\KPMG\Global Server" "sqlEdition"
    Remove-RegistryValue "HKLM:\SOFTWARE\KPMG\Global Server" "sqlInstanceName"
    Remove-RegistryValue "HKLM:\SOFTWARE\KPMG\Global Server" "sqlCollation"
    Remove-RegistryValue "HKLM:\SOFTWARE\KPMG\Global Server" "sqlServiceDomain"
    Remove-RegistryValue "HKLM:\SOFTWARE\KPMG\Global Server" "sqlServiceAccount"
    Remove-RegistryValue "HKLM:\SOFTWARE\KPMG\Global Server" "sqlPort"
    Remove-RegistryValue "HKLM:\SOFTWARE\KPMG\Global Server" "sqlCell"
    Remove-RegistryValue "HKLM:\SOFTWARE\KPMG\Global Server" "sqlMountPoint"

    Close-Subsystem $AppKey "CleanupTattoo" EXECUTE $AppVer
}

exit


# SIG # Begin signature block
# MIIXkQYJKoZIhvcNAQcCoIIXgjCCF34CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUQR8xzP8ecr5K5Pcv8GvDNabq
# oc2gghKxMIID7jCCA1egAwIBAgIQfpPr+3zGTlnqS5p31Ab8OzANBgkqhkiG9w0B
# AQUFADCBizELMAkGA1UEBhMCWkExFTATBgNVBAgTDFdlc3Rlcm4gQ2FwZTEUMBIG
# A1UEBxMLRHVyYmFudmlsbGUxDzANBgNVBAoTBlRoYXd0ZTEdMBsGA1UECxMUVGhh
# d3RlIENlcnRpZmljYXRpb24xHzAdBgNVBAMTFlRoYXd0ZSBUaW1lc3RhbXBpbmcg
# Q0EwHhcNMTIxMjIxMDAwMDAwWhcNMjAxMjMwMjM1OTU5WjBeMQswCQYDVQQGEwJV
# UzEdMBsGA1UEChMUU3ltYW50ZWMgQ29ycG9yYXRpb24xMDAuBgNVBAMTJ1N5bWFu
# dGVjIFRpbWUgU3RhbXBpbmcgU2VydmljZXMgQ0EgLSBHMjCCASIwDQYJKoZIhvcN
# AQEBBQADggEPADCCAQoCggEBALGss0lUS5ccEgrYJXmRIlcqb9y4JsRDc2vCvy5Q
# WvsUwnaOQwElQ7Sh4kX06Ld7w3TMIte0lAAC903tv7S3RCRrzV9FO9FEzkMScxeC
# i2m0K8uZHqxyGyZNcR+xMd37UWECU6aq9UksBXhFpS+JzueZ5/6M4lc/PcaS3Er4
# ezPkeQr78HWIQZz/xQNRmarXbJ+TaYdlKYOFwmAUxMjJOxTawIHwHw103pIiq8r3
# +3R8J+b3Sht/p8OeLa6K6qbmqicWfWH3mHERvOJQoUvlXfrlDqcsn6plINPYlujI
# fKVOSET/GeJEB5IL12iEgF1qeGRFzWBGflTBE3zFefHJwXECAwEAAaOB+jCB9zAd
# BgNVHQ4EFgQUX5r1blzMzHSa1N197z/b7EyALt0wMgYIKwYBBQUHAQEEJjAkMCIG
# CCsGAQUFBzABhhZodHRwOi8vb2NzcC50aGF3dGUuY29tMBIGA1UdEwEB/wQIMAYB
# Af8CAQAwPwYDVR0fBDgwNjA0oDKgMIYuaHR0cDovL2NybC50aGF3dGUuY29tL1Ro
# YXd0ZVRpbWVzdGFtcGluZ0NBLmNybDATBgNVHSUEDDAKBggrBgEFBQcDCDAOBgNV
# HQ8BAf8EBAMCAQYwKAYDVR0RBCEwH6QdMBsxGTAXBgNVBAMTEFRpbWVTdGFtcC0y
# MDQ4LTEwDQYJKoZIhvcNAQEFBQADgYEAAwmbj3nvf1kwqu9otfrjCR27T4IGXTdf
# plKfFo3qHJIJRG71betYfDDo+WmNI3MLEm9Hqa45EfgqsZuwGsOO61mWAK3ODE2y
# 0DGmCFwqevzieh1XTKhlGOl5QGIllm7HxzdqgyEIjkHq3dlXPx13SYcqFgZepjhq
# IhKjURmDfrYwggSjMIIDi6ADAgECAhAOz/Q4yP6/NW4E2GqYGxpQMA0GCSqGSIb3
# DQEBBQUAMF4xCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3Jh
# dGlvbjEwMC4GA1UEAxMnU3ltYW50ZWMgVGltZSBTdGFtcGluZyBTZXJ2aWNlcyBD
# QSAtIEcyMB4XDTEyMTAxODAwMDAwMFoXDTIwMTIyOTIzNTk1OVowYjELMAkGA1UE
# BhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMTQwMgYDVQQDEytT
# eW1hbnRlYyBUaW1lIFN0YW1waW5nIFNlcnZpY2VzIFNpZ25lciAtIEc0MIIBIjAN
# BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAomMLOUS4uyOnREm7Dv+h8GEKU5Ow
# mNutLA9KxW7/hjxTVQ8VzgQ/K/2plpbZvmF5C1vJTIZ25eBDSyKV7sIrQ8Gf2Gi0
# jkBP7oU4uRHFI/JkWPAVMm9OV6GuiKQC1yoezUvh3WPVF4kyW7BemVqonShQDhfu
# ltthO0VRHc8SVguSR/yrrvZmPUescHLnkudfzRC5xINklBm9JYDh6NIipdC6Anqh
# d5NbZcPuF3S8QYYq3AhMjJKMkS2ed0QfaNaodHfbDlsyi1aLM73ZY8hJnTrFxeoz
# C9Lxoxv0i77Zs1eLO94Ep3oisiSuLsdwxb5OgyYI+wu9qU+ZCOEQKHKqzQIDAQAB
# o4IBVzCCAVMwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAO
# BgNVHQ8BAf8EBAMCB4AwcwYIKwYBBQUHAQEEZzBlMCoGCCsGAQUFBzABhh5odHRw
# Oi8vdHMtb2NzcC53cy5zeW1hbnRlYy5jb20wNwYIKwYBBQUHMAKGK2h0dHA6Ly90
# cy1haWEud3Muc3ltYW50ZWMuY29tL3Rzcy1jYS1nMi5jZXIwPAYDVR0fBDUwMzAx
# oC+gLYYraHR0cDovL3RzLWNybC53cy5zeW1hbnRlYy5jb20vdHNzLWNhLWcyLmNy
# bDAoBgNVHREEITAfpB0wGzEZMBcGA1UEAxMQVGltZVN0YW1wLTIwNDgtMjAdBgNV
# HQ4EFgQURsZpow5KFB7VTNpSYxc/Xja8DeYwHwYDVR0jBBgwFoAUX5r1blzMzHSa
# 1N197z/b7EyALt0wDQYJKoZIhvcNAQEFBQADggEBAHg7tJEqAEzwj2IwN3ijhCcH
# bxiy3iXcoNSUA6qGTiWfmkADHN3O43nLIWgG2rYytG2/9CwmYzPkSWRtDebDZw73
# BaQ1bHyJFsbpst+y6d0gxnEPzZV03LZc3r03H0N45ni1zSgEIKOq8UvEiCmRDoDR
# EfzdXHZuT14ORUZBbg2w6jiasTraCXEQ/Bx5tIB7rGn0/Zy2DBYr8X9bCT2bW+IW
# yhOBbQAuOA2oKY8s4bL0WqkBrxWcLC9JG9siu8P+eJRRw4axgohd8D20UaF5Mysu
# e7ncIAkTcetqGVvP6KUwVyyJST+5z3/Jvz4iaGNTmr1pdKzFHTx/kuDDvBzYBHUw
# ggTJMIIDsaADAgECAhAiXW95cB8gTnvQ6hqi4X7jMA0GCSqGSIb3DQEBCwUAMIGE
# MQswCQYDVQQGEwJVUzEdMBsGA1UEChMUU3ltYW50ZWMgQ29ycG9yYXRpb24xHzAd
# BgNVBAsTFlN5bWFudGVjIFRydXN0IE5ldHdvcmsxNTAzBgNVBAMTLFN5bWFudGVj
# IENsYXNzIDMgU0hBMjU2IENvZGUgU2lnbmluZyBDQSAtIEcyMB4XDTE3MDYyNzAw
# MDAwMFoXDTIwMDkyNDIzNTk1OVowejELMAkGA1UEBhMCVVMxEzARBgNVBAgMCk5l
# dyBKZXJzZXkxETAPBgNVBAcMCE1vbnR2YWxlMREwDwYDVQQKDAhLUE1HIExMUDEd
# MBsGA1UECwwUTW9udHZhbGUgRGF0YSBDZW50ZXIxETAPBgNVBAMMCEtQTUcgTExQ
# MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxjb4AQUf8OvAcZdFZUNb
# R/9wlX1mHJ7lrY5P07x7/b8tvk4FrcAsxRzCaqEQQtllgxFgc+ZtChH1oTPO7G28
# vv+PSd5mYiZ6AxprgnLW2oT5lss8OdKxc2Hs1EJGyACPdgNXKnRb4DjN9gaYUey8
# bbX8UgYBjergjwYO8euDOkjXNTGk47BOhs4kVufkt7s2iC94lRQ09xJhXVtFGqL9
# obRt1Z1PBCVxPyupScooTjIK4wTKy2KPEuKlbClyNquOX1ceYZp45498OyIhyD57
# tYedtYqtU2WyAO69tjVdysRuyENS7DEVw+zHqgD+fA/7OzzuPAzgNIaNem3zseTf
# CQIDAQABo4IBPjCCATowCQYDVR0TBAIwADAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0l
# BAwwCgYIKwYBBQUHAwMwYQYDVR0gBFowWDBWBgZngQwBBAEwTDAjBggrBgEFBQcC
# ARYXaHR0cHM6Ly9kLnN5bWNiLmNvbS9jcHMwJQYIKwYBBQUHAgIwGQwXaHR0cHM6
# Ly9kLnN5bWNiLmNvbS9ycGEwHwYDVR0jBBgwFoAU1MAGIknrOUvdk+JcobhHdgly
# A1gwKwYDVR0fBCQwIjAgoB6gHIYaaHR0cDovL3JiLnN5bWNiLmNvbS9yYi5jcmww
# VwYIKwYBBQUHAQEESzBJMB8GCCsGAQUFBzABhhNodHRwOi8vcmIuc3ltY2QuY29t
# MCYGCCsGAQUFBzAChhpodHRwOi8vcmIuc3ltY2IuY29tL3JiLmNydDANBgkqhkiG
# 9w0BAQsFAAOCAQEAscetsKMcvM1RcqxvfAitGIRf+6SWC9CPCLnaOCFXxxZBnPRl
# T/8t3JXNzUki4YatHuVV9g6+jfBF68lntWSGHt79yxauauIfMDzaA2Z3VcIFj+MS
# DVXRTVL4X3LFDpleKobCzr/L2clzf6UvS2w+GAsMaUTq+7LNyxmk+YZ04S/V/Q+u
# 336TIdsQeT7Q9hO7Z80Q9Uo1zIRZUoWl6eaJlDFae7xbSwFJVfDZGFcnNvBiy8AV
# 56pYblwWxu2t6AQYtIOwuAjSrpXleMz46mbbO7ES7LmtWIL8MrlOTBG9or9TMeGl
# AGz9Jzx7/aeBj79a6fdqEcMsfo4FnmKuPodZbDCCBUcwggQvoAMCAQICEHwbNTVK
# 59t050FfEWnKa6gwDQYJKoZIhvcNAQELBQAwgb0xCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5WZXJpU2lnbiwgSW5jLjEfMB0GA1UECxMWVmVyaVNpZ24gVHJ1c3QgTmV0
# d29yazE6MDgGA1UECxMxKGMpIDIwMDggVmVyaVNpZ24sIEluYy4gLSBGb3IgYXV0
# aG9yaXplZCB1c2Ugb25seTE4MDYGA1UEAxMvVmVyaVNpZ24gVW5pdmVyc2FsIFJv
# b3QgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMTQwNzIyMDAwMDAwWhcNMjQw
# NzIxMjM1OTU5WjCBhDELMAkGA1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENv
# cnBvcmF0aW9uMR8wHQYDVQQLExZTeW1hbnRlYyBUcnVzdCBOZXR3b3JrMTUwMwYD
# VQQDEyxTeW1hbnRlYyBDbGFzcyAzIFNIQTI1NiBDb2RlIFNpZ25pbmcgQ0EgLSBH
# MjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBANeVQ9Tc32euOftSpLYm
# MQRw6beOWyq6N2k1lY+7wDDnhthzu9/r0XY/ilaO6y1L8FcYTrGNpTPTC3Uj1Wp5
# J92j0/cOh2W13q0c8fU1tCJRryKhwV1LkH/AWU6rnXmpAtceSbE7TYf+wnirv+9S
# rpyvCNk55ZpRPmlfMBBOcWNsWOHwIDMbD3S+W8sS4duMxICUcrv2RZqewSUL+6Mc
# ntimCXBx7MBHTI99w94Zzj7uBHKOF9P/8LIFMhlM07Acn/6leCBCcEGwJoxvAMg6
# ABFBekGwp4qRBKCZePR3tPNgKuZsUAS3FGD/DVH0qIuE/iHaXF599Sl5T7BEdG9t
# cv8CAwEAAaOCAXgwggF0MC4GCCsGAQUFBwEBBCIwIDAeBggrBgEFBQcwAYYSaHR0
# cDovL3Muc3ltY2QuY29tMBIGA1UdEwEB/wQIMAYBAf8CAQAwZgYDVR0gBF8wXTBb
# BgtghkgBhvhFAQcXAzBMMCMGCCsGAQUFBwIBFhdodHRwczovL2Quc3ltY2IuY29t
# L2NwczAlBggrBgEFBQcCAjAZGhdodHRwczovL2Quc3ltY2IuY29tL3JwYTA2BgNV
# HR8ELzAtMCugKaAnhiVodHRwOi8vcy5zeW1jYi5jb20vdW5pdmVyc2FsLXJvb3Qu
# Y3JsMBMGA1UdJQQMMAoGCCsGAQUFBwMDMA4GA1UdDwEB/wQEAwIBBjApBgNVHREE
# IjAgpB4wHDEaMBgGA1UEAxMRU3ltYW50ZWNQS0ktMS03MjQwHQYDVR0OBBYEFNTA
# BiJJ6zlL3ZPiXKG4R3YJcgNYMB8GA1UdIwQYMBaAFLZ3+mlIR59TEtXC6gcydgfR
# lwcZMA0GCSqGSIb3DQEBCwUAA4IBAQB/68qn6ot2Qus+jiBUMOO3udz6SD4Wxw9F
# lRDNJ4ajZvMC7XH4qsJVl5Fwg/lSflJpPMnx4JRGgBi7odSkVqbzHQCR1YbzSIfg
# y8Q0aCBetMv5Be2cr3BTJ7noPn5RoGlxi9xR7YA6JTKfRK9uQyjTIXW7l9iLi4z+
# qQRGBIX3FZxLEY3ELBf+1W5/muJWkvGWs60t+fTf2omZzrI4RMD3R3vKJbn6Kmgz
# m1By3qif1M0sCzS9izB4QOCNjicbkG8avggVgV3rL+JR51EeyXgp5x5lvzjvAUoB
# CSQOFsQUecFBNzTQPZFSlJ3haO8I8OJpnGdukAsak3HUJgLDwFojMYIESjCCBEYC
# AQEwgZkwgYQxCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3Jh
# dGlvbjEfMB0GA1UECxMWU3ltYW50ZWMgVHJ1c3QgTmV0d29yazE1MDMGA1UEAxMs
# U3ltYW50ZWMgQ2xhc3MgMyBTSEEyNTYgQ29kZSBTaWduaW5nIENBIC0gRzICECJd
# b3lwHyBOe9DqGqLhfuMwCQYFKw4DAhoFAKB4MBgGCisGAQQBgjcCAQwxCjAIoAKA
# AKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFHM++cwRu1GNnumh78hOXlSW
# J4q/MA0GCSqGSIb3DQEBAQUABIIBAKK54oyc0s4w4jbIQOotzueoKoXhFOwmZP0R
# TGdhaP65j9Ojz0sx3/GY85vgO0n202VBh5MFbUpxEnEUwy+4cv+sezgPrj3F+80x
# DV2E2Uu630d5uIt4DzD44eM18Rr/qL/GwNM6u9FkRT6iphwJviYeY/yTcRZI93re
# 8z+3ilgunk/0fvinHZC/0Kp0DToOqnBRb1n4Dajj21gKYATFpV6jwmVn2rSbGuSx
# 9BBPVfXMK2GsBQncYxbsWlzphGZWeJM7sucqo3UXjwEXj4qskoqxq79/CvMBPQaT
# 97cJjnztDFQt3/7LPScA4klEvharAOBKkr1IzUKLocEPUrwUNNyhggILMIICBwYJ
# KoZIhvcNAQkGMYIB+DCCAfQCAQEwcjBeMQswCQYDVQQGEwJVUzEdMBsGA1UEChMU
# U3ltYW50ZWMgQ29ycG9yYXRpb24xMDAuBgNVBAMTJ1N5bWFudGVjIFRpbWUgU3Rh
# bXBpbmcgU2VydmljZXMgQ0EgLSBHMgIQDs/0OMj+vzVuBNhqmBsaUDAJBgUrDgMC
# GgUAoF0wGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MTgwMjI0MjEyMjIzWjAjBgkqhkiG9w0BCQQxFgQUh35KSGv4rhrdl5vx73Tu3AGH
# BiEwDQYJKoZIhvcNAQEBBQAEggEAGt9cvTmRLgq5qeShwDCo/MVZS4e0RycOmvBu
# J/ufBq1NnQO0oYxbacF6gV8w7p6uLjlXWFr/7Q7N27QwHmxQGZN5AjOmwB4eu2yK
# vYwPmhQPG9faHQMQoE4VmUyeNzDayBNqrDxVGWkoFfPnpODrn6Hxt8h4+4/CCQax
# JtfU23PohG2XK9j5kT5v34P9NV3cGazDQIsYFXbx2z2Pxm3jmPbd0whXAC7CFjZQ
# Hbv2UTqG+1IfoPbK4Bgi2Pmj5cwgkYghmXY01C0WariUMVST4KyB+m2R14BTSLev
# k9QgGazfH2XRmXdh6ZmRHgZHFXVADrG6g5VRZ+6y4q2KWgQthg==
# SIG # End signature block
