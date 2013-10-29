use db_cdba
GO
IF schema_id('SyncManager') IS NULL
	exec('CREATE SCHEMA SyncManager')
GO
if Management.fn_GetSettingValue('SyncManager', 'Local Database Name') is null
	insert into Management.Settings
	values('SyncManager', 'Local Database Name', 'db_dba')
GO
if Management.fn_GetSettingValue('SyncManager', 'Local Job Prefix') is null
	insert into Management.Settings
	values('SyncManager', 'Local Job Prefix', 'DBALocal_')
GO	
if OBJECT_ID('SyncManager.SchemaChangesHistory') is null
	CREATE TABLE SyncManager.SchemaChangesHistory(
		SCH_ID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_SchemaChangesHistory PRIMARY KEY CLUSTERED,
		SCH_EventType nvarchar(500) NOT NULL,
		SCH_PostTime sysname NOT NULL,
		SCH_LoginName sysname NOT NULL,
		SCH_DatabaseName sysname NOT NULL,
		SCH_SchemaName sysname NULL,
		SCH_ObjectName sysname NULL,
		SCH_ObjectType sysname NULL,
		SCH_CommandText nvarchar(max) NOT NULL
	)
GO
if OBJECT_ID('SyncManager.SchemaChangesDistribution') is null
	CREATE TABLE SyncManager.SchemaChangesDistribution(
		SCD_DBI_Name nvarchar(128) NOT NULL CONSTRAINT PK_SchemaChangesDistribution PRIMARY KEY CLUSTERED,
		SCD_Last_SCH_ID int NULL,
		SCD_LastUpdateDate datetime NULL,
		SCD_LastErrorMessage nvarchar(2000) NULL
	)
GO
if OBJECT_ID('SyncManager.TablesToSyncExceptions') is null
	CREATE TABLE SyncManager.TablesToSyncExceptions(
		TSE_ID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_TablesToSyncExceptions PRIMARY KEY CLUSTERED,
		TSE_TTC_ID int NOT NULL,
		TSE_Priority tinyint NOT NULL,
		TSE_ENV_ID tinyint NULL,
		TSE_ServerList nvarchar(max) NULL,
		TSE_PostSyncScript nvarchar(max) NULL,
		TSE_IsActive bit NOT NULL
	)
GO
if OBJECT_ID('SyncManager.TablesToSync') is null
begin
	CREATE TABLE SyncManager.TablesToSync(
		TTC_ID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_TablesToSync PRIMARY KEY CLUSTERED,
		TTC_SchemaName sysname NOT NULL,
		TTC_TableName sysname NOT NULL,
		TTC_IsActive bit NULL
	)
	CREATE UNIQUE INDEX IX_TablesToSync_TTC_SchemaName#TTC_TableName on SyncManager.TablesToSync(TTC_SchemaName, TTC_TableName)
end
GO
if OBJECT_ID('SyncManager.TableDataDistribution') is null
	CREATE TABLE SyncManager.TableDataDistribution(
		TDD_SchemaName sysname NOT NULL,
		TDD_TableName sysname NOT NULL,
		TDD_ServerName sysname NOT NULL,
		TDD_LastUpdate datetime NULL,
		TDD_LastErrorMessage nvarchar(2000) NULL,
	 CONSTRAINT PK_TableDataDistribution PRIMARY KEY CLUSTERED 
		(TDD_SchemaName, TDD_TableName, TDD_ServerName)
	)
GO
if OBJECT_ID('SyncManager.usp_DistributeCommand') is not null
	drop procedure SyncManager.usp_DistributeCommand
GO
CREATE procedure SyncManager.usp_DistributeCommand
	@ServerName nvarchar(128),
	@Database sysname,
	@CommandText nvarchar(max),
	@ErrorMessage nvarchar(2000) output
as
declare @Identifier int = 987656

set @ErrorMessage = null

