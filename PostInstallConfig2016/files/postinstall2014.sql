--SQL2014 platform config script
--Set post install database security options
--Rename the sa account to SQL Admin
--added salt stack account Ed P 06152017
set noexec off set parseonly off
go 
ALTER LOGIN sa WITH NAME = SQLAdmin
go
--**** Old Group Removed*******************************************************
--CREATE LOGIN [US\US-SG DMG Montvale]
--FROM WINDOWS
--WITH DEFAULT_DATABASE = Master
--go
--EXEC dbo.sp_addsrvrolemember 'US\US-SG DMG Montvale', 'sysadmin'
--*****************************************************************************
CREATE LOGIN [US\us-svcacctnbu]
FROM WINDOWS
WITH DEFAULT_DATABASE = Master
go
EXEC dbo.sp_addsrvrolemember 'US\us-svcacctnbu', 'sysadmin'
go
--*****************************************************************************
--Adding new TechOps DMG groups
CREATE LOGIN [US\US-SG TechOps DMG SQL]
FROM WINDOWS
WITH DEFAULT_DATABASE = Master
go
EXEC dbo.sp_addsrvrolemember 'US\US-SG TechOps DMG SQL', 'sysadmin'
go
CREATE LOGIN [US\US-SG TechOps DMG SQLSvc]
FROM WINDOWS
WITH DEFAULT_DATABASE = Master
go
EXEC dbo.sp_addsrvrolemember 'US\US-SG TechOps DMG SQLSvc', 'sysadmin'
go
Declare @hostname varchar(25), @logintoadd varchar(25),@sqlquery nvarchar(max)
SELECT @hostname = convert(varchar,SERVERPROPERTY('ComputerNamePhysicalNetBIOS'),25) 
select @logintoadd = @hostname + '\saltstack'
set @sqlquery = 'CREATE LOGIN [' + @logintoadd +
'] from Windows WITH DEFAULT_DATABASE = Master' 
EXEC sp_executeSQL @sqlQuery
EXEC dbo.sp_addsrvrolemember @logintoadd , 'sysadmin'
go
--*****************************************************************************
--Adding new service account for Symantec CCS vulnerability Scans
USE [master]
GO
CREATE LOGIN [US\US-SVCCCSSQLSCAN] FROM WINDOWS WITH DEFAULT_DATABASE=[master]
GO
USE [master]
GO
CREATE USER [US\US-SVCCCSSQLSCAN] FOR LOGIN [US\US-SVCCCSSQLSCAN]
GO
USE [master]
GO
EXEC sp_addrolemember N'db_datareader', N'US\US-SVCCCSSQLSCAN'	
GO
--ALTER ROLE [db_datareader] ADD MEMBER [US\us-svcccssqlscan]
--GO
GRANT VIEW ANY DEFINITION TO [US\us-svcccssqlscan]
GO
GRANT EXECUTE ON [dbo].[xp_regread] TO [US\us-svcccssqlscan]
GRANT EXECUTE ON [dbo].[xp_instance_regread] TO [US\us-svcccssqlscan]
GRANT EXECUTE ON [dbo].[sp_helpuser] TO [US\us-svcccssqlscan]
GRANT EXECUTE ON [dbo].[sp_helprole] TO [US\us-svcccssqlscan]
GRANT EXECUTE ON [dbo].[sp_helprolemember] TO [US\us-svcccssqlscan]
GRANT EXECUTE ON [dbo].[sp_helpsrvrole] TO [US\us-svcccssqlscan]
GRANT EXECUTE ON [dbo].[sp_helpsrvrolemember] TO [US\us-svcccssqlscan]
GRANT EXECUTE ON [dbo].[xp_loginconfig] TO [US\us-svcccssqlscan]
GRANT EXECUTE ON [dbo].[xp_instance_regenumkeys] TO [US\us-svcccssqlscan]
GRANT EXECUTE ON [dbo].[sp_configure] TO [US\us-svcccssqlscan]
GRANT EXECUTE ON [dbo].[sp_helprotect] TO [US\us-svcccssqlscan]
GRANT EXECUTE ON [dbo].[sp_helpdb] TO [US\us-svcccssqlscan]
go
--  get the instance name in case of the install is not default install.
declare @nameServer varchar(100)
declare @nameMachine varchar(50)
declare @kInstance varchar(50)
declare @constrServer varchar(100)
declare @instancename varchar(30)
declare @path nvarchar(200)
select @nameMachine = convert(nvarchar(128), serverproperty('machinename'))
    select top 1 @instancename=name from sys.servers
  order by modify_date desc
 if len(@instancename) = len(@nameMachine)
select  @instancename='MSSQLSERVER'--it is not named instance.
else 
select @instancename = right(@instancename, len(@instancename) - (len(@nameMachine)+1));
set @path =N'E:\MSSQL12.'+@instancename+'\MSSQL\ERRORLOGS\SQLAGENT.OUT'
EXEC msdb.dbo.sp_set_sqlagent_properties @errorlog_file=@path


