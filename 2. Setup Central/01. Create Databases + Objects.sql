/*
This script creates the db_cdba and db_dba databases on the Central server
It also creates some useful objects in db_cdba to be used by the all the systems
*/
if db_id('db_cdba') is null
	create database db_cdba
go
if db_id('db_dba') is null
	create database db_dba
go
use db_cdba
GO
IF schema_id('Management') IS NULL
	EXEC('CREATE SCHEMA Management')
GO
IF schema_id('Infra') IS NULL
	EXEC('CREATE SCHEMA Infra')
GO
if OBJECT_ID('Management.DatabaseInstances') is null
	CREATE TABLE Management.DatabaseInstances
		(DBI_ID int not null identity constraint PK_DatabaseInstances primary key clustered,
		DBI_Name nvarchar(128) not null,
		DBI_IsTrusted bit not null,
		DBI_IsActive bit not null)
GO
if OBJECT_ID('Management.Settings') is null
	CREATE TABLE Management.Settings
		(SET_System varchar(100) NOT NULL,
		SET_Key varchar(100) NOT NULL,
		SET_Value sql_variant NULL,
		CONSTRAINT PK_Settings PRIMARY KEY CLUSTERED(SET_System, SET_Key))
GO
if OBJECT_ID('Management.fn_GetSettingValue') is not null
	drop function Management.fn_GetSettingValue
GO
create function Management.fn_GetSettingValue(@System varchar(100),
												@Key varchar(100)) returns sql_variant
as
begin
	return (select SET_Value
			from Management.Settings
			where SET_System = @System
				and SET_Key = @Key)