begin try
	exec SYL.usp_RunCommand
			   @ServerList = @ServerName
			  ,@Database = @Database
			  ,@Command = @CommandText
			  ,@IsResultExpected = 0
			  ,@LogToDB = 1
			  ,@SqlLogin = null
			  ,@SqlPassword = null
			  ,@OutputTable = null
			  ,@Identifier = @Identifier

	select top 1 @ErrorMessage = SRR_ErrorMessage
	from SYL.Runs
		inner join SYL.ServerRunResult on SRR_RUN_ID = RUN_ID
	where RUN_Identifier = @Identifier
		and SRR_ServerName = @ServerName
	order by SRR_ID desc
end try
begin catch
	set @ErrorMessage = ERROR_MESSAGE()
end catch

set @ErrorMessage = case when @ErrorMessage like 'The server principal % already exists%'
								or @ErrorMessage like 'User, group, or role % already exists%'
								or @ErrorMessage like 'The credential with name % already exists%'
								or @ErrorMessage like 'There is already an %'
								or @ErrorMessage like 'Column already has a %'
								or @ErrorMessage like 'Table % already has a primary key%'
						then null
						else @ErrorMessage
					end
GO
if OBJECT_ID('SyncManager.usp_SyncSchema') is not null
	drop procedure SyncManager.usp_SyncSchema
GO
CREATE procedure SyncManager.usp_SyncSchema
as
set nocount on
declare @LocalDBADatabaseName nvarchar(128),
		@ServerName sysname,
		@Last_SCH_ID int,
		@SCH_ID int,
		@CommandText nvarchar(max),
		@ServerCycleNumber int,
		@EventType sysname,
		@ObjectName sysname,
		@ErrorMessage nvarchar(2000),
		@PreviousServerName sysname,
		@SQL nvarchar(max)

set @LocalDBADatabaseName = CAST(Management.fn_GetSettingValue('SyncManager', 'Local Database Name') as nvarchar(128))

declare crs cursor static
for
	select DBI_Name, SCD_Last_SCH_ID, SCH_ID, SCH_CommandText,
			row_number() over (partition by DBI_Name order by SCH_ID) ServerCycleNumber,
			SCH_EventType, SCH_ObjectName
	from Management.DatabaseInstances
		left join SyncManager.SchemaChangesDistribution on DBI_Name = SCD_DBI_Name
		inner join SyncManager.SchemaChangesHistory on SCD_Last_SCH_ID < SCH_ID
													or SCD_Last_SCH_ID is null
	where DBI_Name <> @@SERVERNAME
		and DBI_IsActive = 1
	order by DBI_Name, SCH_ID
open crs

