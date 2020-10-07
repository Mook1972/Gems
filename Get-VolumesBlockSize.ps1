$wmiQuery = "SELECT Name, Label, Blocksize FROM Win32_Volume WHERE FileSystem='NTFS'"
Get-WmiObject -Query $wmiQuery -ComputerName '.' | Sort-Object Name | Select-Object Name, Label, Blocksize
