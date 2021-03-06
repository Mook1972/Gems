--updated on 11/09/2016 Ed P
--updated on 11/18/2016 Ed P
--non prod remove backup jobs 11/18/2016
--changed the job step type to T-SQL and pipe file to simple name
--removed the use of tokens 07262017

USE msdb
go

/****** Object:  Job [DatabaseIndexOptimize - USER_DATABASES] New Script Date: 10/14/2016 2:24:32 PM ******/

declare @version varchar(100) 
select @version =substring(@@version,22,4)
--select @version
if @version='2008'
    set @version='10_50'
else if @version='2012'
     set @version='11'
else if @version ='2014'
	 set @version='12'
else set @version ='13'
declare @nameMachine varchar(50)
declare @instancename varchar(30)
declare @path nvarchar(200)
declare @pathIO nvarchar(500)
select @nameMachine = convert(nvarchar(128), serverproperty('machinename'))
    select top 1 @instancename=name from sys.servers
  order by modify_date desc
 if len(@instancename) = len(@nameMachine)
select  @instancename='MSSQLSERVER'--it is not named instance.
else 
select @instancename = right(@instancename, len(@instancename) - (len(@nameMachine)+1));
set @path=N'E:\MSSQL'+ @version+'.'+@instancename +'\MSSQL\ErrorLogs\DatabaseIntegrityCheck_Log.txt'
set @pathIO=N'E:\MSSQL'+ @version+'.'+@instancename +'\MSSQL\ErrorLogs\IndexOptimize_Log.txt'

BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]    Script Date: 10/14/2016 2:24:32 PM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DatabaseIndexOptimize - USER_DATABASES', 
		@enabled=1, 
		@notify_level_eventlog=2, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Source: http://ola.hallengren.com',
		@category_name=N'Database Maintenance', 
		@owner_login_name=N'SQLADMIN', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [IndexOptimize - USER_DATABASES]    Script Date: 10/14/2016 2:24:32 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'IndexOptimize - USER_DATABASES', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, 
		@subsystem=N'TSQL',
		@command=N'EXECUTE dbo.IndexOptimize @Databases = ''USER_DATABASES'', @FragmentationLow = NULL, @FragmentationMedium = ''INDEX_REORGANIZE'', @FragmentationHigh = ''INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE'', @FragmentationLevel1 = ''10'', @FragmentationLevel2 = ''30'',@LogToTable = ''Y''', 
		@database_name=N'DMG_Utility',
		@output_file_name=@pathIO,
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'IndexOptimize - USER_DATABASES', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20161014, 
		@active_end_date=99991231, 
		@active_start_time=190000, 
		@active_end_time=235959, 
		@schedule_uid=N'b53329be-8707-4ad5-a7e8-e67d270bb186'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO


/****** Object:  Job [DatabaseStatisticsOptimize - USER_DATABASES]    Script Date: 10/20/2016 11:43:11 AM ******/

declare @version varchar(100) 
select @version =substring(@@version,22,4)
--select @version
if @version='2008'
    set @version='10_50'
else if @version='2012'
     set @version='11'
else if @version ='2014'
	 set @version='12'
else set @version ='13'
declare @nameMachine varchar(50)
declare @instancename varchar(30)
declare @path nvarchar(200)
declare @pathIO nvarchar(500)
declare @pathIO2 nvarchar(500)
select @nameMachine = convert(nvarchar(128), serverproperty('machinename'))
    select top 1 @instancename=name from sys.servers
  order by modify_date desc
 if len(@instancename) = len(@nameMachine)
select  @instancename='MSSQLSERVER'--it is not named instance.
else 
select @instancename = right(@instancename, len(@instancename) - (len(@nameMachine)+1));
set @path=N'E:\MSSQL'+ @version+'.'+@instancename +'\MSSQL\ErrorLogs\DatabaseIntegrityCheck_Log.txt'
set @pathIO=N'E:\MSSQL'+ @version+'.'+@instancename +'\MSSQL\ErrorLogs\IndexOptimize_Log.txt'
set @pathIO2=N'E:\MSSQL'+ @version+'.'+@instancename +'\MSSQL\ErrorLogs\StatisticsOptimize_Log.txt'
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [Database Maintenance]    Script Date: 10/20/2016 11:43:11 AM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Database Maintenance' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Database Maintenance'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DatabaseStatisticsOptimize - USER_DATABASES', 
		@enabled=1, 
		@notify_level_eventlog=2, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Source: http://ola.hallengren.com', 
		@category_name=N'Database Maintenance', 
		@owner_login_name=N'SQLADMIN', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [StatisticsOptimize - USER_DATABASES]    Script Date: 10/20/2016 11:43:11 AM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'StatisticsOptimize - USER_DATABASES', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0,  
		@subsystem=N'TSQL',
		@command=N'EXECUTE dbo.IndexOptimize @Databases = ''USER_DATABASES'', @FragmentationLow = NULL, @FragmentationMedium = NULL, @FragmentationHigh = NULL, @UpdateStatistics = ''ALL'', @OnlyModifiedStatistics = ''Y'', @LogToTable = ''Y''', 
		@database_name=N'DMG_Utility',
		@output_file_name= @pathIO2, 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'StatisticsOptimize - USER_DATABASES', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20161020, 
		@active_end_date=99991231, 
		@active_start_time=53000, 
		@active_end_time=235959, 
		@schedule_uid=N'34ae56f1-c426-4e68-a9ad-63c832537e4a'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

