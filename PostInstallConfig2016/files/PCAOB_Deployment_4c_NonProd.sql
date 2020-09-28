--08152016 This script is the deployment script for the PCAOB job
--Rev 4c Ed Pochinski - Non Prod
--08152016 added create directory code for cluster failovers will create new but not overwrite old
--08162016 added code to change db owner to SA account name
--08172016 added code assign SA as job owner
--09022016 added time stamp variable and print for csv
--09162016 changed from DMG_UTILITY1 to DMG_UTILITY and re tested
--09282016 changed the SQLAgent job owner from Service account to SQLADMIN account also added a new field
--for dbrole output and server role output
--12072016 Added logic to determine if xp_cmdshell is turned on and do not turn off when completed
--12082016 Added a Servername stamp in the output file name for clusters
--12132016 Added a new file stamp to include MSSQLSERVER for default instances
--12152016 introduced a procedure to print the version installed for tracking purposes
--05162017 built the NonProd version with server name file stamp and tested
--06272017 added server\instance stamps to the file name and extended the field in the csv
--removed the output log and aadded a job description for the GUI

if not exists(select * from sys.databases where name = 'DMG_UTILITY')
Begin
    create database DMG_UTILITY
	Print 'DMG_UTILITY Database Created'
End
GO
USE DMG_UTILITY
GO
if exists(select name from sys.objects where name = 'usp_PCAOB_Version')
DROP PROCEDURE [dbo].[usp_PCAOB_Version]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
create Proc [dbo].[usp_PCAOB_Version]
as
Print @@servername + ',PCAOB Rev4c NonProd '
GO
Declare @sasid varchar(25)
select @sasid = name from master..syslogins where sid = 0x01
exec sp_changedbowner @sasid
go
if exists (select * from dbo.sysobjects where id = object_id(N'[dbo].[Audit_ServerRoles_2a]') and OBJECTPROPERTY(id, N'IsProcedure') = 1)
 drop procedure [dbo].[Audit_ServerRoles_2a]
GO 
create proc [dbo].[Audit_ServerRoles_2a]
  as
