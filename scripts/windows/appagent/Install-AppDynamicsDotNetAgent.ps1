#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    AppDynamics .NET APM Agent Installation and Management Script
    
.DESCRIPTION
    This script provides comprehensive installation and management capabilities for AppDynamics .NET APM Agent including:
    - Download and install .NET agent
    - Configure IIS integration
    - Setup application pools
    - Configure controller connection
    - Manage service lifecycle
    - Validate installation
    
.PARAMETER Action
    The action to perform: Install, Uninstall, Configure, Start, Stop, Restart, Status, Validate
    
.PARAMETER ConfigFile
    Path to JSON configuration file containing agent settings
    
.PARAMETER AgentArchive
    Path to .NET agent MSI or ZIP file (for Install operations)
    
.PARAMETER ApplicationPool
    Specific application pool to configure (optional - configures all pools if not specified)
    
.PARAMETER Force
    Force installation even if agent is already installed
    
.EXAMPLE
    .\Install-AppDynamicsDotNetAgent.ps1 -Action Install -ConfigFile "dotnet-config.json"
    
.EXAMPLE
    .\Install-AppDynamicsDotNetAgent.ps1 -Action Configure -ApplicationPool "MyAppPool"
    
.EXAMPLE
    .\Install-AppDynamicsDotNetAgent.ps1 -Action Status
    
.NOTES
    Requires Administrator privileges and IIS installed
    Author: AppDynamics .NET Agent Installer
    Version: 1.0
    Compatible with AppDynamics .NET Agent 20.x+
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Install', 'Uninstall', 'Configure', 'Start', 'Stop', 'Restart', 'Status', 'Validate', 'Download')]
    [string]$Action,
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile,
    
    [Parameter(Mandatory = $false)]
    [string]$AgentArchive,
    
    [Parameter(Mandatory = $false)]
    [string]$ApplicationPool,
    
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

# Set strict mode and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Configuration
$Config = @{
    AgentName = 'AppDynamics .NET Agent'
    InstallDestination = 'C:\AppDynamics'
    DotNetAgentPath = 'C:\AppDynamics\dotNetAgent'
    TempDownloadPath = 'C:\Temp\AppDynamics'
    ServiceName = 'AppDynamics.Agent.Coordinator_service'
    RegistryPath = 'HKLM:\SOFTWARE\AppDynamics'
    IISModuleName = 'AppDynamicsIIS'
    BackupBasePath = 'C:\AppDynamics\Backups'
}

# Default configuration values
$DefaultConfig = @{
    ControllerHost = 'controller.company.com'
    ControllerPort = '443'
    ControllerSsl = 'true'
    AccountAccessKey = ''
    AccountName = 'customer1'
    ApplicationName = 'MyDotNetApplication'
    TierName = 'WebTier'
    NodeName = $env:COMPUTERNAME
    AgentType = 'dotNetAgent'
    LogLevel = 'INFO'
    LogPath = 'C:\AppDynamics\dotNetAgent\Logs'
}
#endregion