/****** Object:  Job [DatabaseIntegrityCheck - USER_DATABASES] New Script Date: 10/14/2016 2:33:02 PM ******/

declare @version varchar(100) 
select @version =substring(@@version,22,4)
--select @version
if @version='2008'
    set @version='10_50'
else if @version='2012'
     set @version='11'
else if @version ='2014'
	 set @version='12'
else set @version ='13'
declare @nameMachine varchar(50)
declare @instancename varchar(30)
declare @path nvarchar(200)
declare @pathIO nvarchar(500)
select @nameMachine = convert(nvarchar(128), serverproperty('machinename'))
    select top 1 @instancename=name from sys.servers
  order by modify_date desc
 if len(@instancename) = len(@nameMachine)
select  @instancename='MSSQLSERVER'--it is not named instance.
else 
select @instancename = right(@instancename, len(@instancename) - (len(@nameMachine)+1));
set @path=N'E:\MSSQL'+ @version+'.'+@instancename +'\MSSQL\ErrorLogs\DatabaseIntegrityCheck_Log.txt'
set @pathIO=N'E:\MSSQL'+ @version+'.'+@instancename +'\MSSQL\ErrorLogs\IndexOptimize_Log.txt'

BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [Database Maintenance]    Script Date: 10/14/2016 2:33:02 PM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Database Maintenance' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Database Maintenance'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DatabaseIntegrityCheck - USER_DATABASES', 
		@enabled=1, 
		@notify_level_eventlog=2, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Source: http://ola.hallengren.com', 
		@category_name=N'Database Maintenance', 
		@owner_login_name=N'SQLADMIN', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [DatabaseIntegrityCheck - USER_DATABASES]    Script Date: 10/14/2016 2:33:02 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'DatabaseIntegrityCheck - USER_DATABASES', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0,
		@subsystem=N'TSQL', 
		@command=N'EXECUTE [dbo].[DatabaseIntegrityCheck] @Databases = ''USER_DATABASES'', @LogToTable = ''Y''',
		@database_name=N'DMG_Utility', 
		@output_file_name=@path,
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'DatabaseIntegrityCheck - USER_DATABASES', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20140722, 
		@active_end_date=99991231, 
		@active_start_time=200000, 
		@active_end_time=235959, 
		@schedule_uid=N'5d4592c2-209f-4fcb-950a-d1a407dc535c'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO

/******************************************************MaintCleanup Job*******************************************/


USE [msdb]
GO

declare @version varchar(100) 

select @version =substring(@@version,22,4)
--select @version
if @version='2008'
    set @version='10_50'
else if @version='2012'
     set @version='11'
else if @version ='2014'
	 set @version='12'
else set @version ='13'
declare @nameMachine varchar(50)
declare @instancename varchar(30)
declare @path nvarchar(500)
declare @pathSI nvarchar(500)
declare @sql nvarchar(500)
select @nameMachine = convert(nvarchar(128), serverproperty('machinename'))
    select top 1 @instancename=name from sys.servers
  order by modify_date desc
 if len(@instancename) = len(@nameMachine)
select  @instancename='MSSQLSERVER'--it is not named instance.
else 
select @instancename = right(@instancename, len(@instancename) - (len(@nameMachine)+1));
--select @instancename
--set @sql=N'sqlcmd -E -S $(ESCAPE_SQUOTE(SRVR)) -d DMG_Utility -Q "EXECUTE [dbo].[DatabaseBackup] @Databases = ''SYSTEM_DATABASES'', @Directory = N''G:\MSSQL'+ @version+'.'+@instancename +'\MSSQL\Backup'', @BackupType = ''FULL'', @Verify = ''Y'', @CleanupTime = NULL, @CheckSum = ''Y'', @LogToTable = ''Y''" -b'
set @sql=N'cmd /q /c "For /F "tokens=1 delims=" %v In (''ForFiles /P "E:\MSSQL'+ @version+'.'+@instancename +'\MSSQL\errorlogs" /m *_*_*_*.txt /d -30 2^>^&1'') do if EXIST "E:\MSSQL'+ @version+'.'+@instancename +'\MSSQL\errorlogs"\%v echo del "E:\MSSQL'+ @version+'.'+@instancename +'\MSSQL\errorlogs"\%v& del "E:\MSSQL'+ @version+'.'+@instancename +'\MSSQL\errorlogs"\%v"'
--select @sql