end
GO
if OBJECT_ID('Infra.Numbers') is null
begin
	create table Infra.Numbers(Num int identity(1, 1) PRIMARY KEY CLUSTERED, a int)

	exec('insert into Infra.Numbers(a)
	select top 100000 a.id
	from master..syscomments a
		cross join master..syscomments b')

	exec('alter table Infra.Numbers drop column a')
end
GO
if OBJECT_ID('Infra.PowershellScripts') is null
	CREATE TABLE Infra.PowershellScripts
		(PSC_Name varchar(100) not null constraint PK_PowershellScripts primary key clustered,
		PSC_Script varchar(max))
GO
if OBJECT_ID('Infra.fn_SplitString') is not null
	drop function Infra.fn_SplitString
GO
create function Infra.fn_SplitString(
		@Str nvarchar(max),
		@Delimiter varchar(10) = ',') returns table
/*
This function is used for splitting strings into tables
*/
return
(
select substring(@Str, num, charindex(@Delimiter, @Str + @Delimiter, num) - num) Val
from SYL.Numbers
where num <= len(@Str) and substring(@Delimiter + @Str, num, len(@Delimiter)) = @Delimiter
)
GO
if OBJECT_ID('Infra.usp_RunCommandAsJob') is not null
	drop procedure Infra.usp_RunCommandAsJob
GO
CREATE procedure Infra.usp_RunCommandAsJob
	@Command nvarchar(max),
	@SubSystemName nvarchar(128), --The options are 'TSQL' or 'CmdExec'
	@ErrorNumber int = null output,
	@ErrorMessage nvarchar(2000) = null output,
	@Message nvarchar(max) = null output
as
/*
This procedure is used for running a command wrpped in a job.
It is used for 2 things:
	1. Running cmd commands (no results) without using xp_cmdshell.
	2. Running backup and restore and getting the reql reason for failure
*/
set nocount on
if @Command is null return

declare @job_name sysname,
		@job_id uniqueidentifier

select @ErrorNumber = null,
		@ErrorMessage = null,
		@Message = null

set @job_name = cast(newid() as nvarchar(100))

while exists (select 1 from msdb..sysjobs where name = @job_name)
	set @job_name += 'A'

DECLARE @JobID BINARY(16)
DECLARE @ReturnCode INT

SELECT @ReturnCode = 0	

begin try
	if not exists (select *
					from sys.sysprocesses 
					where [program_name] = N'SQLAgent - Generic Refresher')
		raiserror('The SQL Server Agent isn''t running', 16, 1)

	if not exists (SELECT 1 FROM msdb.dbo.syscategories WHERE name = N'[Uncategorized (Local)]')
		exec msdb.dbo.sp_add_category @name = N'[Uncategorized (Local)]'
		
	exec @ReturnCode = msdb.dbo.sp_add_job @job_id = @JobID OUTPUT,
		@job_name = @job_name,
		@owner_login_name = N'sa',
		@description = N'No description available.',
		@category_name = N'[Uncategorized (Local)]',
		@enabled = 0,
		@notify_level_email = 0,
		@notify_level_page = 0,
		@notify_level_netsend = 0,
		@notify_level_eventlog = 2,
		@delete_level = 0

	if @ReturnCode <> 0
		raiserror('Error creating job', 16, 1)

	exec @ReturnCode = msdb.dbo.sp_add_jobstep @job_id = @JobID,
												@step_id = 1,
												@step_name = N'Run Command',
												@command = @Command,
												@database_name = N'master',
												@server = N'',
												@database_user_name = N'',
												@subsystem = @SubsystemName,
												@cmdexec_success_code = 0,
												@flags = 0,
												@retry_attempts = 0,
												@retry_interval = 1,
												@output_file_name = N'',
												@on_success_step_id = 0,
												@on_success_action = 1,
												@on_fail_step_id = 0,
												@on_fail_action = 2
	if @ReturnCode <> 0
		raiserror('Error adding job step', 16, 1)

	exec @ReturnCode = msdb.dbo.sp_update_job @job_id = @JobID,
												 @start_step_id = 1

	if @ReturnCode <> 0
		raiserror('Error setting startup step', 16, 1)

	exec @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @JobID,
									@server_name = N'(local)'

	if @ReturnCode <> 0
		raiserror('Error adding job server', 16, 1)

	select @job_id = job_id
	from msdb..sysjobs
	where name = @job_name

	exec msdb..sp_start_job @job_name = @job_name, @output_flag = 0

	while not exists (select * from msdb..sysjobhistory where job_id = @job_id and step_id = 1)
		waitfor delay '00:00:00.5'

	select top 1 @Message = [Message]
	from msdb..sysjobhistory
	where job_id = @job_id and step_id = 1
	order by instance_id desc

	if @Message like '%The step succeeded%'
		select @ErrorNumber = 0,
				@ErrorMessage = null
	else
	begin
		;With ErrorParse1 as
			(select substring(@Message, charindex('.', @Message, 1) + 2, 2000) ErrorMessage)
			,ErrorParse2 as
			(select ErrorMessage,
				substring(ErrorMessage,
						charindex('(Error ', ErrorMessage, 1) + len('(Error ') + 1, 100) ErrorNumber
			from ErrorParse1)
		select @ErrorMessage = case when @SubSystemName = 'CmdExec' and ErrorMessage like '%(reason:%'
									then replace(stuff(ErrorMessage, 1, CHARINDEX('(reason: ', ErrorMessage, 1) + LEN('(reason: '), ''), ').  The step failed.', '')
									else replace(ErrorMessage, '.  The step failed.', '')
								end,
				@ErrorNumber = case when @SubSystemName = 'TSQL'
									then case when isnumeric(left(ErrorNumber, charindex(')', ErrorNumber, 1) - 1)) = 1
											then cast(left(ErrorNumber, charindex(')', ErrorNumber, 1) - 1) as int)
											else -1
										end
									else -1
								end
		from ErrorParse2
	end
end try
begin catch
	select @ErrorNumber = ERROR_NUMBER(),
			@ErrorMessage = ERROR_MESSAGE()
end catch
if exists (select * from msdb..sysjobs where name = @job_name)
	exec msdb..sp_delete_job @job_name = @job_name
GO
if OBJECT_ID('Infra.usp_GetTempFileName') is not null
	drop procedure Infra.usp_GetTempFileName
GO
create procedure Infra.usp_GetTempFileName
	@Extension varchar(10),
	@FileName varchar(1000) output
as
set @FileName = CAST(Management.fn_GetSettingValue('Management', 'Central Temp Folder') as varchar(1000))
					+ '\' + cast(NEWID() as varchar(36)) + '.' + @Extension
if @FileName is null
begin
	raiserror('Must define a Central Temp Folder', 16, 1)
	return -1
end
GO
if OBJECT_ID('Infra.usp_DeleteTempFile') is not null
	drop procedure Infra.usp_DeleteTempFile
GO
create procedure Infra.usp_DeleteTempFile
	@FullFilePath varchar(1000)
as
declare @Command varchar(1000)
if @FullFilePath like CAST(Management.fn_GetSettingValue('Management', 'Central Temp Folder') as varchar(1000)) + '%'
begin
	set @Command = 'del "' + @FullFilePath + '"'
	exec Infra.usp_RunCommandAsJob @Command,
								'CmdExec'
end
else
	raiserror('This procedure can only delete files from the Central temp folder', 16, 1)
GO
if OBJECT_ID('Infra.usp_RunPowershellScript') is not null
	drop procedure Infra.usp_RunPowershellScript
GO
create procedure Infra.usp_RunPowershellScript
	@ScriptName varchar(100),
	@Parameters varchar(1000),
	@ErrorMessage nvarchar(2000) = null output,
	@Output nvarchar(max) = null output
as
declare @ScriptFileName varchar(1000),
		@Command as varchar(4000)

select @ErrorMessage = null,
		@Output = null

begin try
	exec Infra.usp_GetTempFileName 'ps1',
									@ScriptFileName output
end try
begin catch
	set @ErrorMessage = ERROR_MESSAGE()
	return
end catch

set @Command = 'bcp "select PSC_Script from ' + DB_NAME() + '.Infra.PowershellScripts where PSC_Name = ''' + @ScriptName + '''"'
+ ' queryout "' + @ScriptFileName + '" -S ' + @@SERVERNAME + ' -T -w -t -r'

exec Infra.usp_RunCommandAsJob @Command,
								'CmdExec',
								default,
								@ErrorMessage output

if @ErrorMessage is null
begin
	set @Command = 'powershell.exe -f "' + @ScriptFileName + '" ' + @Parameters
	exec Infra.usp_RunCommandAsJob @Command,
									'CmdExec',
									default,
									@ErrorMessage output,
									@Output output
	exec Infra.usp_DeleteTempFile @ScriptFileName
end
GO
delete Infra.PowershellScripts
where PSC_Name = 'Script Job'
insert into Infra.PowershellScripts
values('Script Job',
'Param([string]$ServerName,
		[string]$JobName,
		[string]$FileName)
if (!(($ServerName) -and ($JobName) -and ($FileName))) {exit}

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
$srv = New-Object "Microsoft.SqlServer.Management.Smo.Server" $ServerName
if (Test-Path $FileName)
{
	del $FileName
}
[string]$JobScripts = ""

$srv.JobServer.Jobs | `
	Where {($_.Name -match $JobName)} | `
		foreach {$JobScripts = $JobScripts + "IF NOT EXISTS (SELECT * FROM msdb..sysjobs WHERE name = ''$($_.Name)'')
BEGIN
$($_.Script())
END
GO
"}

if ($JobScripts)
{
	out-file -FilePath $FileName -InputObject $JobScripts
}
if (Test-Path $FileName)
{
	Write-Host "Job scripted successfully"
}
else
{
	Write-Host "Job Not Found"
}

$srv.Close')
GO
if OBJECT_ID('Infra.usp_ScriptJob') is not null
	drop procedure Infra.usp_ScriptJob
GO
CREATE procedure Infra.usp_ScriptJob
	@JobName sysname,
	@Script nvarchar(max) output,
	@ErrorMessage nvarchar(2000) = null output
as
set nocount on
declare @JobFileName varchar(1000),
		@Parameters varchar(1000),
		@Output nvarchar(max),
		@SQL nvarchar(max)

set @Script = null

begin try
	exec Infra.usp_GetTempFileName 'sql',
									@JobFileName output
end try
begin catch
	set @ErrorMessage = ERROR_MESSAGE()
	return
end catch
--Selecting from sysjobs in order to avoid SQL injection
set @Parameters = '"' + @@SERVERNAME + '" "'
						+ (select name
							from msdb..sysjobs
							where name = @JobName) + '" "' + @JobFileName + '"'

exec Infra.usp_RunPowershellScript 'Script Job',
									@Parameters,
									@ErrorMessage output,
									@Output output

if @Output like '%Job scripted successfully%'
begin
	set @SQL = 'select @Script = BulkColumn from openrowset( BULK N''' + @JobFileName + ''', SINGLE_NCLOB) a'
	exec sp_executesql @SQL,
						N'@Script nvarchar(max) output',
						@Script = @Script output
	exec Infra.usp_DeleteTempFile @JobFileName
end
GO