Declare @name varchar(55),@srvname varchar(55),@ServerRole2 varchar(55),@dbrole2 varchar(55),@membername varchar(100),@timestamp varchar(25)
Set NOCOUNT ON
Select @timestamp = CONVERT(varchar, CURRENT_TIMESTAMP , 112)
CREATE TABLE #temp_rolemember_final  
(ServerRole VARCHAR(100), DbRole VARCHAR(128),MemberName VARCHAR(128)) 
Declare @sqlsvr varchar(100),@sqlstr2 varchar(500), @sqlsvrstamp varchar(500)
select @timestamp = CONVERT(varchar, CURRENT_TIMESTAMP , 112)
Select @sqlsvr = @@SERVERNAME
If @sqlsvr LIKE '%\%' 
Select @sqlsvrstamp = replace(@sqlsvr,'\','_')
Else
Select @sqlsvrstamp = @sqlsvr + '_MSSQLSERVER'  
DECLARE @ServerRole VARCHAR(128) 
DECLARE @sqlcmd2 VARCHAR(1000) 
--TRUNCATE TABLE #temp_rolemember_final  
SET @sqlcmd2 = 'EXEC sp_helpsrvrolemember' 
 
INSERT INTO #temp_rolemember_final 
EXECUTE(@sqlcmd2) 

DECLARE ServerRole_cursor2 INSENSITIVE CURSOR
	FOR
 SELECT ServerRole,DbRole, MemberName FROM #temp_rolemember_final
where membername not in ('dbo')
	FOR READ ONLY 
OPEN ServerRole_cursor2
FETCH next FROM ServerRole_cursor2 into @ServerRole2,@dbrole2,@membername 
	WHILE @@fetch_status = 0
BEGIN

Print 'NONPROD:' + @sqlsvrstamp +  ',' + @dbrole2 + ',' + @ServerRole2 + ',' + @timestamp + ',' + 'SrvRole'

FETCH NEXT FROM ServerRole_cursor2 INTO @ServerRole2,@dbrole2,@membername 
END
CLOSE ServerRole_cursor2
DEALLOCATE ServerRole_cursor2  

 
DROP TABLE #temp_rolemember_final 


GO


if exists (select * from dbo.sysobjects where id = object_id(N'[dbo].[Audit_DatabaseRoles_2a]') and OBJECTPROPERTY(id, N'IsProcedure') = 1)
 drop procedure [dbo].[Audit_DatabaseRoles_2a]
GO 
Create Proc [dbo].[Audit_DatabaseRoles_2a]
as
Declare @name varchar(55),@srvname varchar(55),@dbname2 varchar(55),@dbrole2 varchar(55),@membername varchar(100),@timestamp varchar(25)
Set NOCOUNT ON
Select @timestamp = CONVERT(varchar, CURRENT_TIMESTAMP , 112)
CREATE TABLE #temp_rolemember  
(DbRole VARCHAR(128),MemberName VARCHAR(128),MemberSID VARCHAR(1000)) 
CREATE TABLE #temp_rolemember_final  
(DbName VARCHAR(100), DbRole VARCHAR(128),MemberName VARCHAR(128)) 
Declare @sqlsvr varchar(100),@sqlstr2 varchar(500), @sqlsvrstamp varchar(500)
select @timestamp = CONVERT(varchar, CURRENT_TIMESTAMP , 112)
Select @sqlsvr = @@SERVERNAME
If @sqlsvr LIKE '%\%' 
Select @sqlsvrstamp = replace(@sqlsvr,'\','_')
Else
Select @sqlsvrstamp = @sqlsvr + '_MSSQLSERVER'  

DECLARE @dbname VARCHAR(128) 
DECLARE @sqlcmd2 VARCHAR(1000) 

DECLARE grp_role CURSOR FOR  
SELECT name FROM master..sysdatabases 
WHERE name NOT IN ('tempdb')  
AND DATABASEPROPERTYEX(name, 'Status') = 'ONLINE'  


OPEN grp_role 
FETCH NEXT FROM grp_role INTO @dbname 

WHILE @@FETCH_STATUS = 0 
BEGIN 

TRUNCATE TABLE #temp_rolemember  
SET @sqlcmd2 = 'EXEC [' + @dbname + ']..sp_helprolemember' 

--PRINT @sqlcmd2  
INSERT INTO #temp_rolemember 
EXECUTE(@sqlcmd2) 

INSERT INTO #temp_rolemember_final 
SELECT @dbname AS DbName, DbRole, MemberName 
FROM #temp_rolemember 

FETCH NEXT FROM grp_role INTO @dbname 
END 


CLOSE grp_role 
DEALLOCATE grp_role
--Select * FROM #temp_rolemember_final
 DECLARE dbname_cursor2 INSENSITIVE CURSOR
	FOR
 SELECT DbName,DbRole, MemberName FROM #temp_rolemember_final
where membername not in ('dbo')
	FOR READ ONLY 
OPEN dbname_cursor2
FETCH next FROM dbname_cursor2 into @dbname2,@dbrole2,@membername 
	WHILE @@fetch_status = 0
BEGIN

Print 'NONPROD:' + @sqlsvrstamp +  ','+@dbname2 + ',' + @membername + ','+   @dbrole2 + ',' + @timestamp + ',' + 'DBRole'

FETCH NEXT FROM dbname_cursor2 INTO @dbname2,@dbrole2,@membername 
END
CLOSE dbname_cursor2
DEALLOCATE dbname_cursor2  

DROP TABLE #temp_rolemember 
DROP TABLE #temp_rolemember_final 


GO
--PCAOB Job Deployment Code

USE [msdb]
GO
--check if job exists and drop it
IF EXISTS (SELECT name FROM msdb.dbo.sysjobs WHERE name='AuditArtifacts')
EXEC msdb.dbo.sp_delete_job @job_name=N'AuditArtifacts', @delete_unused_schedule=1
GO
/**
Declare @SaName varchar(25)
select @SaName = name from master..syslogins where SID = 0x1
**/
SET NOCOUNT ON
/**
Declare @serviceAccname varchar(35)
DECLARE @sqltxt1 nvarchar (1024),@sqltxt2 nvarchar (1024),@sqltxt3 nvarchar (1024)
select  @serviceAccname = service_account from sys.dm_server_services
where servicename LIKE 'SQL Server%'
**/
Declare @sasid varchar(25)
select @sasid = name from master..syslogins where sid = 0x01
exec sp_changedbowner @sasid
/****** Object:  Job [AuditArtifacts]    Script Date: 8/15/2016 6:32:36 PM ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]    Script Date: 8/15/2016 6:32:36 PM ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'AuditArtifacts', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'The job lands Non Production physical artifact files on disk for auditing purposes.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name= @sasid, @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Create_Directory]    Script Date: 8/15/2016 6:32:36 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Create_Directory', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'PowerShell', 
		@command=N'New-Item -path "C:\AuditArtifacts" -type directory', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Build_Artifact_DatabaseRoleFiles]    Script Date: 8/15/2016 6:32:36 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Build_Artifact_DatabaseRoleFiles', 
		@step_id=2, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
Declare @value_in_use sql_variant
SELECT @value_in_use = value_in_use FROM sys.configurations where name = ''xp_cmdshell''
--Select @value_in_use
If @value_in_use = 0
Begin
Print ''Turning on''
exec sp_configure ''show advanced options'',''1'';
RECONFIGURE WITH OVERRIDE;
exec sp_configure ''xp_cmdshell'',''1'';
RECONFIGURE WITH OVERRIDE;
End
Declare @sqlsvr varchar(100),@sqlstr2 varchar(500),@timestamp varchar(25),@sqlsvrstamp varchar(500)
select @timestamp = CONVERT(varchar, CURRENT_TIMESTAMP , 112)
Select @sqlsvr = @@SERVERNAME
If @sqlsvr LIKE ''%\%'' 
Select @sqlsvrstamp = replace(@sqlsvr,''\'',''_'')
Else
Select @sqlsvrstamp = @sqlsvr + ''_MSSQLSERVER''
--Print @sqlsvrstamp 
Select @sqlstr2 = '' sqlcmd -S''+@sqlsvr+'' -E -dMaster -Q"Exec DMG_UTILITY..Audit_DatabaseRoles_2a" >C:\AuditArtifacts\AuditArtifacts_'' + @sqlsvrstamp + ''_DatabaseRole_'' + @timestamp + ''.csv''
--Print @sqlstr2
EXEC master..xp_cmdshell @sqlstr2

If @value_in_use = 0
Begin
exec sp_configure ''xp_cmdshell'',0;
RECONFIGURE WITH OVERRIDE;
End
If @@error = 0
Print '' Data loaded to file successfully''
else
Print '' Check the errors in this log''',
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Build_Artifact_ServerRoleFile]    Script Date: 8/15/2016 6:32:36 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Build_Artifact_ServerRoleFile', 
		@step_id=3, 
		@cmdexec_success_code=0, 
		@on_success_action=3, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'
Declare @value_in_use sql_variant
SELECT @value_in_use = value_in_use FROM sys.configurations where name = ''xp_cmdshell''
--Select @value_in_use
If @value_in_use = 0
Begin
Print ''Turning on''
exec sp_configure ''show advanced options'',''1'';
RECONFIGURE WITH OVERRIDE;
exec sp_configure ''xp_cmdshell'',''1'';
RECONFIGURE WITH OVERRIDE;
End
Declare @sqlsvr varchar(100),@sqlstr2 varchar(500),@timestamp varchar(25),@sqlsvrstamp varchar(500)
select @timestamp = CONVERT(varchar, CURRENT_TIMESTAMP , 112)
Select @sqlsvr = @@SERVERNAME
If @sqlsvr LIKE ''%\%'' 
Select @sqlsvrstamp = replace(@sqlsvr,''\'',''_'')
Else
Select @sqlsvrstamp = @sqlsvr + ''_MSSQLSERVER''
Print @sqlsvrstamp 
Select @sqlstr2 = '' sqlcmd -S''+@sqlsvr+'' -E -dMaster -Q"Exec DMG_UTILITY..Audit_ServerRoles_2a" >C:\AuditArtifacts\AuditArtifacts_'' + @sqlsvrstamp + ''_ServerRoles_'' + @timestamp + ''.csv''
--Print @sqlstr2
EXEC master..xp_cmdshell @sqlstr2

If @value_in_use = 0
Begin
exec sp_configure ''xp_cmdshell'',0;
RECONFIGURE WITH OVERRIDE;
End
If @@error = 0
Print '' Data loaded to file successfully''
else
Print '' Check the errors in this log''', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [Remove_Old_Files]    Script Date: 8/15/2016 6:32:36 PM ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Remove_Old_Files', 
		@step_id=4, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'PowerShell', 
		@command=N'#path to files to remove
$path = "C:\AuditArtifacts\"
#days old to remove
$hours = 46
$FileExtension = "*.csv"
$Now = Get-Date
$LastWrite = $Now.AddHours(-$hours)
#fetch files and remove
$Files = Get-Childitem $path -Include $FileExtension -Recurse | Where {$_.LastWriteTime -le "$LastWrite"}
foreach ($File in $Files)
    {
    if ($File -ne $NULL)
        {
      
        Remove-Item $File.FullName | out-null
        }
    }', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Schedule1', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20160729, 
		@active_end_date=99991231, 
		@active_start_time=70000, 
		@active_end_time=235959, 
		@schedule_uid=N'2fcdddc9-aaf4-4bf4-8e27-cb01ad94bc89'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO
Select @@ServerName
Print 'PCAOB Audit objects deployed'
 









