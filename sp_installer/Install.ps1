#-------------------------------------------
#
#   Application: SQL Server Service Pack Installer
#
#   Author: Amauri Viguera
#   Original Release: 2016-Apr-06
#
#   1.0 AV 2016-Apr-06 - Original Release
#   1.1 AV 2016-Sep-09 - and now we have to deal with new SP / CU reset, because next time future-proof
#   1.1 AV 2016-Dec-12 - updated to only launch CUInstaller if path is not empty
#   1.2 AV 2017-Jan-17 - updated to confirm valid $sqlVersion
#                       - install KB3210089 GDR for 2016 
#   1.3 AV 2017-Feb-02 - added KSTools 1.45.2 dependency
#                       - added pending reboot check 
#                       - added re-install arg
#   1.4 AV 2017-Feb-18  - added support for SQL 2008 R2
#   1.5 AV 2017-Feb-24  - added additional post-SP patches for SQL 2008
#   1.6 AV 2017-Mar-04  - added more logging to better track in splunk 
#                       - renamed switch to "-force"
#                       - sqlVersion param is now optional but validated later. this avoids breakage when sent incorrectly via salt.
#   1.7 AV 2017-Mar-05  - changed 2008 installation params, because they're 10 years old and undocumented
#   1.8 AV 2017-May-12  - removed KB3210089 GDR for SQL 2016 (already at SP1 CU2 and no longer required)
#                       - added hotfixes for 2008
#   1.9 AV 2017-Jul-29  - changed 2008 (non-R2) hotfix params
#   2.0 AV 2018-Jan-25 - added additional GDR for SQL 2008 R2 (KB4057113)
#                       - new subsystem to tackle 2012 GDRs
#                       - improved logic around SP0 for new SQL versions, such as 2017, that have a CU but no SP
#                       - added support for -sqlVersion 2017
#   2.1 AV 2018-Jul-27 - new GDRs for SQL 2012, 2008 and 2008 R2
#                       - updated to allow SP0 + CU# combination (first encountered in SQL 2017)
#   2.2 AV 2018-Aug-21 - refactor GDR installation to use the configuration file.
#   2.3 AV 2018-Oct-29 - Logging GDR exit code with write-hoststatus so we can track failures
#   2.4 LP 2020-Jul-27 - Update Pending Reboot check, added Get-PendingRebootStatus Function
#
#-------------------------------------------
Param
(
   [string]$sqlVersion,
   [switch]$force = $false
)

Import-Module KSTools
$requiredVersion = ((Get-KSToolsVersion) -ge [version]"1.45.2")

if (!($requiredVersion)) { write-hoststatus "SQL Server SP Installer: installation error - KSTools version not met" "FAIL" ; exit 3 }

#-------------------------------------------
#   Script Constants
#-------------------------------------------

$AppFName = "SQL Server Service Pack Installer"
$AppVer = "1"
$AppKey = "MSSQL\ServicePack"
$RepoServer = $env:REPOSERVER
$InstallCmd = ""

$ScriptRoot = $PSScriptRoot
if ($ScriptRoot -eq $null)
{
    $ScriptRoot = Split-Path $script:MyInvocation.MyCommand.Path
}

$COMPUTERNAME = $env:COMPUTERNAME

$ErrorActionPreference = "Stop"
$ErrorFlag = 0
$Env:SEE_MASK_NOZONECHECKS = 1

#-------------------------------------------
#   Script Variables
#-------------------------------------------

$ServicePackINIFile = "$ScriptRoot\files\ServicePackConfig.ini"

#-------------------------------------------
#   Subsystem Installations
#-------------------------------------------

$stamp = (get-date -format "yyyy-MM-dd HH:mm")
write-hoststatus "SQL Server SP Installer: starting installation at $($stamp)" "INFO"

#---------------------------------------------------------------------------------------------------------------------------------
# Function Name    : Get-PendingRebootStatus
# Function Details : This function is used to check if a server is pending for reboot and also the reason for pending reboot.
#---------------------------------------------------------------------------------------------------------------------------------

