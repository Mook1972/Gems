# Get-LocalAdminGroupMember.ps1
# Written by Bill Stewart (bstewart@iname.com)

# This is a sample script that shows how to use WMI retrieve members of the
# local Administrators group on one or more computers. This script uses the
# group's SID (S-1-5-32-544) rather than the English name 'Administrators'.
# This means the script works on computers where the group isn't named
# 'Administrators' (for example, if the group is renamed or if it's on a non-
# English version of Windows). The script uses the GetRelated method to
# enumerate the group's members. Alternate credentials are supported for
# connecting to remote computers.
#
# A note about the -BlockSize parameter: This corresponds to the BlockSize
# property of the EnumerationOptions object that is passed as a parameter to
# the WMI GetRelated method. 50 is the default value (i.e., retrieve 50 members
# at a time), but you can of course use a different value if needed.

#requires -version 2

<#
.SYNOPSIS
Outputs the members of the local Administrators group on one or more computers.

.DESCRIPTION
Outputs the members of the local Administrators group on one or more computers using WMI. The Administrators group is retrieved by its SID (S-1-5-32-544) rather than the name 'Administrators'.

.PARAMETER ComputerName
Specifies one or more computer names. The default is the local computer. Wildcards are not permitted.

.PARAMETER Credential
Specifies credentials for the WMI connection to each computer. Credentials are ignored for the local computer.

.PARAMETER BlockSize
Specifies the number of members that will be retrieved at a time. The default value is 50.

.OUTPUTS
PSObjects with the following properties:
  ComputerName  The computer where the Administrators group is located
  Name          The localized name of the Administrators group
  Member        The member of the Administrators group

.EXAMPLE
PS C:\> Get-LocalAdminGroupMember
Outputs the members of the Administrators group on the current computer.

.EXAMPLE
PS C:\> Get-LocalAdminGroupMember computer1,computer2
Outputs the members of the Administrators groups on the specified computers.

.EXAMPLE
PS C:\> $credential = Get-Credential
PS C:\> Get-LocalAdminGroupMember computer1,computer2 -Credential $credential
Outputs the members of the Administrators groups on the specified computers using alternate credentials.

.EXAMPLE
PS C:\> Get-Content ComputerList.txt | Get-LocalAdminGroupMember -BlockSize 20
Outputs the members of the Administrators groups on each computer listed in the file Computers.txt. The groups are output 20 members at a time.

.LINK
WMI BlockSize property: http://msdn.microsoft.com/en-us/library/system.management.enumerationoptions.blocksize.aspx
#>

param(
  [parameter(Position=0,ValueFromPipeline=$true)]
    $ComputerName=[Net.Dns]::GetHostName(),
    [System.Management.Automation.PSCredential] $Credential,
    [UInt32] $BlockSize=50
)

begin {
  $WMIEnumOpts = new-object System.Management.EnumerationOptions
  $WMIEnumOpts.BlockSize = $BlockSize

  function GetLocalAdminGroupMember {
    param(
      [String] $computerName,
      [System.Management.Automation.PSCredential] $credential
    )
    $params = @{
      "Class" = "Win32_Group"
      "ComputerName" = $computerName
      "Filter" = "LocalAccount=TRUE and SID='S-1-5-32-544'"
    }
    if ( $credential ) {
      if ( $computerName -eq [Net.Dns]::GetHostName() ) {
        Write-Warning "The -Credential parameter is ignored for the current computer."
      }
      else {
        $params.Add("Credential", $credential)
      }
    }
    Get-WmiObject @params | ForEach-Object {
      $groupName = $_.Name
      $_.GetRelated("Win32_Account","Win32_GroupUser","","",
        "PartComponent","GroupComponent",$false,$WMIEnumOpts) | Select-Object `
          @{Name="ComputerName"; Expression={$_.__SERVER}},
          @{Name="Name"; Expression={$groupName}},
          @{Name="Member"; Expression={$_.Caption -replace "^$($_.__SERVER)\\", ""}},
          @{Name="Type"; Expression={$_.__CLASS}}
    }
  }
}

process {
  foreach ( $computerNameItem in $computerName ) {
    GetLocalAdminGroupMember $computerNameItem $Credential
  }
}
