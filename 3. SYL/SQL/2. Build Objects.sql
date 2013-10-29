/*
This script creates all of the database objects SYL needs in order to run.
*/
use db_cdba
GO
IF schema_id('SYL') IS NULL
	EXEC('CREATE SCHEMA SYL')
GO
if OBJECT_ID('SYL.SqlLogins') is null
	create table SYL.SqlLogins
		(SLG_ID int NOT NULL identity(1, 1) CONSTRAINT PK_SqlLogins PRIMARY KEY CLUSTERED,
		SLG_Login nvarchar(255) NOT NULL,
		SLG_Password nvarchar(2000) NOT NULL,
		SLG_IsDefault bit NOT NULL)
GO
if OBJECT_ID('SYL.Runs') is null
begin
	create table SYL.Runs
		([RUN_ID] [int] NOT NULL IDENTITY(1,1) CONSTRAINT PK_Runs PRIMARY KEY CLUSTERED,
		[RUN_StartDate] [datetime] NOT NULL CONSTRAINT DF_Runs_RUN_StartDate  DEFAULT (getdate()),
		[RUN_ServerList] [varchar](max) NOT NULL,
		[RUN_Database] [nvarchar](255) NOT NULL,
		[RUN_Command] [nvarchar](max) NOT NULL,
		[RUN_ExpectsResults] [bit] NOT NULL,
		[RUN_EndDatetime] [datetime] NULL,
		[RUN_Identifier] [int] NULL,
		[RUN_NumberOfErrors] [int] NULL,
		[RUN_ErrorMessage] [varchar](max) NULL)
	create index IX_Runs_RUN_Identifier on SYL.Runs(RUN_Identifier)
end
GO
if OBJECT_ID('SYL.ServerRunResult') is null
begin
	create table SYL.ServerRunResult
		(SRR_ID int not null identity(1, 1) constraint PK_ServerRunResult primary key clustered,
		SRR_RUN_ID int not null,
		SRR_ServerName nvarchar(255) not null,
		SRR_StartDate datetime not null default(getdate()),
		SRR_EndDate datetime null,
		SRR_RecordsAffected int null,
		SRR_ErrorMessage varchar(max) null)
	create index IX_ServerRunResult_SRR_RUN_ID on SYL.ServerRunResult(SRR_RUN_ID)
end
GO
if OBJECT_ID('SYL.trg_SqlLogins') is not null
	drop trigger SYL.trg_SqlLogins
GO
create trigger SYL.trg_SqlLogins on SYL.SqlLogins
	for insert,update
as
set nocount on
if (select count(*) from SYL.SqlLogins where SLG_IsDefault = 1) > 1
begin
	rollback
	raiserror('Default logins are very much Like immortals. There can be only one.', 16, 1)
end
GO
if OBJECT_ID('SYL.usp_StartRun') is not null
	drop procedure SYL.usp_StartRun
GO
create procedure SYL.usp_StartRun
	@ServerList varchar(max),
	@Database nvarchar(255),
	@Command nvarchar(max),
	@ExpectsResults bit,
	@Identifier int
as
set nocount on

insert into SYL.Runs(RUN_ServerList, RUN_Database, RUN_Command, RUN_ExpectsResults, RUN_Identifier)
select @ServerList, @Database , @Command, @ExpectsResults, @Identifier

select scope_identity() RUN_ID
GO
if OBJECT_ID('SYL.usp_EndRun') is not null
	drop procedure SYL.usp_EndRun
GO
create procedure SYL.usp_EndRun
	@RUN_ID int,
	@NumberOfErrors int,
	@ErrorMessage varchar(max) = null
as
set nocount on

update SYL.Runs
set RUN_EndDatetime = getdate(),
	RUN_NumberOfErrors = @NumberOfErrors,
	RUN_ErrorMessage = @ErrorMessage
where RUN_ID = @RUN_ID
GO
if OBJECT_ID('SYL.usp_StartServerRun') is not null
	drop procedure SYL.usp_StartServerRun
GO
create procedure SYL.usp_StartServerRun
	@RUN_ID int,
	@ServerName nvarchar(255)
as
set nocount on

insert into SYL.ServerRunResult(SRR_RUN_ID, SRR_ServerName)
select @RUN_ID, @ServerName

select scope_identity() SRR_ID
GO
if OBJECT_ID('SYL.usp_EndServerRun') is not null
	drop procedure SYL.usp_EndServerRun
GO
create procedure SYL.usp_EndServerRun
	@SRR_ID int,
	@RecordsAffected int,
	@ErrorMessage varchar(max)
as
set nocount on

update SYL.ServerRunResult
set SRR_EndDate = getdate(),
	SRR_RecordsAffected = @RecordsAffected,
	SRR_ErrorMessage = @ErrorMessage
WHERE SRR_ID = @SRR_ID
GO
if OBJECT_ID('SYL.usp_GetServersList') is not null
	drop procedure SYL.usp_GetServersList
GO
create procedure SYL.usp_GetServersList
	@ServerList nvarchar(max)
as
select DBI_Name ServerName, DBI_IsTrusted IsWindowsAuthentication
from Infra.fn_SplitString(@ServerList, ',')
	inner join Management.DatabaseInstances with (nolock) on DBI_Name = Val
GO
if OBJECT_ID('SYL.usp_RetrieveLoginDetails') is not null
	drop procedure SYL.usp_RetrieveLoginDetails
GO
create procedure SYL.usp_RetrieveLoginDetails
	@SqlLogin nvarchar(255) = ''
as
select top 1 SLG_Login SqlLogin, SLG_Password SqlPassword
from SYL.SqlLogins with (nolock)
where SLG_Login = @SqlLogin or @SqlLogin = ''
order by SLG_ID
GO
if OBJECT_ID('Infra.usp_RunOnAllServers') is not null
	drop procedure Infra.usp_RunOnAllServers
GO
create procedure Infra.usp_RunOnAllServers
	@Command nvarchar(max),
	@Database nvarchar(256) = 'master',
	@IsResultExpected bit = 1,
	@LogToDB bit = 1,
	@SqlLogin nvarchar(128) = null,
	@SqlPassword nvarchar(128) = null,
	@OutputTable nvarchar(257) = null,
	@Identifier int = 0
as
declare @ServerList nvarchar(max)
set @ServerList = stuff((select ',' + DBI_Name
						from Management.DatabaseInstances
						where DBI_IsActive = 1), 1, 1, '')

if @ServerList is not null
	exec SYL.usp_RunCommand @ServerList,
							@Database,
							@Command,
							@IsResultExpected,
							@LogToDB,
							@SqlLogin,
							@SqlPassword,
							@OutputTable,
							@Identifier