Function Get-PendingRebootStatus
{

    param($COMPUTERNAME)

    If ([string]::IsNullOrEmpty($COMPUTERNAME)) {   
    Write-HostStatus " Get-PendingRebootStatus : The passed parameter server name is empty. Please pass a valid argument." "FAIL"
    Break; }

       
    $rebootStatus = Invoke-Command -ComputerName $COMPUTERNAME -ScriptBlock {
                #param($COMPUTERNAME)

                $pendRebootProperties = [ordered] @{
                    RebootStatus      = 'NA'  
                    PendingReason     = ''
                }
                $pendRebootOjbect = New-Object -Type PSObject -Property $pendRebootProperties

              $result = @{
                  CBSRebootPending =$false
                  WindowsUpdateRebootRequired = $false
                  FileRenamePending = $false
                  SCCMRebootPending = $false
              }

              #Check CBS Registry
              $key = Get-Item "HKLM:Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction SilentlyContinue
              if ($null -ne $key)
              {
                  $result.CBSRebootPending = $true
                  $pendRebootOjbect.PendingReason += 'Component Based Servicing'
                  #Write-Output "$cluster : $serverName : Component Based Servicing - Reboot Pending : True" 
              }

              #Check Windows Update
              $key = Get-Item "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue
              if($null -ne $key)
              {
                  $result.WindowsUpdateRebootRequired = $true
                  $pendRebootOjbect.PendingReason += ', Windows Auto Update'
                   #Write-Output "$COMPUTERNAME : Auto Updates - Reboot Pending : True" 
              }

              #Check PendingFileRenameOperations
              $prop = Get-ItemProperty "HKLM:SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue 
              if($null -ne $prop)
              {
                  #PendingFileRenameOperations is not *must* to reboot?
                  $result.FileRenamePending = $true
                  $pendRebootOjbect.PendingReason += ', File Name Operations'
                  #Write-Output "$COMPUTERNAME : Pending File Rename Operations - Reboot Pending : True" 
              }

              #Check SCCM Client <http://gallery.technet.microsoft.com/scriptcenter/Get-PendingReboot-Query-bdb79542/view/Discussions#content>
              try
              {
                  $util = [wmiclass]"\\.\root\ccm\clientsdk:CCM_ClientUtilities"
                  $status = $util.DetermineIfRebootPending()
                  if(($null -ne $status) -and $status.RebootPending)
                  {
                      $result.SCCMRebootPending = $true
                      $pendRebootOjbect.PendingReason += ', SCCM Client Operation'
                      #Write-Output "$cluster : $serverName : Pending SCCM Client Operation - Reboot Pending : True" 
                  }
              }
              catch
              { }

              #Return Reboot required
              #Write-Output "$COMPUTERNAME : Pending Reboot Result :  $($result.ContainsValue($true)) " 
              $pendRebootOjbect.RebootStatus = $($result.ContainsValue($true))
              If($pendRebootOjbect.PendingReason)
              {
                  If(($pendRebootOjbect.PendingReason).Split(",",2)[0] -eq '')
                  {
                    $pendRebootOjbect.PendingReason = (($pendRebootOjbect.PendingReason).Split(",",2)[1]).trim()
                  }
              }
              Return $pendRebootOjbect
       } -ArgumentList $COMPUTERNAME
          
    Return $rebootStatus
}

$pendingRebootStatus = Get-PendingRebootStatus -COMPUTERNAME $COMPUTERNAME

# abort installation if a reboot is pending 
if ($pendingRebootStatus.RebootStatus -eq "True") { write-hoststatus "SQL Server SP Installer: installation error - pending reboot detected" "WARNING" ; Restart-Computer $COMPUTERNAME -Force }

# abort installation if configuration file is missing
if (!(test-path $ServicePackINIFile)) { write-hoststatus "SQL Server SP Installer: installation error - configuration file is missing" "FAIL" ; exit 3 }

# supported versions are 2012, 2014 and 2016
# and now 2017! :) 
if (($sqlVersion -ne "2012") -and ($sqlVersion -ne "2014") -and ($sqlVersion -ne "2016") -and ($sqlVersion -ne "2008R2") -and ($sqlVersion -ne "2008") -and ($sqlVersion -ne "2017")) { 
    write-hoststatus "SQL Server SP Installer: installation error - invalid SQL version specified" "FAIL"
    exit 1 
}

# if we specified the -force flag, remove the AppVer keys, which will force a reinstall 
if ($force) { Remove-RegistryKey "HKLM:\SOFTWARE\KPMG_US\APPVER\MSSQL\ServicePack" }

# figure out currently installed service pack

# looking at subsystem stamp, value is [AppVer],[MM/dd/yyyy] [HH:mm:ss]
# we split this and take the first word (AppVer)
# then we read the "new" version from the INI file 
# if the new version of the ini file is greater, then we remove the CU AppVer 
# this is done so we can move from something like SP1 CU6 to SP2 CU1 
# otherwise $CUVersion AppVer would prevent CU1 from being installed on top of old SP CU6 

$ErrorActionPreference = "SilentlyContinue"
$InstalledSP = ((Get-RegistryValue "HKLM:\SOFTWARE\KPMG_US\APPVER\MSSQL\ServicePack" "Install").split(',')[0])

if (!($InstalledSP)) { $InstalledSP = 0 } # in case no SP is installed

write-host "debug: Installed Service Pack is $($InstalledSP)"

