clear
#----------------------------------------------------------------------------------------------
# Application Team Settings
#----------------------------------------------------------------------------------------------
	$uniquehostid = $env:COMPUTERNAME
	$applicationname="AppDynamics"
	$tiername="APP"
	$nodename=$uniquehostid
	
#--------------------------------------------------------------------------------------------------------------
# SaaS Controller Settings for Windows Machine Agents
#--------------------------------------------------------------------------------------------------------------
    $controllerhost = 'deltekprodca.saas.appdynamics.com'
    $controllerport = '443'
    $controllerssl = 'true'
    $orchestration = 'false'
    $accountaccesskey = 'k7msot9e1vms'
    $accountname = 'deltekprodca'
    $sim = 'true'
	$issapmachine = ''
    $machinepath = ''
    $dotnetcompatmode = 'false'

#--------------------------------------------------------------------------------------------------------------
#  Server install paths and dynamic recognician of AppDynamics Windows Machine Agent name
#--------------------------------------------------------------------------------------------------------------
    $BASEInstallDir = "C:\Temp"
    $AppDMachineAgentFileBaseName = (Get-ChildItem -Path $BASEInstallDir -Recurse -Filter "machineagent*").BaseName
    $AppDMachineAgentFile = (Get-ChildItem -Path $BASEInstallDir -Recurse -Filter "machineagent*").Name
    $AppDInstallDestination = 'C:\AppDynamics'
    $MachineAgentSimDir = $AppDInstallDestination+"\machine-agent"

#--------------------------------------------------------------------------------------------------------------
#  Matching criteria for default values on controller-info.xml file
#--------------------------------------------------------------------------------------------------------------
	$controller_host_match="<controller-host></controller-host>"
	$controller_port_match="<controller-port></controller-port>"
	$controller_ssl_enabled_match="<controller-ssl-enabled>false</controller-ssl-enabled>"
	$enable_orchestration_match="<enable-orchestration>false</enable-orchestration>"
	$unique_host_id_match="<unique-host-id></unique-host-id>"
	$account_access_key_match="<account-access-key></account-access-key>"
	$account_name_match="<account-name></account-name>"
	$sim_enabled_match="<sim-enabled>false</sim-enabled>"
	$is_sap_machine_match="<is-sap-machine></is-sap-machine>"
	$machine_path_match="<machine-path></machine-path>"
	$dotnet_compatibility_mode_match="<dotnet-compatibility-mode>false</dotnet-compatibility-mode>"
	
#----------------------------------------------------------------------------------------------
# Modifying default values for custom values defined above
#----------------------------------------------------------------------------------------------
	$controllerhost='<controller-host>'+$controllerhost+'</controller-host>'
	$controllerport='<controller-port>'+$controllerport+'</controller-port>'
	$controllerssl='<controller-ssl-enabled>'+$controllerssl+'</controller-ssl-enabled>'
	$orchestration='<enable-orchestration>'+$orchestration+'</enable-orchestration>'
	$uniquehostid='<unique-host-id>'+$uniquehostid+'</unique-host-id>'
	$accountaccesskey='<account-access-key>'+$accountaccesskey+'</account-access-key>'
	$accountname='<account-name>'+$accountname+'</account-name>'
	$sim='<sim-enabled>'+$sim+'</sim-enabled>'
	$issapmachine='<is-sap-machine>'+$issapmachine+'</is-sap-machine>'
	$machinepath='<machine-path>'+$machinepath+'</machine-path>'
	$dotnetcompatmode='<dotnet-compatibility-mode>'+$dotnetcompatmode+'</dotnet-compatibility-mode>'
	$applicationname='<application-name>'+$applicationname+'</application-name>'
	$tiername='<tier-name>'+$tiername+'<tier-name>'
	$nodename='<node-name>'+$nodename+'<node-name>'

#--------------------------------------------------------------------------------------------------------------
#  Announce variables
#--------------------------------------------------------------------------------------------------------------
    Write-Host "AppDMachineAgentFileBaseName: $AppDMachineAgentFileBaseName"
    Write-Host "AppDMachineAgentFile: $AppDMachineAgentFile"
    Write-Host "AppDInstallDestination: $AppDInstallDestination"
    Write-Host "MachineAgentSimDir: $MachineAgentSimDir"
	
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
	Expand-Archive -LiteralPath $BASEInstallDir\$AppDMachineAgentFile -DestinationPath $AppDInstallDestination\$AppDMachineAgentFileBaseName
	New-Item -ItemType SymbolicLink -Path $MachineAgentSimDir -Target $AppDInstallDestination\$AppDMachineAgentFileBaseName
	#--------------------------------------------------------------------------------------------------------------
	#  Configure the AppDynamics Machine Agent to report into the correct SaaS controller and properly identify the agent
	#--------------------------------------------------------------------------------------------------------------
		(Get-Content $MachineAgentSimDir\conf\controller-info.xml -Raw) -replace $controller_host_match, $controllerhost | Set-Content $MachineAgentSimDir\conf\controller-info.xml
		(Get-Content $MachineAgentSimDir\conf\controller-info.xml -Raw) -replace $controller_port_match, $controllerport | Set-Content $MachineAgentSimDir\conf\controller-info.xml
		(Get-Content $MachineAgentSimDir\conf\controller-info.xml -Raw) -replace $controller_ssl_enabled_match, $controllerssl | Set-Content $MachineAgentSimDir\conf\controller-info.xml
		(Get-Content $MachineAgentSimDir\conf\controller-info.xml -Raw) -replace $enable_orchestration_match, $orchestration | Set-Content $MachineAgentSimDir\conf\controller-info.xml
		(Get-Content $MachineAgentSimDir\conf\controller-info.xml -Raw) -replace $unique_host_id_match, $uniquehostid | Set-Content $MachineAgentSimDir\conf\controller-info.xml
		(Get-Content $MachineAgentSimDir\conf\controller-info.xml -Raw) -replace $account_access_key_match, $accountaccesskey | Set-Content $MachineAgentSimDir\conf\controller-info.xml
		(Get-Content $MachineAgentSimDir\conf\controller-info.xml -Raw) -replace $account_name_match, $accountname | Set-Content $MachineAgentSimDir\conf\controller-info.xml
		(Get-Content $MachineAgentSimDir\conf\controller-info.xml -Raw) -replace $sim_enabled_match, $sim | Set-Content $MachineAgentSimDir\conf\controller-info.xml
		(Get-Content $MachineAgentSimDir\conf\controller-info.xml -Raw) -replace $is_sap_machine_match, $issapmachine | Set-Content $MachineAgentSimDir\conf\controller-info.xml
		(Get-Content $MachineAgentSimDir\conf\controller-info.xml -Raw) -replace $machine_path_match, $machinepath | Set-Content $MachineAgentSimDir\conf\controller-info.xml
		(Get-Content $MachineAgentSimDir\conf\controller-info.xml -Raw) -replace $dotnet_compatibility_mode_match, $dotnetcompatmode | Set-Content $MachineAgentSimDir\conf\controller-info.xml
		Add-Content -Path $MachineAgentSimDir\conf\controller-info.xml -Value $applicationname
		Add-Content -Path $MachineAgentSimDir\conf\controller-info.xml -Value $tiername
		Add-Content -Path $MachineAgentSimDir\conf\controller-info.xml -Value $nodename
	cmd /c cscript $MachineAgentSimDir\InstallService.vbs
}