declare @mem bigint
   declare @MaxMem bigint
  declare @MinMem bigint
 declare @cpucount int

 select 
 @cpucount=cpu_count,
 @mem=convert(int,(round(convert(numeric(18,6),physical_memory_KB)/1024/1024,0)))
 from sys.dm_os_sys_info

  --06152016 Ed P changed memory settings calculations.
if @mem<=2
  set @mem=@mem*0.75--If the Windows server has less than 2 GB, 75% of the Windows server memory.  
 Else   if @mem >2 and @mem <=4--If the Windows server has 2 GB to 4 GB, 1 GB less than the Windows server memory.
 set @mem=@mem-1
  else if @mem>4 and @mem <=6 --If the Windows server has more than 4 GB but less than 6 GB, 2 GB less that the Windows server memory.
   set @mem=@mem-2
   else if @mem>6 and @mem <=12 --If the Windows server has more than 6 GB but less than 12 GB, 4 GB less that the Windows server memory.
   set @mem=@mem-4
   else if @mem>12 and @mem <=24 --If the Windows server has more than 12 GB but less than 24 GB, 6 GB less that the Windows server memory.
   set @mem=@mem-6
   else if @mem>24 and @mem <48 --If the Windows server has more than 24 GB but less than 48 GB, 8 GB less that the Windows server memory.
   set @mem=@mem-8
   else if @mem>=48 and @mem <=96 --If the Windows server has more than 36 GB but less than 96 GB, 12 GB less that the Windows server memory.
   set @mem=@mem-12
   else if @mem>96 and @mem <128 --If the Windows server has more than 96 GB but less than 128 GB, 16 GB less that the Windows server memory.
   set @mem=@mem-16
   else if @mem>=128   --If the Windows server has more than 128 GB set to 24 GB less that the Windows server memory.
   set @mem=@mem-24
  set @MaxMem=@mem
select (@mem *50/100)
  set @MinMem=round(@mem *20/100,0)
  if @MinMem=0 
  set @MinMem=1
  set @MinMem=@MinMem*1024
  if @MinMem > 6144
  set @MinMem = 6144
  set @MaxMem=@MaxMem*1024
  select @MinMem as 'MinMem'
   select @MaxMem as 'MaxMem'

--turn on advanced options to set memory and config options
EXEC sys.sp_configure N'show advanced options', N'1'  
RECONFIGURE WITH OVERRIDE
EXEC sys.sp_configure N'min server memory (MB)',@MinMem
EXEC sys.sp_configure N'max server memory (MB)', @MaxMem
--set SQL Agent Xps
exec sys.sp_configure 'Agent XPs', '1' 
RECONFIGURE WITH OVERRIDE
--enable mail xps
exec sp_configure 'Database Mail XPs','1'
--go
RECONFIGURE WITH OVERRIDE
--enable Compression
EXEC sp_configure 'backup compression default', 1 
RECONFIGURE WITH OVERRIDE 
--turn off advanced options
EXEC sys.sp_configure N'show advanced options', N'0'  
RECONFIGURE WITH OVERRIDE

declare @tempdbpath varchar(100)
select @tempdbpath=substring(filename,1,len(filename)-11) from tempdb.sys.sysfiles where fileid=1


-- split tempdb to multiple files.
declare @i int
set @i=2
declare @sql varchar(1000)
declare @counter int 
if @cpucount<=8  
  set @counter=@cpucount
else 
 set @counter=8
 

	while @I<=@counter
	begin
	select @i
	set @sql='ALTER DATABASE [tempdb] ADD FILE ( NAME = N''tempdb_0'+convert(varchar(2),@i)+''', FILENAME = N'''+@tempdbpath+'\tempdb_0'+convert(varchar(2),@i)+'.ndf'' , SIZE = 512MB , FILEGROWTH = 512MB  )'
	exec (@sql)
	set @i=@i+1
	end
USE [tempdb]
GO
DBCC SHRINKFILE (N'tempdev' , 512)
GO
DBCC SHRINKFILE (N'templog' , 512)
GO
USE [master]
GO
ALTER DATABASE [tempdb] MODIFY FILE ( NAME = N'tempdev', SIZE = 512MB,FILEGROWTH = 512MB )
GO
ALTER DATABASE [tempdb] MODIFY FILE ( NAME = N'templog', SIZE = 512MB,FILEGROWTH = 512MB )
GO
--Change Model DB Size settings.
ALTER DATABASE [model] MODIFY FILE ( NAME = N'modeldev', SIZE = 131072KB , FILEGROWTH = 131072KB )
GO
ALTER DATABASE [model] MODIFY FILE ( NAME = N'modellog', SIZE = 131072KB , FILEGROWTH = 131072KB )
GO
 