# read installer executable from the ini file
$SPVersion = Get-IniValue "$ServicePackINIFile" "$SQLVersion" "SPVersion"
$CUVersion = Get-IniValue "$ServicePackINIFile" "$SQLVersion" "CUVersion"
$SPInstaller = Get-IniValue "$ServicePackINIFile" "$SQLVersion" "SPInstaller"

if ($CUVersion -gt 0) { $CUInstaller = Get-IniValue "$ServicePackINIFile" "$SQLVersion" "CUInstaller" }
if (($SPInstaller.length -eq 0) -and ($SPVersion -ne 0)) { write-hoststatus "SQL Server SP Installer: installation error - unable to read SP info from configuration file" "FAIL" ; exit 2 }

write-host "debug: Requested updates are SP$($SPVersion) CU$($CUVersion)"

# moving from SP1 -> SP2, or SP2 -> SP3, reset CU AppVer key
if ($SPVersion -gt $InstalledSP) { 
    write-host "debug: resetting CU AppVer key because of new Service Pack" "INFO"
    $ErrorActionPreference = "SilentlyContinue"
    Remove-RegistryValue "HKLM:\SOFTWARE\KPMG_US\APPVER\MSSQL\ServicePack" "InstallCU"
    $ErrorActionPreference = "Stop"
}

# cross your fingers that MS doesn't change these :)
$InstallCmd = "$SPInstaller /quiet /IAcceptSQLServerLicenseTerms /Action=Patch /AllInstances"

# and of course it turns out that's changed... :) 
if ($sqlVersion -eq "2008") { $InstallCmd = "$SPInstaller /quiet /Action=Patch /AllInstances" }

# install service pack
# use "SPVersion" from ini file in case a new service pack is needed

if ($SPVersion -gt 0) {
    if (Add-Subsystem $AppKey "Install" "SYSTEM" $SPVersion)
    {
        # launch installer 
        write-hoststatus "SQL Server SP Installer: Installing SQL $SQLVersion Service Pack $SPVersion ($($SPInstaller))" "OK"
        $ErrorFlag = (Run "$ScriptRoot\files\$InstallCmd" True True)
        write-hoststatus "SQL Server SP Installer: SP installation complete. Exit code $($ErrorFlag)" "OK"
        Close-Subsystem $AppKey "Install" "SYSTEM" $SPVersion
    }
}

# we don't break on non-zero exit code because it can be 3010 (reboot required) or others (N/A, already installed, etc.)
$pendingRebootStatus = Get-PendingRebootStatus -COMPUTERNAME $COMPUTERNAME
# check if SP installation left a pending reboot. if so, CU installation will fail 
if ($pendingRebootStatus.RebootStatus -eq "True") { write-hoststatus "SQL Server SP Installer: CU installation on hold pending reboot." "WARNING" ; Restart-Computer $COMPUTERNAME -Force }

if ($CUVersion -gt 0) {
    if (Add-Subsystem $AppKey "InstallCU" "SYSTEM" $CUVersion)
    {
        # only run the installer if CU is greater than 0
        # CU can be 0 for new SPs or brand new / defunct versions 
        write-hoststatus "SQL Server SP Installer: Installing SQL $SQLVersion Cummulative Update $CUVersion ($($CUInstaller))" "OK"
        $InstallCmdCU = "$CUInstaller /quiet /IAcceptSQLServerLicenseTerms /Action=Patch /AllInstances"
        $ErrorFlag = (Run "$ScriptRoot\files\$InstallCmdCU" True True)
        write-hoststatus "SQL Server SP Installer: CU installation complete. Exit code $($ErrorFlag)" "OK"
        Close-Subsystem $AppKey "InstallCU" "SYSTEM" $CUVersion
    }
}

# refactored GDR installation process as of 2018-Aug-21
# GDRs are becoming more frequent, so the configuration file now holds the list, and we can stop updating the script whenever one is released
$pendingRebootStatus = Get-PendingRebootStatus -COMPUTERNAME $COMPUTERNAME
if ($pendingRebootStatus.RebootStatus -eq "True") { write-hoststatus "SQL Server SP Installer: GDR installation on hold pending reboot." "WARNING" ; Restart-Computer $COMPUTERNAME -Force }

