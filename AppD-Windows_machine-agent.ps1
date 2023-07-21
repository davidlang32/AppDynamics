#--------------------------------------------------------------------------------------------------------------
#  APM Agent variables and paths
#--------------------------------------------------------------------------------------------------------------
    $BASEInstallDir = "C:\Temp\AppD-Windows_machine-agent"
    $uniquehostid = $env:COMPUTERNAME
    $AppDMachineAgentFileBaseName = (Get-ChildItem -Path $BASEInstallDir\machine-agent -Recurse -Filter "machineagent*").BaseName
    $AppDMachineAgentFile = (Get-ChildItem -Path $BASEInstallDir\machine-agent -Recurse -Filter "machineagent*").Name
    $AppDInstallDestination = 'C:\AppDynamics'
    $MachineAgentSimDir = $AppDInstallDestination'\machine-agent'

#--------------------------------------------------------------------------------------------------------------
#  Installing the AppDynamics Machine Agent
#	* Check if the symbolic link path exists
#		- if yes, uninstall the machine agent and delete it the directory
#		- continue to install it - this will ensure we only have 1 agent on the box
#--------------------------------------------------------------------------------------------------------------
    if(!(Test-Path -Path $AppDInstallDestination\$AppDMachineAgentFileBaseName)) {
        if (Test-Path -Path $MachineAgentSimDir) {
            Stop-Service -Name "AppDynamics Machine Agent"
            cmd /c cscript $MachineAgentSimDir\UninstallService.vbs
            cmd /c "rmdir $MachineAgentSimDir"
            }
    	Expand-Archive -LiteralPath $MachineAgentSimDir\$AppDMachineAgentFile -DestinationPath $AppDInstallDestination\$AppDMachineAgentFileBaseName
    	New-Item -ItemType SymbolicLink -Path $MachineAgentSimDir -Target $AppDInstallDestination\$AppDMachineAgentFileBaseName
    	(Get-Content $MachineAgentSimDir\conf\controller-info.xml -Raw) -replace '%uniquehostid%', $uniquehostid | Set-Content $MachineAgentSimDir\conf\controller-info.xml
    	cmd /c cscript $MachineAgentSimDir\InstallService.vbs
    }
}
#-------------------------------------------------------------------------------------
# Restart and clean up
#-------------------------------------------------------------------------------------
#Remove-Item -Path $BASEInstallDir -Recurse -Force
#Clear-RecycleBin -Force