/****** Object:  Job [MaintenanceJob_Cleanup]    Script Date: 09/24/2014 10:22:51 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]]    Script Date: 09/24/2014 10:22:51 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'MaintenanceJob_Cleanup', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sqladmin', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [CommandLog Cleanup]    Script Date: 09/24/2014 10:22:51 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'CommandLog Cleanup', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'DELETE FROM [dbo].[CommandLog] WHERE StartTime < DATEADD(dd,-30,GETDATE())', 
		@database_name=N'DMG_Utility',
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Output File Cleanup]    Script Date: 09/24/2014 10:22:51 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Output File Cleanup', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'CmdExec', 
		--@command=N'cmd /q /c "For /F "tokens=1 delims=" %v In (''ForFiles /P "E:\MSSQL10_50.MSSQLSERVER\MSSQL\errorlogs" /m *_*_*_*.txt /d -30 2^>^&1'') do if EXIST "E:\MSSQL10_50.MSSQLSERVER\MSSQL\errorlogs"\%v echo del "E:\MSSQL10_50.MSSQLSERVER\MSSQL\errorlogs"\%v& del "E:\MSSQL10_50.MSSQLSERVER\MSSQL\errorlogs"\%v"', 
		@command=@sql,
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [sp_delete_backuphistory]    Script Date: 09/24/2014 10:22:51 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'sp_delete_backuphistory', 
		@step_id=3, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL',
		@command=N'DECLARE @CleanupDate datetime SET @CleanupDate = DATEADD(dd,-30,GETDATE()) EXECUTE msdb.dbo.sp_delete_backuphistory @oldest_date = @CleanupDate', 
		@database_name=N'msdb',
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [sp_purge_jobhistory]    Script Date: 09/24/2014 10:22:51 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'sp_purge_jobhistory', 
		@step_id=4, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL',
		@command=N'DECLARE @CleanupDate datetime SET @CleanupDate = DATEADD(dd,-30,GETDATE()) EXECUTE msdb.dbo.sp_purge_jobhistory @oldest_date = @CleanupDate', 
		@database_name=N'MSDB',
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Maintenance_Cleanup', 
		@enabled=1, 
		@freq_type=8, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=1, 
		@active_start_date=20140924, 
		@active_end_date=99991231, 
		@active_start_time=60000, 
		@active_end_time=235959, 
		@schedule_uid=N'9f8fd84d-bf78-42db-a109-da0664212b55'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO


USE [msdb]
GO

/****** Object:  Job [Cycle Error Log]    Script Date: 11/19/2014 3:34:21 PM ******/


BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]    Script Date: 11/19/2014 3:34:21 PM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Cycle Error Log', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'SQLAdmin', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Cycle Error Log]    Script Date: 11/19/2014 3:34:21 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Cycle Error Log', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'dbcc errorlog', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Cycle Error Log', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20141119, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'353cc52a-ba8b-4eab-9416-a3348157cb23'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO

 

/*******************************Job Script Set_DBs_To_SimpleFor_NBU***************************/


USE [msdb]
GO

/****** Object:  Job [Set_DBs_To_SimpleFor_NBU]    Script Date: 6/8/2016 2:29:05 PM ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]    Script Date: 6/8/2016 2:29:05 PM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'Set_DBs_To_SimpleFor_NBU', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'This job will run daily and set all databases to simple recovery model for NBU. Only full backups will be taken with NetBackup.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'SQLADMIN', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Step1_RunScript]    Script Date: 6/8/2016 2:29:05 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Step1_RunScript', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'Declare @SAname varchar(25)
select @SAname = name from master..syslogins where SID = 0x1
if @SAname <> ''SQLADMIN''
Begin
exec msdb.dbo.sp_update_job @job_name=N''Set_DBs_To_SimpleFor_NBU'', @owner_login_name= @SAname
End
declare @name sysname,
	@recovery_model_desc nvarchar(120),
	@script nvarchar(500),
	@full_backup_count int
declare db cursor 
	for select name, recovery_model_desc from sys.databases where recovery_model_desc <> ''simple''
	for read only
open db
	fetch next from db into @name, @recovery_model_desc
	while @@fetch_status = 0
	begin
 		set @script = ''alter database ['' + @name + ''] set recovery simple''
  		exec sp_executesql @script
		print ''Database Recovery set to Simple for: '' + @name
		fetch next from db into @name, @recovery_model_desc
	end
close db
deallocate db', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Sched1', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20160608, 
		@active_end_date=99991231, 
		@active_start_time=191500, 
		@active_end_time=235959, 
		@schedule_uid=N'ffbf1aa9-d22f-476f-b282-d0083bfcb540'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO



/*********************************************************************************Dropping the  login ****************************************/
 



Use [master]
go
declare @user varchar(40)
declare @sql varchar(200)
SELECT @user=SYSTEM_USER
select @user
set @sql='drop Login ['+@user+']'
exec (@sql)