if (Add-Subsystem $AppKey "ApplyGDRs" "EXECUTE" $AppVer)
{
    # look for "GDRList=" item in the configuraton file for SQL version specified
    $GDRList = Get-IniValue "$ServicePackINIFile" "$SQLVersion" "GDRList"
    if ($GDRList) {
        # split if we have more than one comma-separated item
        if ( $GDRList.Contains(",") ) { $GDRList = $GDRList.Split(",") | % { $_.trim() } }

        write-hoststatus "SQL Server SP Installer: applying $($GDRList.count) GDRs for SQL Server $($SQLVersion)" "INFO"

        $flags = "/quiet /IAcceptSQLServerLicenseTerms /Action=Patch /AllInstances"
        # /IAcceptSQLServerLicenseTerms flag was introduced in 2008 R2
        if ($sqlVersion -eq "2008") { $flags = "/quiet /Action=Patch /AllInstances" }

        # loop through GDRs and install them using their own subsystem
        foreach ($item in $GDRList) {
            if (Add-Subsystem "$($AppKey)\$($item)" "Install" "SYSTEM" $AppVer)
            {
                write-hoststatus "SQL Server SP Installer: Installing $($item)" "INFO"
                $ErrorFlag = (Run "$ScriptRoot\files\$($item) $($flags)" True True)
                $logMessage = "SQL Server SP Installer: $($item) installation complete. Exit code $($ErrorFlag)."
                if ($ErrorFlag -eq "3010") { $logMessage += " Reboot required." }
                write-hoststatus  "$($logMessage)" "INFO"
                Close-Subsystem "$($AppKey)\$($item)" "Install" "SYSTEM" $AppVer
            } # GDR subsystem
        } # for each GDR in list
    } else {
        # if no GDR list present in configuration file, there's nothing to be done
        write-hoststatus "SQL Server SP Installer: No GDRs found for SQL $($SQLVersion)" "OK"
    } # if any GDRs are found on configuration file

    write-hoststatus "SQL Server SP Installer: GDR installation completed." "INFO"

    Close-Subsystem $AppKey "ApplyGDRs" "EXECUTE" $AppVer
}

write-hoststatus "SQL Server SP Installer: installation completed." "INFO"

exit

# SIG # Begin signature block
# MIIXkQYJKoZIhvcNAQcCoIIXgjCCF34CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUYNwGtIixaC13jKJvFxd2CBao
# OkagghKxMIID7jCCA1egAwIBAgIQfpPr+3zGTlnqS5p31Ab8OzANBgkqhkiG9w0B
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
# MAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFIbyaFgaIi9PbxpXBABHbDTQ
# tLOsMA0GCSqGSIb3DQEBAQUABIIBAHKVUeK2J770ujJS8iVk39Cn5STpPTKMr4rB
# 0sK6GzifHyYKyEZPfMFNENq3m9b5TkAVv/HsMvTJCiP68L8AJIoZe2dxKjeOsBn2
# hh7s7VzLx9yuJ28RQ0lBM1wA0gaEUC/AuKN09UGexokSKCHmVTtMwEUe8W5tRqX5
# u9OEq1aUlN4R6XH+2tLHXArMis+8ltlVEuoseWTe+S1UwNW8BX7Amvijqh5eDMAD
# ii1ttx407ttU+kqwVppd7+kyKTE6VbXjxL2XpojmaEqeRkUTP7LLzNAoRE/yE5i0
# Vz6pkVNZ6tgQE7IllO+0klpm2aZv8Gtw4umd4wOdZ8HcDn6+hAuhggILMIICBwYJ
# KoZIhvcNAQkGMYIB+DCCAfQCAQEwcjBeMQswCQYDVQQGEwJVUzEdMBsGA1UEChMU
# U3ltYW50ZWMgQ29ycG9yYXRpb24xMDAuBgNVBAMTJ1N5bWFudGVjIFRpbWUgU3Rh
# bXBpbmcgU2VydmljZXMgQ0EgLSBHMgIQDs/0OMj+vzVuBNhqmBsaUDAJBgUrDgMC
# GgUAoF0wGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MjAwNzMwMTgyNDI5WjAjBgkqhkiG9w0BCQQxFgQUPhyukR+oD9i9tTWZ7asFgQS9
# 5CMwDQYJKoZIhvcNAQEBBQAEggEAPF41UKl8t1PDlZg+7C6/ImyU4+orkLu59Zqq
# xDBB2SZlIuwbPcypM0D6At7LOraCypGHbjaySv7e6+uaEm13jhskJW4nsM+/LSqI
# shd4O71YyBa++bDnaFoh5pOqf908Yjrcp2MluzTwfhBgJLTdkDGLZgM/N0el6BFP
# BXWK2h/vLF8TqJWSVGBFV+a+N8mrh1kLdaDipWvYlAD5nQjg4R7MkPKVbYIRLSzO
# Y2nzY4rIlfuMxAMH+2+/pDG7sOK7l/3KX/7PI8OxhbOug5Md98x64irrMsOXf+Hk
# b2BP3p04+nDalAA5vlsG1F+hpYFLq0sklx/30Jem/jGwPNBo3g==
# SIG # End signature block
