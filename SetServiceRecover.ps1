# Simple script to Set Windows Service recovery option for all computer "active" (by last login time stamp" last x days 
# Recovery / failure option used here: Restart on any failure after 5minutes and  reset count after 5 days
# Last Mod by Tilo 2013-10-31
# Optimize Logging and Filter (e.g. check for online) as needed. :)
import-module activedirectory  
$domain = "my.domain.com"  
$DaysLastActive = 90
$time = (Get-Date).Adddays(-($DaysLastActive)) 
$ServiceName = "Hamachi2Svc"
$log = "C:\scripts\"+$ServiceName+"_Logfile.log"
$dttm = get-date -uformat "%Y-%m-%d %H:%M:%S"
Add-Content $log "------ $dttm : Start $ServiceName service setting ------"

  
# Get all AD computers with lastLogonTimestamp greater than our time set above
$ListOfComputer = Get-ADComputer -Filter {LastLogonTimeStamp -gt $time}
  
foreach ($PC in $ListOfComputer) {
$Computer = $PC.Name
$cmdstyle = sc.exe \\$Computer failure $ServiceName reset= 432000 actions= restart/300000/restart/300000/restart/300000
Add-Content $log "$Computer : $cmdstyle"
}

$dttm = get-date -uformat "%Y-%m-%d %H:%M:%S"
Add-Content $log "------ $dttm : End $ServiceName service setting------ "