fetch next from crs into @ServerName, @Last_SCH_ID, @SCH_ID, @CommandText, @ServerCycleNumber, @EventType, @ObjectName
while @@fetch_status = 0
begin
	if @PreviousServerName is null
		set @PreviousServerName = @ServerName

	merge SyncManager.SchemaChangesDistribution D
	using (select @ServerName ServerName) S
			on D.SCD_DBI_Name = ServerName
		when matched then update
						set SCD_LastUpdateDate = getdate()
		when not matched by target then insert(SCD_DBI_Name, SCD_LastUpdateDate)
						values(ServerName, getdate());


	if @Last_SCH_ID is null and @ServerCycleNumber = 1
	begin
		set @SQL = 'if db_id(''' + @LocalDBADatabaseName+ ''') is null
						create database ' + QUOTENAME(@LocalDBADatabaseName) + '
					alter database ' + quotename(@LocalDBADatabaseName) + ' set trustworthy on

					declare @Name nvarchar(128)
					select @Name = name
					from sys.server_principals
					where principal_id = 1
					exec(''alter authorization on database::' + QUOTENAME(@LocalDBADatabaseName) + ' to '' + @Name)'
		exec SyncManager.usp_DistributeCommand @ServerName = @ServerName,
												@Database = 'master',
												@CommandText = @SQL,
												@ErrorMessage = @ErrorMessage output

		update SyncManager.SchemaChangesDistribution
		set SCD_Last_SCH_ID = case when @ErrorMessage is null then 0 else SCD_Last_SCH_ID end,
			SCD_LastErrorMessage = @ErrorMessage
		where SCD_DBI_Name = @ServerName
	end
	
	if @ErrorMessage is null or @PreviousServerName <> @ServerName
	begin
		if @EventType = 'CREATE_TABLE' and @ObjectName = 'NumberHelper'
		begin
			set @CommandText = 'if object_id(''INFRA.NumberHelper'') is not null drop table INFRA.NumberHelper' + CHAR(13)+CHAR(10)
								+ @CommandText
			exec SyncManager.usp_DistributeCommand @ServerName = @ServerName,
													@Database = @LocalDBADatabaseName,
													@CommandText = @CommandText,
													@ErrorMessage = @ErrorMessage output		
			
			if @ErrorMessage is null
			begin
				set @SQL = 'set nocount on
				if not exists (select * from ' + quotename(@LocalDBADatabaseName) + '.Infra.NumberHelper)
				begin
					exec(''alter table ' + quotename(@LocalDBADatabaseName) + '.Infra.NumberHelper add a bit'')
					exec(''insert into ' + quotename(@LocalDBADatabaseName) + '.Infra.NumberHelper
					select top 100000 null
					from master..syscomments a
						cross join master..syscomments b'')
					exec(''alter table ' + quotename(@LocalDBADatabaseName) + '.Infra.NumberHelper drop column a'')
				end'

				exec SyncManager.usp_DistributeCommand @ServerName = @ServerName,
														@Database = @LocalDBADatabaseName,
														@CommandText = @SQL,
														@ErrorMessage = @ErrorMessage output
			end
			update SyncManager.SchemaChangesDistribution
			set SCD_Last_SCH_ID = case when @ErrorMessage is null then @SCH_ID else SCD_Last_SCH_ID end,
				SCD_LastErrorMessage = @ErrorMessage
			where SCD_DBI_Name = @ServerName
		end
		else
		begin
			exec SyncManager.usp_DistributeCommand @ServerName = @ServerName,
														@Database = @LocalDBADatabaseName,
														@CommandText = @CommandText,
														@ErrorMessage = @ErrorMessage output		

			update SyncManager.SchemaChangesDistribution
			set SCD_Last_SCH_ID = case when @ErrorMessage is null then @SCH_ID else SCD_Last_SCH_ID end,
				SCD_LastErrorMessage = @ErrorMessage
			where SCD_DBI_Name = @ServerName
		end
	end
	
	set @PreviousServerName = @ServerName

	fetch next from crs into @ServerName, @Last_SCH_ID, @SCH_ID, @CommandText, @ServerCycleNumber, @EventType, @ObjectName
end
close crs
deallocate crs
GO
if OBJECT_ID('SyncManager.usp_SyncJobs') is not null
	drop procedure SyncManager.usp_SyncJobs
GO
CREATE procedure SyncManager.usp_SyncJobs
as
set nocount on

declare @JobPrefix nvarchar(128),
		@SQL nvarchar(max),
		@JobName sysname,
		@Servers nvarchar(max),
		@Script nvarchar(max),
		@saLogin sysname
if OBJECT_ID('tempdb..#Jobs') is not null
	drop table #Jobs

create table #Jobs(srv sysname,
					name sysname,
					[enabled] bit)
select @JobPrefix = CAST(Management.fn_GetSettingValue('SyncManager', 'Local Job Prefix') as nvarchar(128))

set @SQL =
'select @@SERVERNAME srv, name, enabled
from dbo.sysjobs with (nolock)
where name like ''' + replace(@JobPrefix, '_', '[_]') + '%'''

exec Infra.usp_RunOnAllServers @Command = @SQL,
								@Database = 'msdb',
								@OutputTable = '#Jobs'

if OBJECT_ID('tempdb..#MissingJobs') is not null
	drop table #MissingJobs

select @saLogin = name
from sys.server_principals
where principal_id = 1

;with JobServers as
	(select name JobName, DBI_Name ServerName
	from #Jobs
		cross join Management.DatabaseInstances
	where srv = @@SERVERNAME
		and [enabled] = 1
		and DBI_IsActive = 1
	)
	, MissingJobs as
	(select *
	from JobServers
	where not exists (select *
						from #Jobs
						where srv = ServerName
							and name = JobName)
	)
select JobName,
	stuff((select ',' + ServerName
			from MissingJobs J1
			where J.JobName = J1.JobName
			for xml path('')), 1, 1, '') Srvs
into #MissingJobs
from (select distinct JobName
		from MissingJobs) J

