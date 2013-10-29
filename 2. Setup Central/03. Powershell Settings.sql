/*
This script sets the Powershell execution policy on the Central server to UnRestricted.
You can set it to anything else that would allow running scripts locally instead.
*/
declare @ErrorMessage nvarchar(2000)

exec Infra.usp_RunCommandAsJob 'powershell.exe "Set-ExecutionPolicy UnRestricted"',
								'CmdExec',
								default,
								@ErrorMessage output

if @ErrorMessage is not null
begin
	set @ErrorMessage = 'Error setting Powershell execution policy'
	raiserror(@ErrorMessage, 16, 1)
end