#region Utility Functions
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        'Info' { Write-Host $logMessage -ForegroundColor White }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Error' { Write-Host $logMessage -ForegroundColor Red }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
    }
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-IISInstalled {
    try {
        Import-Module WebAdministration -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Load-Configuration {
    param([string]$ConfigFilePath)
    
    if (-not $ConfigFilePath -or -not (Test-Path $ConfigFilePath)) {
        Write-Log "Using default configuration" -Level Warning
        return $DefaultConfig
    }
    
    try {
        Write-Log "Loading configuration from: $ConfigFilePath" -Level Info
        $configData = Get-Content -Path $ConfigFilePath -Raw | ConvertFrom-Json
        
        # Merge with defaults
        $mergedConfig = $DefaultConfig.Clone()
        foreach ($property in $configData.PSObject.Properties) {
            $mergedConfig[$property.Name] = $property.Value
        }
        
        Write-Log "Configuration loaded successfully" -Level Success
        return $mergedConfig
    }
    catch {
        Write-Log "Failed to load configuration: $($_.Exception.Message). Using defaults." -Level Warning
        return $DefaultConfig
    }
}

function Test-DotNetAgentInstalled {
    $installExists = Test-Path $Config.DotNetAgentPath
    $serviceExists = Get-Service -Name $Config.ServiceName -ErrorAction SilentlyContinue
    $registryExists = Test-Path $Config.RegistryPath
    
    return @{
        InstallationExists = $installExists
        ServiceExists = $null -ne $serviceExists
        RegistryExists = $registryExists
        IsInstalled = $installExists -and ($null -ne $serviceExists) -and $registryExists
    }
}

function Get-IISApplicationPools {
    try {
        Import-Module WebAdministration -ErrorAction Stop
        return Get-IISAppPool | Select-Object Name, State, ProcessModel
    }
    catch {
        Write-Log "Failed to get IIS application pools: $($_.Exception.Message)" -Level Error
        return @()
    }
}
#endregion

#region Installation Functions
function Download-DotNetAgent {
    param(
        [string]$DownloadUrl,
        [string]$OutputPath
    )
    
    try {
        Write-Log "Creating download directory..." -Level Info
        if (-not (Test-Path $Config.TempDownloadPath)) {
            New-Item -ItemType Directory -Path $Config.TempDownloadPath -Force | Out-Null
        }
        
        if (-not $DownloadUrl) {
            Write-Log "Please download the AppDynamics .NET Agent from:" -Level Info
            Write-Log "https://download.appdynamics.com" -Level Info
            Write-Log "Look for: .NET Agent (for Windows IIS)" -Level Info
            throw "Download URL not provided. Please specify -AgentArchive parameter with local file path."
        }
        
        Write-Log "Downloading .NET Agent from: $DownloadUrl" -Level Info
        $fileName = Split-Path $DownloadUrl -Leaf
        $downloadPath = Join-Path $Config.TempDownloadPath $fileName
        
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $downloadPath -UseBasicParsing
        Write-Log "Download completed: $downloadPath" -Level Success
        
        return $downloadPath
    }
    catch {
        Write-Log "Failed to download .NET Agent: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Install-DotNetAgent {
    param(
        [string]$AgentFilePath,
        [hashtable]$Configuration
    )
    
    try {
        Write-Log "Installing AppDynamics .NET Agent..." -Level Info
        
        # Verify installer file
        if (-not (Test-Path $AgentFilePath)) {
            throw "Agent installer not found: $AgentFilePath"
        }
        
        # Create installation directory
        if (-not (Test-Path $Config.InstallDestination)) {
            New-Item -ItemType Directory -Path $Config.InstallDestination -Force | Out-Null
        }
        
        $fileExtension = [System.IO.Path]::GetExtension($AgentFilePath).ToLower()
        
        switch ($fileExtension) {
            '.msi' {
                Write-Log "Installing from MSI package..." -Level Info
                Install-FromMSI -MSIPath $AgentFilePath -Configuration $Configuration
            }
            '.zip' {
                Write-Log "Installing from ZIP package..." -Level Info
                Install-FromZIP -ZipPath $AgentFilePath -Configuration $Configuration
            }
            default {
                throw "Unsupported file type: $fileExtension. Expected .msi or .zip"
            }
        }
        
        Write-Log ".NET Agent installation completed" -Level Success
    }
    catch {
        Write-Log "Failed to install .NET Agent: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Install-FromMSI {
    param(
        [string]$MSIPath,
        [hashtable]$Configuration
    )
    
    # Build MSI arguments
    $msiArgs = @(
        '/i'
        "`"$MSIPath`""
        '/quiet'
        '/norestart'
        "AD_AgentHTTPProxyHost=`"$($Configuration.ControllerHost)`""
        "AD_AgentHTTPProxyPort=`"$($Configuration.ControllerPort)`""
        "AD_AgentAccountAccessKey=`"$($Configuration.AccountAccessKey)`""
        "AD_AgentAccountName=`"$($Configuration.AccountName)`""
        "AD_AgentApplicationName=`"$($Configuration.ApplicationName)`""
        "AD_AgentTierName=`"$($Configuration.TierName)`""
        "AD_AgentNodeName=`"$($Configuration.NodeName)`""
    )
    
    Write-Log "Running MSI installer with arguments..." -Level Info
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -ne 0) {
        throw "MSI installation failed with exit code: $($process.ExitCode)"
    }
    
    Write-Log "MSI installation completed successfully" -Level Success
}

function Install-FromZIP {
    param(
        [string]$ZipPath,
        [hashtable]$Configuration
    )
    
    # Extract ZIP file
    $extractPath = Join-Path $Config.TempDownloadPath "DotNetAgent_Extract"
    if (Test-Path $extractPath) {
        Remove-Item $extractPath -Recurse -Force
    }
    
    Write-Log "Extracting ZIP file..." -Level Info
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $extractPath -Force
    
    # Find the actual agent directory
    $agentDir = Get-ChildItem $extractPath -Directory | Where-Object { $_.Name -like "*dotNetAgent*" -or $_.Name -like "*AppDynamics*" } | Select-Object -First 1
    
    if (-not $agentDir) {
        throw "Could not find .NET Agent directory in extracted files"
    }
    
    # Copy to installation directory
    Write-Log "Copying agent files to installation directory..." -Level Info
    if (Test-Path $Config.DotNetAgentPath) {
        Remove-Item $Config.DotNetAgentPath -Recurse -Force
    }
    
    Copy-Item $agentDir.FullName $Config.DotNetAgentPath -Recurse -Force
    
    # Configure the agent
    Configure-DotNetAgent -Configuration $Configuration
    
    # Register with IIS
    Register-IISModule
    
    Write-Log "ZIP installation completed successfully" -Level Success
}

function Configure-DotNetAgent {
    param([hashtable]$Configuration)
    
    try {
        Write-Log "Configuring .NET Agent..." -Level Info
        
        # Create config directory if it doesn't exist
        $configDir = Join-Path $Config.DotNetAgentPath "Config"
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }
        
        # Create app.config for the agent
        $appConfigPath = Join-Path $configDir "app.config"
        Create-AgentConfiguration -ConfigPath $appConfigPath -Configuration $Configuration
        
        # Set environment variables for IIS
        Set-IISEnvironmentVariables -Configuration $Configuration
        
        # Configure application pools
        if ($ApplicationPool) {
            Configure-ApplicationPool -PoolName $ApplicationPool -Configuration $Configuration
        } else {
            Configure-AllApplicationPools -Configuration $Configuration
        }
        
        Write-Log ".NET Agent configuration completed" -Level Success
    }
    catch {
        Write-Log "Failed to configure .NET Agent: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Create-AgentConfiguration {
    param(
        [string]$ConfigPath,
        [hashtable]$Configuration
    )
    
    $configXml = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
    <appSettings>
        <add key="APPDYNAMICS_AGENT_APPLICATION_NAME" value="$($Configuration.ApplicationName)" />
        <add key="APPDYNAMICS_AGENT_TIER_NAME" value="$($Configuration.TierName)" />
        <add key="APPDYNAMICS_AGENT_NODE_NAME" value="$($Configuration.NodeName)" />
        <add key="APPDYNAMICS_CONTROLLER_HOST_NAME" value="$($Configuration.ControllerHost)" />
        <add key="APPDYNAMICS_CONTROLLER_PORT" value="$($Configuration.ControllerPort)" />
        <add key="APPDYNAMICS_CONTROLLER_SSL_ENABLED" value="$($Configuration.ControllerSsl)" />
        <add key="APPDYNAMICS_AGENT_ACCOUNT_NAME" value="$($Configuration.AccountName)" />
        <add key="APPDYNAMICS_AGENT_ACCOUNT_ACCESS_KEY" value="$($Configuration.AccountAccessKey)" />
        <add key="APPDYNAMICS_AGENT_LOGS_DIR" value="$($Configuration.LogPath)" />
        <add key="APPDYNAMICS_AGENT_LOG_LEVEL" value="$($Configuration.LogLevel)" />
    </appSettings>
</configuration>
"@
    
    Set-Content -Path $ConfigPath -Value $configXml -Encoding UTF8
    Write-Log "Created agent configuration: $ConfigPath" -Level Info
}

function Set-IISEnvironmentVariables {
    param([hashtable]$Configuration)
    
    Write-Log "Setting IIS environment variables..." -Level Info
    
    $envVars = @{
        'APPDYNAMICS_AGENT_APPLICATION_NAME' = $Configuration.ApplicationName
        'APPDYNAMICS_AGENT_TIER_NAME' = $Configuration.TierName
        'APPDYNAMICS_AGENT_NODE_NAME' = $Configuration.NodeName
        'APPDYNAMICS_CONTROLLER_HOST_NAME' = $Configuration.ControllerHost
        'APPDYNAMICS_CONTROLLER_PORT' = $Configuration.ControllerPort
        'APPDYNAMICS_CONTROLLER_SSL_ENABLED' = $Configuration.ControllerSsl
        'APPDYNAMICS_AGENT_ACCOUNT_NAME' = $Configuration.AccountName
        'APPDYNAMICS_AGENT_ACCOUNT_ACCESS_KEY' = $Configuration.AccountAccessKey
        'COR_ENABLE_PROFILING' = '1'
        'COR_PROFILER' = '{57e1aa68-2229-41aa-9931-a6e93bbc64d8}'
        'COR_PROFILER_PATH_32' = Join-Path $Config.DotNetAgentPath 'AppDynamics.AgentProfiler.Win32.dll'
        'COR_PROFILER_PATH_64' = Join-Path $Config.DotNetAgentPath 'AppDynamics.AgentProfiler.Win64.dll'
    }
    
    foreach ($var in $envVars.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($var.Key, $var.Value, 'Machine')
        Write-Log "Set environment variable: $($var.Key)" -Level Info
    }
}

function Configure-ApplicationPool {
    param(
        [string]$PoolName,
        [hashtable]$Configuration
    )
    
    try {
        Write-Log "Configuring application pool: $PoolName" -Level Info
        
        Import-Module WebAdministration -ErrorAction Stop
        
        # Check if pool exists
        if (-not (Get-IISAppPool -Name $PoolName -ErrorAction SilentlyContinue)) {
            Write-Log "Application pool '$PoolName' not found" -Level Warning
            return
        }
        
        # Set environment variables for the specific pool
        $envVars = @{
            'APPDYNAMICS_AGENT_APPLICATION_NAME' = $Configuration.ApplicationName
            'APPDYNAMICS_AGENT_TIER_NAME' = $Configuration.TierName
            'APPDYNAMICS_AGENT_NODE_NAME' = "$($Configuration.NodeName)-$PoolName"
        }
        
        foreach ($var in $envVars.GetEnumerator()) {
            Set-ItemProperty -Path "IIS:\AppPools\$PoolName" -Name "processModel.environmentVariables.[$($var.Key)]" -Value $var.Value
        }
        
        # Restart the application pool
        Restart-WebAppPool -Name $PoolName
        Write-Log "Configured and restarted application pool: $PoolName" -Level Success
    }
    catch {
        Write-Log "Failed to configure application pool '$PoolName': $($_.Exception.Message)" -Level Error
    }
}

function Configure-AllApplicationPools {
    param([hashtable]$Configuration)
    
    Write-Log "Configuring all application pools..." -Level Info
    
    $appPools = Get-IISApplicationPools
    foreach ($pool in $appPools) {
        if ($pool.State -eq 'Started') {
            Configure-ApplicationPool -PoolName $pool.Name -Configuration $Configuration
        }
    }
}

function Register-IISModule {
    try {
        Write-Log "Registering AppDynamics IIS module..." -Level Info
        
        Import-Module WebAdministration -ErrorAction Stop
        
        $modulePath = Join-Path $Config.DotNetAgentPath "AppDynamics.IIS.Module.dll"
        
        if (-not (Test-Path $modulePath)) {
            Write-Log "IIS module not found at: $modulePath" -Level Warning
            return
        }
        
        # Remove existing module if present
        Remove-WebGlobalModule -Name $Config.IISModuleName -ErrorAction SilentlyContinue
        
        # Add the module
        New-WebGlobalModule -Name $Config.IISModuleName -Image $modulePath -Precondition "managedHandler"
        
        Write-Log "IIS module registered successfully" -Level Success
    }
    catch {
        Write-Log "Failed to register IIS module: $($_.Exception.Message)" -Level Error
    }
}
#endregion

#region Service Management Functions
function Start-DotNetAgentService {
    try {
        Write-Log "Starting .NET Agent service..." -Level Info
        $service = Get-Service -Name $Config.ServiceName -ErrorAction SilentlyContinue
        
        if (-not $service) {
            Write-Log "Service not found: $($Config.ServiceName)" -Level Warning
            return
        }
        
        if ($service.Status -eq 'Running') {
            Write-Log "Service is already running" -Level Success
            return
        }
        
        Start-Service -Name $Config.ServiceName -ErrorAction Stop
        Write-Log "Service started successfully" -Level Success
    }
    catch {
        Write-Log "Failed to start service: $($_.Exception.Message)" -Level Error
    }
}

function Stop-DotNetAgentService {
    try {
        Write-Log "Stopping .NET Agent service..." -Level Info
        $service = Get-Service -Name $Config.ServiceName -ErrorAction SilentlyContinue
        
        if (-not $service) {
            Write-Log "Service not found: $($Config.ServiceName)" -Level Warning
            return
        }
        
        if ($service.Status -eq 'Stopped') {
            Write-Log "Service is already stopped" -Level Success
            return
        }
        
        Stop-Service -Name $Config.ServiceName -Force -ErrorAction Stop
        Write-Log "Service stopped successfully" -Level Success
    }
    catch {
        Write-Log "Failed to stop service: $($_.Exception.Message)" -Level Error
    }
}

function Restart-DotNetAgentService {
    Stop-DotNetAgentService
    Start-Sleep -Seconds 3
    Start-DotNetAgentService
    
    # Also restart IIS to ensure agent is loaded
    Write-Log "Restarting IIS..." -Level Info
    iisreset /restart
    Write-Log "IIS restarted" -Level Success
}
#endregion

#region Status and Validation Functions
function Get-DotNetAgentStatus {
    try {
        Write-Log "=== AppDynamics .NET Agent Status ===" -Level Success
        
        $agentStatus = Test-DotNetAgentInstalled
        
        # Installation Status
        Write-Log "Installation Status:" -Level Info
        Write-Log "  Installation Path: $($Config.DotNetAgentPath)" -Level Info
        Write-Log "  Installation Exists: $($agentStatus.InstallationExists)" -Level Info
        Write-Log "  Registry Exists: $($agentStatus.RegistryExists)" -Level Info
        Write-Log "  Fully Installed: $($agentStatus.IsInstalled)" -Level Info
        
        # Service Status
        Write-Log "" -Level Info
        Write-Log "Service Status:" -Level Info
        $service = Get-Service -Name $Config.ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            Write-Log "  Service Name: $($service.Name)" -Level Info
            Write-Log "  Service Status: $($service.Status)" -Level Info
            Write-Log "  Start Type: $($service.StartType)" -Level Info
        } else {
            Write-Log "  Service: Not Found" -Level Warning
        }
        
        # IIS Status
        Write-Log "" -Level Info
        Write-Log "IIS Integration:" -Level Info
        if (Test-IISInstalled) {
            Import-Module WebAdministration -ErrorAction SilentlyContinue
            $module = Get-WebGlobalModule -Name $Config.IISModuleName -ErrorAction SilentlyContinue
            if ($module) {
                Write-Log "  IIS Module: Registered" -Level Info
                Write-Log "  Module Path: $($module.Image)" -Level Info
            } else {
                Write-Log "  IIS Module: Not Registered" -Level Warning
            }
            
            # Application Pool Status
            $appPools = Get-IISApplicationPools
            Write-Log "  Application Pools: $($appPools.Count) found" -Level Info
            foreach ($pool in $appPools | Select-Object -First 5) {
                Write-Log "    - $($pool.Name): $($pool.State)" -Level Info
            }
        } else {
            Write-Log "  IIS: Not Installed" -Level Warning
        }
        
        # Environment Variables
        Write-Log "" -Level Info
        Write-Log "Environment Variables:" -Level Info
        $envVars = @('APPDYNAMICS_CONTROLLER_HOST_NAME', 'APPDYNAMICS_AGENT_APPLICATION_NAME', 'COR_ENABLE_PROFILING')
        foreach ($envVar in $envVars) {
            $value = [Environment]::GetEnvironmentVariable($envVar, 'Machine')
            if ($value) {
                Write-Log "  $envVar: $value" -Level Info
            } else {
                Write-Log "  $envVar: Not Set" -Level Warning
            }
        }
    }
    catch {
        Write-Log "Failed to get agent status: $($_.Exception.Message)" -Level Error
    }
}

function Test-DotNetAgentValidation {
    try {
        Write-Log "=== AppDynamics .NET Agent Validation ===" -Level Success
        
        $validationResults = @()
        
        # Check installation
        $agentStatus = Test-DotNetAgentInstalled
        if ($agentStatus.IsInstalled) {
            $validationResults += "✓ Agent installation found"
        } else {
            $validationResults += "✗ Agent installation incomplete"
        }
        
        # Check service
        $service = Get-Service -Name $Config.ServiceName -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            $validationResults += "✓ Agent service running"
        } else {
            $validationResults += "✗ Agent service not running"
        }
        
        # Check IIS integration
        if (Test-IISInstalled) {
            Import-Module WebAdministration -ErrorAction SilentlyContinue
            $module = Get-WebGlobalModule -Name $Config.IISModuleName -ErrorAction SilentlyContinue
            if ($module) {
                $validationResults += "✓ IIS module registered"
            } else {
                $validationResults += "✗ IIS module not registered"
            }
        }
        
        # Check environment variables
        $corEnabled = [Environment]::GetEnvironmentVariable('COR_ENABLE_PROFILING', 'Machine')
        if ($corEnabled -eq '1') {
            $validationResults += "✓ .NET profiling enabled"
        } else {
            $validationResults += "✗ .NET profiling not enabled"
        }
        
        # Display results
        Write-Log "Validation Results:" -Level Info
        foreach ($result in $validationResults) {
            if ($result.StartsWith("✓")) {
                Write-Log "  $result" -Level Success
            } else {
                Write-Log "  $result" -Level Warning
            }
        }
        
        $successCount = ($validationResults | Where-Object { $_.StartsWith("✓") }).Count
        $totalCount = $validationResults.Count
        
        Write-Log "" -Level Info
        Write-Log "Validation Summary: $successCount/$totalCount checks passed" -Level Info
        
        if ($successCount -eq $totalCount) {
            Write-Log "✓ All validations passed - Agent ready for use!" -Level Success
        } else {
            Write-Log "⚠ Some validations failed - Please review configuration" -Level Warning
        }
    }
    catch {
        Write-Log "Failed to validate agent: $($_.Exception.Message)" -Level Error
    }
}
#endregion

#region Uninstallation Functions
function Uninstall-DotNetAgent {
    try {
        Write-Log "Uninstalling AppDynamics .NET Agent..." -Level Info
        
        # Stop service
        Stop-DotNetAgentService
        
        # Remove IIS module
        Write-Log "Removing IIS module..." -Level Info
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        Remove-WebGlobalModule -Name $Config.IISModuleName -ErrorAction SilentlyContinue
        
        # Remove environment variables
        Write-Log "Removing environment variables..." -Level Info
        $envVars = @('COR_ENABLE_PROFILING', 'COR_PROFILER', 'COR_PROFILER_PATH_32', 'COR_PROFILER_PATH_64',
                     'APPDYNAMICS_AGENT_APPLICATION_NAME', 'APPDYNAMICS_AGENT_TIER_NAME', 'APPDYNAMICS_AGENT_NODE_NAME',
                     'APPDYNAMICS_CONTROLLER_HOST_NAME', 'APPDYNAMICS_CONTROLLER_PORT', 'APPDYNAMICS_CONTROLLER_SSL_ENABLED',
                     'APPDYNAMICS_AGENT_ACCOUNT_NAME', 'APPDYNAMICS_AGENT_ACCOUNT_ACCESS_KEY')
        
        foreach ($envVar in $envVars) {
            [Environment]::SetEnvironmentVariable($envVar, $null, 'Machine')
        }
        
        # Remove installation directory
        if (Test-Path $Config.DotNetAgentPath) {
            Write-Log "Removing installation directory..." -Level Info
            Remove-Item $Config.DotNetAgentPath -Recurse -Force
        }
        
        # Remove registry entries
        if (Test-Path $Config.RegistryPath) {
            Write-Log "Removing registry entries..." -Level Info
            Remove-Item $Config.RegistryPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Restart IIS
        Write-Log "Restarting IIS..." -Level Info
        iisreset /restart
        
        Write-Log "Agent uninstalled successfully" -Level Success
    }
    catch {
        Write-Log "Failed to uninstall agent: $($_.Exception.Message)" -Level Error
        throw
    }
}
#endregion

#region Main Script Logic
try {
    Write-Log "AppDynamics .NET Agent Manager v1.0" -Level Success
    Write-Log "Action: $Action" -Level Info
    
    # Verify administrator privileges
    if (-not (Test-Administrator)) {
        throw "This script requires Administrator privileges. Please run as Administrator."
    }
    
    # Verify IIS is installed for most operations
    if ($Action -in @('Install', 'Configure', 'Status') -and -not (Test-IISInstalled)) {
        Write-Log "IIS is not installed or WebAdministration module is not available" -Level Warning
        Write-Log "Some features may not work correctly" -Level Warning
    }
    
    switch ($Action.ToLower()) {
        'download' {
            Write-Log "Please download the AppDynamics .NET Agent manually from:" -Level Info
            Write-Log "https://download.appdynamics.com" -Level Info
            Write-Log "Search for: '.NET Agent' or 'DotNetAgentSetup'" -Level Info
            Write-Log "Then run this script with -Action Install -AgentArchive <path-to-downloaded-file>" -Level Info
        }
        
        'install' {
            if (-not $AgentArchive) {
                throw "AgentArchive parameter is required for Install action"
            }
            $configuration = Load-Configuration -ConfigFilePath $ConfigFile
            Install-DotNetAgent -AgentFilePath $AgentArchive -Configuration $configuration
        }
        
        'configure' {
            $configuration = Load-Configuration -ConfigFilePath $ConfigFile
            Configure-DotNetAgent -Configuration $configuration
        }
        
        'uninstall' {
            Uninstall-DotNetAgent
        }
        
        'start' {
            Start-DotNetAgentService
        }
        
        'stop' {
            Stop-DotNetAgentService
        }
        
        'restart' {
            Restart-DotNetAgentService
        }
        
        'status' {
            Get-DotNetAgentStatus
        }
        
        'validate' {
            Test-DotNetAgentValidation
        }
        
        default {
            throw "Unknown action: $Action"
        }
    }
    
    Write-Log "Operation completed successfully!" -Level Success
}
catch {
    Write-Log "Operation failed: $($_.Exception.Message)" -Level Error
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
finally {
    Write-Log ".NET Agent management script completed." -Level Info
}
#endregion