USE [master]
GO
EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'NumErrorLogs', REG_DWORD, 9
GO
xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\MSSQLServer\MSSQLServer',N'AuditLevel', REG_DWORD,3
go
RECONFIGURE WITH OVERRIDE
go


USE [msdb]
GO
/****** Object:  Alert [11 - Specified database object not found]    ******/
EXEC msdb.dbo.sp_add_alert @name=N'11 - Specified database object not found', 
		@message_id=0, 
		@severity=11, 
		@enabled=1, 
		@delay_between_responses=0, 
		@include_event_description_in=0, 
		@category_name=N'[Uncategorized]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'
USE [msdb]
GO
/****** Object:  Alert [14 - Insufficient Permission]    ******/
EXEC msdb.dbo.sp_add_alert @name=N'14 - Insufficient Permission', 
		@message_id=0, 
		@severity=14, 
		@enabled=1, 
		@delay_between_responses=0, 
		@include_event_description_in=0, 
		@category_name=N'[Uncategorized]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'
USE [msdb]
GO
/****** Object:  Alert [15 - Syntax Error in SQL Statements]    ******/
EXEC msdb.dbo.sp_add_alert @name=N'15 - Syntax Error in SQL Statements', 
		@message_id=0, 
		@severity=15, 
		@enabled=1, 
		@delay_between_responses=0, 
		@include_event_description_in=0, 
		@category_name=N'[Uncategorized]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'
USE [msdb]
GO
/****** Object:  Alert [17 - Insufficient Resources]    ******/
EXEC msdb.dbo.sp_add_alert @name=N'17 - Insufficient Resources', 
		@message_id=0, 
		@severity=17, 
		@enabled=1, 
		@delay_between_responses=0, 
		@include_event_description_in=0, 
		@category_name=N'[Uncategorized]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'
USE [msdb]
GO
/****** Object:  Alert [19 - Fatal Error in Resource]    ******/
EXEC msdb.dbo.sp_add_alert @name=N'19 - Fatal Error in Resource', 
		@message_id=0, 
		@severity=19, 
		@enabled=1, 
		@delay_between_responses=0, 
		@include_event_description_in=0, 
		@category_name=N'[Uncategorized]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'
USE [msdb]
GO
/****** Object:  Alert [20 - Fatal Error in Current Process]      ******/
EXEC msdb.dbo.sp_add_alert @name=N'20 - Fatal Error in Current Process', 
		@message_id=0, 
		@severity=20, 
		@enabled=1, 
		@delay_between_responses=0, 
		@include_event_description_in=0, 
		@category_name=N'[Uncategorized]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'
USE [msdb]
GO
/****** Object:  Alert [21- Fatal Error in Database Processes]   ******/
EXEC msdb.dbo.sp_add_alert @name=N'21- Fatal Error in Database Processes', 
		@message_id=0, 
		@severity=21, 
		@enabled=1, 
		@delay_between_responses=0, 
		@include_event_description_in=0, 
		@category_name=N'[Uncategorized]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'
USE [msdb]
GO
/****** Object:  Alert [22 - Fatal Error:  Table Integrity Suspect]     ******/
EXEC msdb.dbo.sp_add_alert @name=N'22 - Fatal Error:  Table Integrity Suspect', 
		@message_id=0, 
		@severity=22, 
		@enabled=1, 
		@delay_between_responses=0, 
		@include_event_description_in=0, 
		@category_name=N'[Uncategorized]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'
USE [msdb]
GO
/****** Object:  Alert [23 - Fatal Error:  Database Integrity Suspect]   ******/
EXEC msdb.dbo.sp_add_alert @name=N'23 - Fatal Error:  Database Integrity Suspect', 
		@message_id=0, 
		@severity=23, 
		@enabled=1, 
		@delay_between_responses=0, 
		@include_event_description_in=0, 
		@category_name=N'[Uncategorized]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'
USE [msdb]
GO
/****** Object:  Alert [24 - Fatal Error:  Hardware Error]    ******/
EXEC msdb.dbo.sp_add_alert @name=N'24 - Fatal Error:  Hardware Error', 
		@message_id=0, 
		@severity=24, 
		@enabled=1, 
		@delay_between_responses=0, 
		@include_event_description_in=0, 
		@category_name=N'[Uncategorized]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'
USE [msdb]
GO
/****** Object:  Alert [25 - Fatal Error]    ******/
EXEC msdb.dbo.sp_add_alert @name=N'25 - Fatal Error', 
		@message_id=0, 
		@severity=25, 
		@enabled=1, 
		@delay_between_responses=0, 
		@include_event_description_in=0, 
		@category_name=N'[Uncategorized]', 
		@job_id=N'00000000-0000-0000-0000-000000000000'
/*********************************************************************************Dropping the  login ****************************************/
Use [master]
go
declare @user varchar(40)
declare @sql varchar(200)
SELECT @user=SYSTEM_USER
select @user
set @sql='drop Login ['+@user+']'
exec (@sql)

