function Get-SqlServerInstance 
{
<#
.Synopsis
   Gets SQL instances from a computer or array of computers
   Isaac H. Roitman, 2016
   v2.1
.DESCRIPTION
   Gets SQL instances and associated SQL instance properties from a computer or array of computers using .NET remote registry, finds the related Windows service information using WMI, and compiles the data into a custom PowerShell object
.EXAMPLE
   Get-SQLServerInstance -ComputerName SERVER1,SERVER2,SERVER3
.EXAMPLE
   (Get-ADComputer -Filter 'operatingsystem -like "*server*"' | sort Name).Name | Get-SQLServerInstance
   This example will retrieve all servers from Active Directory and pass the computer names (using pipeline) to Get-SqlServerInstance; this will essentially scan your whole domain for all SQL instances on all servers
.EXAMPLE
   Get-SQLServerInstance -ComputerName (Get-Content C:\TEMP\SERVERS.TXT) | Get-SqlDatabase
   This example will get SQL instances from a list of computers in a text file, then pipe the instances to Get-SqlDatabase cmdlet to get databases from each SQL instance using native PowerShell pipeline (based on ServerInstance named property)
.EXAMPLE
   Get-SqlServerInstance -ComputerName SERVER1,SERVER2,SERVER3 -ServerInstance *INS*
   This example will only return SQL instances which match the value *INS* (INS1, INS2, SQLINS will be returned); not mandatory and only used for filtering, otherwise * and all instances are returned
#>
    [CmdletBinding()]
    [Alias('gsi')]
    [OutputType([array])]
    Param
    (
        # ComputerName, please enter array or string values separated by comma
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [string[]]$ComputerName,

        # Return only specific SQL Server Instances matching this string
        [string]
        $ServerInstance="*"
    )

    begin
    {
        $sqlkey = "SOFTWARE\Microsoft\Microsoft SQL Server"
        $type = [Microsoft.Win32.RegistryHive]::LocalMachine
    }
    
    process
    {
        foreach ($computer in $ComputerName)
        {
            $computer = $computer.ToUpper()
            
            Write-Verbose "Working on $computer"
            
            $subs = $instances = $instance = $inskey = $sqlbasekey = $opensqlkey = $openbasekey = $instancename = @()        
        
            $ping = Test-Connection -ComputerName $computer -Count 1 -Quiet
        
            if ($ping)
            {
                try
                {
                    $sqlbasekey = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey($type, $computer)
                }
                catch
                {
                    Write-Error "Cannot query registry on $computer"
                }
                               
                if ($sqlbasekey)
                {
                    $opensqlkey = $sqlbasekey.OpenSubKey($sqlkey)

                    $sqlsubkeys = foreach ($sub in $opensqlkey.GetSubKeyNames()){$sub}

                    $instances = $sqlsubkeys | where {$_ -like "MSSQL*.*" -and $_ -like $ServerInstance -and $_ -notmatch "MSAS" -and $_ -notmatch "MSRS" -and $_ -notmatch "LOCAL"}

                    Write-Verbose "$($instances.count) SQL instances found on $computer $($instances -join ', ')"

                    foreach ($instance in $instances)
                    {
                        $inskey = "$sqlkey\$instance"

                        $instancename = $sqlbasekey.OpenSubkey($inskey).GetValue($null).tostring()

                        Write-Verbose "Gathering data for $computer\$instancename"
            
                        try
                        {
                            $clusname = $sqlbasekey.OpenSubKey($inskey + "\Cluster").GetValue('ClusterName')
                            $fullname = "$clusname\$instancename"
                        }
                        catch 
                        {
                            $clusname = $null
                            $fullname = "$computer\$instancename"
                        }

                        # Query SQL start parameters
                        $parameters = $sqlbasekey.OpenSubKey($inskey + "\MSSQLServer\Parameters").GetValueNames()

                        # Query the current SQL version
                        $currentversion = $sqlbasekey.OpenSubKey($inskey + "\MSSQLServer" + "\CurrentVersion").GetValue('CurrentVersion')

                        # Create SQLProduct (readable name) based on the current version number
                        $sqlproduct = switch -Wildcard ($currentversion) 
                        { 
                            "13.0*" {"SQL Server 2016"} 
                            "12.0*" {"SQL Server 2014"} 
                            "11.0*" {"SQL Server 2012"} 
                            "10.5*" {"SQL Server 2008 R2"} 
                            "10.0*" {"SQL Server 2008"}
                            "9.00*" {"SQL Server 2005"}
                            "8.00*" {"SQL Server 2000"}
                            default {"Unknown Version"}
                        }

                        # Query the specific instance's Windows service settings using Get-WMIObject
                        if ($instancename -match "MICROSOFT##SSEE") 
                        {
                            $service = Get-WmiObject -ComputerName $computer -Query "Select * from Win32_Service WHERE Name LIKE '%$instancename%'" | select SystemName,Name,Displayname,StartMode,StartName,State
                        }
                        else 
                        {
                            $service = Get-WmiObject -ComputerName $computer -Query "Select * from Win32_Service WHERE DisplayName = 'SQL Server ($instancename)'" | select SystemName,Name,Displayname,StartMode,StartName,State
                        } 

                        # Query SQL FullText settings      
                        try
                        {
                            $fulltext = $sqlbasekey.OpenSubKey($inskey + "\ClusterState").GetValue('SQL_FullText_Adv')
                        }
                        catch 
                        {
                            $fulltext = $null
                        }

                        # Create PS custom object and query all other data which doesn't require a condition or statement
                        [PSCustomObject] @{
                            ComputerName = $computer
                            ServerInstance = $fullname -replace "\\MSSQLSERVER"
                            InstanceName = $instancename
                            ClusterName = $clusname
                            ClusterInstance = if ($sqlbasekey.OpenSubKey($inskey + "\Setup").GetValue('SQLCluster') -eq '1') {$true} else {$false}                           
                            DefaultInstance = if ($fullname -match "\\MSSQLSERVER") {$true} else {$false}
                            SQLProduct = $sqlproduct
                            Edition = $sqlbasekey.OpenSubKey($inskey + "\Setup").GetValue('Edition')
                            ServicePack = $sqlbasekey.OpenSubKey($inskey + "\Setup").GetValue('SP')
                            CurrentVersion = $currentversion
                            PatchLevel = $sqlbasekey.OpenSubKey($inskey + "\Setup").GetValue('PatchLevel')
                            RegistryKey = $inskey
                            TCPPort = $sqlbasekey.OpenSubKey($inskey + "\MSSQLServer\SuperSocketNetLib\Tcp\IPAll").GetValue('TcpPort')
                            DynamicTCPPort = $sqlbasekey.OpenSubKey($inskey + "\MSSQLServer\SuperSocketNetLib\Tcp\IPAll").GetValue('TcpDynamicPorts')
                            ServiceName = $service.Name
                            ServiceDisplayName  = $service.DisplayName
                            ServiceAccountName = $service.StartName
                            ServiceStartMode = $service.StartMode
                            ServiceState = $service.State
                            SQLProgDir = $sqlbasekey.OpenSubKey($inskey + "\Setup").GetValue('SQLProgramDir')
                            SQLPath = $sqlbasekey.OpenSubKey($inskey + "\Setup").GetValue('SQLPath')
                            SQLDataRoot = $sqlbasekey.OpenSubKey($inskey + "\Setup").GetValue('SQLDataRoot')
                            BackupDirectory = $sqlbasekey.OpenSubKey($inskey + "\MSSQLServer").GetValue('BackupDirectory')
                            DefaultLogDirectory = $sqlbasekey.OpenSubKey($inskey + "\MSSQLServer").GetValue('DefaultLog')
                            ErrorDumpDirectory = $sqlbasekey.OpenSubKey($inskey + "\CPE").GetValue('ErrorDumpDir')
                            StartParameters = ($parameters | % {$sqlbasekey.OpenSubKey($inskey + "\MSSQLServer\Parameters").GetValue($_)}) -join ", "
                            FullText = if ($fulltext -eq '1') {$true} else {$false}
                        }
                    }
                }
            }
            else
            {
                Write-Error "$computer is not reachable"
            }
        }
    }
    end
    {
    }
}