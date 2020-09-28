USE MASTER
GO
exec sp_revokelogin N'BUILTIN\Administrators';
exec sp_revokelogin N'NT Service\MSSQL$MSSQLSERVER';
exec sp_revokelogin N'NT Service\SQLAGENT$MSSQLSERVER';
EXEC sp_dropsrvrolemember 'US\us-svcsqlspinup', 'sysadmin';
GO