declare crs cursor static for
select JobName, Srvs
from #MissingJobs

open crs
fetch next from crs into @JobName, @Servers
while @@fetch_status = 0
begin
	print @JobName + ' - ' + @Servers
	exec Infra.usp_ScriptJob @JobName = @JobName,
							@Script = @Script output

	set @Script = 'declare @name sysname
					select @name = name
					from sys.server_principals
					where principal_id = 1' + CHAR(13)+CHAR(10)
				+ replace(replace(replace(@Script, char(13)+char(10)+'GO'+char(13)+char(10), char(13)+char(10))
									, ', ' + CHAR(13)+char(10)+CHAR(9)+CHAR(9) + '@schedule_uid=', ' --')
									, '@owner_login_name=N''' + @saLogin + '''', '@owner_login_name=@name')

	exec SYL.usp_RunCommand @ServerList = @Servers,
							@Database = 'msdb',
							@Command = @Script,
							@IsResultExpected = 0,
							@LogToDB = 1,
							@SqlLogin = null,
							@SqlPassword = null,
							@OutputTable = '',
							@Identifier = 0

	fetch next from crs into @JobName, @Servers
end
close crs
deallocate crs
GO
if OBJECT_ID('SyncManager.usp_Report_FailedTableDataSync') is not null
	drop procedure SyncManager.usp_Report_FailedTableDataSync
GO
CREATE procedure SyncManager.usp_Report_FailedTableDataSync
as
select TDD_ServerName ServerName,
	TDD_SchemaName SchemaName, TDD_TableName TableName,
	TDD_LastUpdate LastUpdate, TDD_LastErrorMessage LastErrorMessage
from SyncManager.TableDataDistribution
	inner join Management.DatabaseInstances on DBI_Name = TDD_ServerName
where TDD_LastErrorMessage is not null
	and DBI_IsActive = 1
GO
if OBJECT_ID('SyncManager.usp_Report_FailedSchemaChangesDistribution') is not null
	drop procedure SyncManager.usp_Report_FailedSchemaChangesDistribution
GO
CREATE procedure SyncManager.usp_Report_FailedSchemaChangesDistribution
as
select DBI_Name ServerName, HistoryID, CommandType,
	ObjectName, SCD_LastUpdateDate LastUpdateDate,
	SCD_LastErrorMessage LastErrorMessage
from Management.DatabaseInstances
	left join SyncManager.SchemaChangesDistribution on DBI_Name = SCD_DBI_Name
	outer apply (select top 1 isnull(SCH_SchemaName + '.', '') + isnull(SCH_ObjectName, '') ObjectName,
							SCH_ID HistoryID, SCH_EventType CommandType
				from SyncManager.SchemaChangesHistory
				where SCH_ID > SCD_Last_SCH_ID
				order by SCH_ID) H
where DBI_IsActive = 1
	and DBI_Name <> @@SERVERNAME
	and (SCD_LastErrorMessage is not null
			or SCD_Last_SCH_ID is null
			or SCD_Last_SCH_ID < (select max(SCH_ID)
									from SyncManager.SchemaChangesHistory)
		)
GO
if OBJECT_ID('SyncManager.fn_GetTablesToSyncExceptions') is not null
	drop function SyncManager.fn_GetTablesToSyncExceptions
GO
CREATE function SyncManager.fn_GetTablesToSyncExceptions
	(@TTC_ID int,
	@ServerName nvarchar(128))
returns table
as
	return (select top 1 TSE_ID
				from SyncManager.TablesToSyncExceptions
					inner join Management.DatabaseInstances on (',' + TSE_ServerList + ',' like '%,' + DBI_Name + ',%'
																or TSE_ServerList is null)
													
				where TSE_TTC_ID = @TTC_ID
					and DBI_Name = @ServerName
				order by TSE_Priority)
GO
if OBJECT_ID('SyncManager.usp_SyncData') is not null
	drop procedure SyncManager.usp_SyncData
GO
CREATE procedure SyncManager.usp_SyncData
as
set nocount on
declare @LocalDBADatabaseName nvarchar(128),
		@SchemaName sysname,
		@TableName sysname,
		@PostSyncScript nvarchar(max),
		@ServerList nvarchar(max),
		@SQL nvarchar(max),
		@TableXML xml,
		@Identifier int = 12653

set @LocalDBADatabaseName = CAST(Management.fn_GetSettingValue('SyncManager', 'Local Database Name') as nvarchar(128))

if OBJECT_ID('tempdb..#Tabs') is not null
	drop table #Tabs

select TTC_ID, DBI_Name, TSE_ID
into #Tabs
from SyncManager.TablesToSync
	cross join Management.DatabaseInstances
	outer apply SyncManager.fn_GetTablesToSyncExceptions(TTC_ID, DBI_Name)
where TTC_IsActive = 1
	and DBI_Name <> @@SERVERNAME
		and DBI_IsActive = 1

declare crs cursor static for
	select TTC_SchemaName, TTC_TableName, TSE_PostSyncScript,
		stuff((select ',' + DBI_Name
				from #Tabs t1
				where t.TTC_ID = t1.TTC_ID
					and (t.TSE_ID = t1.TSE_ID
						or (t.TSE_ID is null
							and t1.TSE_ID is null))
				order by DBI_Name
				for xml path('')), 1, 1, '') ServerList
	from (select distinct TTC_ID, TSE_ID from #Tabs) t
		inner join SyncManager.TablesToSync t2 on t.TTC_ID = t2.TTC_ID
		left join SyncManager.TablesToSyncExceptions t3 on t.TSE_ID = t3.TSE_ID
	order by TTC_SchemaName, TTC_TableName

open crs

fetch next from crs into @SchemaName, @TableName, @PostSyncScript, @ServerList
while @@fetch_status = 0
begin
	set @SQL = 
	'select @TableXML = (select @SchemaName SchemaName, @TableName TableName,
		(select *
		from ' + quotename(@LocalDBADatabaseName) + '.' + quotename(@SchemaName) + '.' + quotename(@TableName) + ' Row with (nolock)
		for xml auto, type) Data
	from (select 1 a) Tab
	for xml auto, elements, type)'

	exec sp_executesql @SQL,
						N'@SchemaName sysname,
							@TableName sysname,
							@TableXML xml output',
						@SchemaName = @SchemaName,
						@TableName = @TableName,
						@TableXML = @TableXML output

	select @SQL = 'use ' + quotename(@LocalDBADatabaseName) + '
					declare @SQL nvarchar(max),
							@TableXML xml,
							@SchameName sysname,
							@TableName sysname,
							@TableData xml,
							@HasIdentity bit
						set @TableXML = ''' + replace(CAST(@TableXML as nvarchar(max)), '''', '''''') + '''
					select @SchameName = @TableXML.value(''(Tab/SchemaName)[1]'', ''sysname''),
							@TableName = @TableXML.value(''(Tab/TableName)[1]'', ''sysname''),
							@TableData = @TableXML.query(''Tab/Data'')

					declare @KeyColumns table (Name sysname)
					declare @TableColumns table (Name sysname,
												ColType nvarchar(100),
												IsIdentity bit)


					insert into @KeyColumns
					select c.name
					from sys.indexes i
						inner join sys.index_columns ic on i.object_id = ic.object_id
															and i.index_id = ic.index_id
						inner join sys.columns c on ic.object_id = c.object_id
													and ic.column_id = c.column_id
					where i.object_id = object_id(@SchameName + ''.'' + @TableName)
						and i.type = 1

					insert into @TableColumns
					select name, 
							case when TYPE_NAME(system_type_id) in (''char'', ''nchar'', ''varchar'', ''nvarchar'')
										then TYPE_NAME(system_type_id) + ''('' + case max_length
														when -1 then ''max''
														else CAST(max_length as varchar(10))
													end + '')''
									when TYPE_NAME(system_type_id) = ''sql_variant''
										then ''nvarchar(4000)''
									else TYPE_NAME(system_type_id)
								end, is_identity
					from sys.columns
					where object_id = object_id(@SchameName + ''.'' + @TableName)

					select @HasIdentity = cast(max(cast(IsIdentity as int)) as bit)
					from @TableColumns

					set @SQL = ''select ''
					+ STUFF((select '',b.value(''''@'' + Name + '''''', ''''''
										+ ColType + '''''') '' + QUOTENAME(Name)
								from @TableColumns
								for xml path('''')), 1, 1, '''') + ''
					into #TableData
					from @TableData.nodes(''''Data/Row'''') a(b)

					delete '' + @SchameName + ''.'' + @TableName + ''
					from '' + @SchameName + ''.'' + @TableName + '' D
					where not exists (select *
										from #TableData S
										where ''
										+ stuff((select ''and (S.'' + QUOTENAME(Name) + '' = D.'' + QUOTENAME(Name)
																+ '' or (S.'' + QUOTENAME(Name) + '' is null''
																+ '' and D.'' + QUOTENAME(Name) + '' is null))''
													from @KeyColumns
													for xml path('''')), 1, 4, '''') + '')

					'' + isnull(''update D
					set '' + stuff((select '','' + QUOTENAME(Name) + '' = S.'' + QUOTENAME(Name)
									from @TableColumns t
									where not exists (select *
														from @KeyColumns k
														where t.Name = k.Name)
									for xml path('''')), 1, 1, '''') + ''
					from '' + @SchameName + ''.'' + @TableName + '' D
						inner join #TableData S on ''
								+ stuff((select ''and (S.'' + QUOTENAME(Name) + '' = D.'' + QUOTENAME(Name)
											+ '' or (S.'' + QUOTENAME(Name) + '' is null''
											+ '' and D.'' + QUOTENAME(Name) + '' is null))''
								from @KeyColumns
								for xml path('''')), 1, 4, ''''), '''')

					+ case when @HasIdentity = 1 then char(13)+char(10) + ''set identity_insert '' + @SchameName + ''.'' + @TableName + '' on'' + char(13)+char(10) else '''' end
					+ ''insert into '' + @SchameName + ''.'' + @TableName + ''(''
						+ stuff((select '','' + Name
									from @TableColumns
									for xml path('''')), 1, 1, '''') + '')
					select *
					from #TableData S
					where not exists (select *
										from '' + @SchameName + ''.'' + @TableName + '' D
										where ''
										+ stuff((select ''and (S.'' + QUOTENAME(Name) + '' = D.'' + QUOTENAME(Name)
																+ '' or (S.'' + QUOTENAME(Name) + '' is null''
																+ '' and D.'' + QUOTENAME(Name) + '' is null))''
													from @KeyColumns
													for xml path('''')), 1, 4, '''') + '')''
					+ case when @HasIdentity = 1 then char(13)+char(10) + ''set identity_insert '' + @SchameName + ''.'' + @TableName + '' off'' + char(13)+char(10) else '''' end

					exec sp_executesql @SQL,
										N''@TableData xml'',
										@TableData = @TableData'
					+ ISNULL(char(13)+char(10) + @PostSyncScript, '')

	exec SYL.usp_RunCommand
		@ServerList = @ServerList
		,@Database = @LocalDBADatabaseName
		,@Command = @SQL
		,@IsResultExpected = 0
		,@LogToDB = 1
		,@SqlLogin = null
		,@SqlPassword = null
		,@OutputTable = null
		,@Identifier = @Identifier

	;with Results as
		(select SRR_ServerName, SRR_ErrorMessage
			from SYL.ServerRunResult
			where SRR_RUN_ID = (select top 1 RUN_ID
								from SYL.Runs
								where RUN_Identifier = @Identifier
								order by RUN_ID desc))
	merge SyncManager.TableDataDistribution
	using Results
		on TDD_SchemaName = @SchemaName
		and TDD_TableName = @TableName
		and TDD_ServerName = SRR_ServerName
	when matched then update
						set TDD_LastUpdate = getdate(),
							TDD_LastErrorMessage = SRR_ErrorMessage
	when not matched by target then insert (TDD_SchemaName, TDD_TableName, TDD_ServerName, TDD_LastUpdate, TDD_LastErrorMessage)
										values(@SchemaName, @TableName, SRR_ServerName, getdate(), SRR_ErrorMessage);

	fetch next from crs into @SchemaName, @TableName, @PostSyncScript, @ServerList
end
close crs
deallocate crs
GO
