use db_cdba
GO
/*
This scripts sets and creates a folder on the Central server for temporary files
The files are very small. The folder is created under your default data folder.

You might want to skip this script, and instead set and create the folder in another location
	1. Create a folder wherever you want (if it's a cluster, make sure it's on a shared drive,
		or exists in the same location on all nodes).
	2. insert a record into the Settings table as so (change <Your location> with a real value):
		insert into Management.Settings
		values('Management', 'Central Temp Folder', '<Your location>')
*/
if Management.fn_GetSettingValue('Management', 'Central Temp Folder') is null
begin
	declare @DefaultData nvarchar(512),
			@CentralTempFolder varchar(1000),
			@Command varchar(1000),
			@ErrorMessage nvarchar(2000)
	exec master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',
										N'Software\Microsoft\MSSQLServer\MSSQLServer',
										N'DefaultData',
										@DefaultData OUTPUT
	if @DefaultData is null
		select @DefaultData = left(physical_name, len(physical_name) - charindex('\', reverse(physical_name), 1))
		from sys.master_files
		where database_id = 1
			and [file_id] = 1

	set @CentralTempFolder = @DefaultData + '\CentralTempFiles'
	set @Command = 'md "' + @CentralTempFolder + '"'

	exec Infra.usp_RunCommandAsJob @Command,
									'CmdExec',
									default,
									@ErrorMessage output

	if @ErrorMessage is not null and @ErrorMessage not like '%already exists%'
	begin
		set @ErrorMessage = 'Error creating Central temp folder: ' + @ErrorMessage
		raiserror(@ErrorMessage, 16, 1)
	end
	else
		insert into Management.Settings
		values('Management', 'Central Temp Folder', @CentralTempFolder)
end