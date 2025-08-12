#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    AppDynamics Machine Agent Installer for Windows
    
.DESCRIPTION
    This script installs and configures the AppDynamics Machine Agent on Windows systems.
    It handles uninstallation of existing agents, configuration updates, and service installation.
    
.PARAMETER ConfigFile
    Path to configuration file (optional - uses embedded config if not provided)
    
.EXAMPLE
    .\Install-AppDynamicsMachineAgent.ps1
    
.NOTES
    Requires Administrator privileges
    Author: Your Name
    Version: 2.0
    Date: $(Get-Date -Format 'yyyy-MM-dd')
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile
)

# Set strict mode and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Configuration
$Config = @{
    # Application Team Settings
    UniqueHostId = $env:COMPUTERNAME
    ApplicationName = "MyWebApp"  # Replace with your actual application name
    TierName = "WebTier"          # Replace with your actual tier name
    NodeName = $env:COMPUTERNAME
    
    # SaaS Controller Settings
    ControllerHost = 'mycompany.saas.appdynamics.com'  # Replace with your controller host
    ControllerPort = '443'
    ControllerSsl = 'true'
    Orchestration = 'false'
    AccountAccessKey = 'your-account-access-key-here'   # Replace with your actual key
    AccountName = 'your-account-name'                   # Replace with your account name
    SimEnabled = 'true'
    IsSapMachine = ''
    MachinePath = ''
    DotNetCompatMode = 'false'
    
    # Installation Paths
    BaseInstallDir = "C:\Temp"
    InstallDestination = 'C:\AppDynamics'
    ServiceName = "AppDynamics Machine Agent"
}

# Configuration file mappings for controller-info.xml
$ConfigMappings = @{
    '<controller-host></controller-host>' = "<controller-host>$($Config.ControllerHost)</controller-host>"
    '<controller-port></controller-port>' = "<controller-port>$($Config.ControllerPort)</controller-port>"
    '<controller-ssl-enabled>false</controller-ssl-enabled>' = "<controller-ssl-enabled>$($Config.ControllerSsl)</controller-ssl-enabled>"
    '<enable-orchestration>false</enable-orchestration>' = "<enable-orchestration>$($Config.Orchestration)</enable-orchestration>"
    '<unique-host-id></unique-host-id>' = "<unique-host-id>$($Config.UniqueHostId)</unique-host-id>"
    '<account-access-key></account-access-key>' = "<account-access-key>$($Config.AccountAccessKey)</account-access-key>"
    '<account-name></account-name>' = "<account-name>$($Config.AccountName)</account-name>"
    '<sim-enabled>false</sim-enabled>' = "<sim-enabled>$($Config.SimEnabled)</sim-enabled>"
    '<is-sap-machine></is-sap-machine>' = "<is-sap-machine>$($Config.IsSapMachine)</is-sap-machine>"
    '<machine-path></machine-path>' = "<machine-path>$($Config.MachinePath)</machine-path>"
    '<dotnet-compatibility-mode>false</dotnet-compatibility-mode>' = "<dotnet-compatibility-mode>$($Config.DotNetCompatMode)</dotnet-compatibility-mode>"
}

$AdditionalConfig = @(
    "<application-name>$($Config.ApplicationName)</application-name>"
    "<tier-name>$($Config.TierName)</tier-name>"
    "<node-name>$($Config.NodeName)</node-name>"
)
#endregion

#region Functions
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

function Get-MachineAgentFiles {
    param([string]$SearchPath)
    
    try {
        $agentFiles = Get-ChildItem -Path $SearchPath -Recurse -Filter "machineagent*" -ErrorAction Stop
        
        if ($agentFiles.Count -eq 0) {
            throw "No AppDynamics Machine Agent files found in $SearchPath"
        }
        
        if ($agentFiles.Count -gt 1) {
            Write-Log "Multiple agent files found. Using the first one: $($agentFiles[0].Name)" -Level Warning
        }
        
        return @{
            BaseName = $agentFiles[0].BaseName
            FileName = $agentFiles[0].Name
            FullPath = $agentFiles[0].FullName
        }
    }
    catch {
        throw "Failed to locate Machine Agent files: $($_.Exception.Message)"
    }
}

function Remove-ExistingAgent {
    param(
        [string]$ServiceName,
        [string]$MachineAgentPath
    )
    
    try {
        if (Test-Path -Path $MachineAgentPath) {
            Write-Log "Removing existing Machine Agent installation..."
            
            # Stop service if running
            $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            if ($service -and $service.Status -eq 'Running') {
                Write-Log "Stopping $ServiceName service..."
                Stop-Service -Name $ServiceName -Force -ErrorAction Stop
                Start-Sleep -Seconds 5
            }
            
            # Uninstall service
            $uninstallScript = Join-Path $MachineAgentPath "UninstallService.vbs"
            if (Test-Path -Path $uninstallScript) {
                Write-Log "Uninstalling service..."
                $result = Start-Process -FilePath "cscript" -ArgumentList $uninstallScript -Wait -PassThru -NoNewWindow
                if ($result.ExitCode -ne 0) {
                    Write-Log "Warning: Service uninstall returned exit code $($result.ExitCode)" -Level Warning
                }
            }
            
            # Remove directory
            Write-Log "Removing directory: $MachineAgentPath"
            Remove-Item -Path $MachineAgentPath -Recurse -Force -ErrorAction Stop
        }
    }
    catch {
        Write-Log "Error removing existing agent: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Install-MachineAgent {
    param(
        [hashtable]$AgentFiles,
        [string]$InstallDestination,
        [string]$MachineAgentPath
    )
    
    try {
        Write-Log "Installing AppDynamics Machine Agent..."
        
        # Create installation directory
        $agentInstallPath = Join-Path $InstallDestination $AgentFiles.BaseName
        if (-not (Test-Path -Path $agentInstallPath)) {
            New-Item -ItemType Directory -Path $agentInstallPath -Force | Out-Null
        }
        
        # Extract agent files
        Write-Log "Extracting agent files to: $agentInstallPath"
        Expand-Archive -LiteralPath $AgentFiles.FullPath -DestinationPath $agentInstallPath -Force
        
        # Create symbolic link
        Write-Log "Creating symbolic link: $MachineAgentPath -> $agentInstallPath"
        if (Test-Path -Path $MachineAgentPath) {
            Remove-Item -Path $MachineAgentPath -Force
        }
        New-Item -ItemType SymbolicLink -Path $MachineAgentPath -Target $agentInstallPath -Force | Out-Null
        
        Write-Log "Machine Agent installation completed successfully" -Level Success
    }
    catch {
        Write-Log "Error installing Machine Agent: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Update-ConfigurationFile {
    param(
        [string]$ConfigFilePath,
        [hashtable]$ConfigMappings,
        [array]$AdditionalConfig
    )
    
    try {
        Write-Log "Updating configuration file: $ConfigFilePath"
        
        if (-not (Test-Path -Path $ConfigFilePath)) {
            throw "Configuration file not found: $ConfigFilePath"
        }
        
        # Read the configuration file
        $configContent = Get-Content -Path $ConfigFilePath -Raw
        
        # Apply configuration mappings
        foreach ($mapping in $ConfigMappings.GetEnumerator()) {
            $configContent = $configContent -replace [regex]::Escape($mapping.Key), $mapping.Value
        }
        
        # Write updated content back to file
        Set-Content -Path $ConfigFilePath -Value $configContent -Encoding UTF8
        
        # Add additional configuration lines
        foreach ($config in $AdditionalConfig) {
            Add-Content -Path $ConfigFilePath -Value $config -Encoding UTF8
        }
        
        Write-Log "Configuration file updated successfully" -Level Success
    }
    catch {
        Write-Log "Error updating configuration file: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Install-Service {
    param(
        [string]$MachineAgentPath
    )
    
    try {
        Write-Log "Installing AppDynamics Machine Agent service..."
        
        $installScript = Join-Path $MachineAgentPath "InstallService.vbs"
        if (-not (Test-Path -Path $installScript)) {
            throw "Service installation script not found: $installScript"
        }
        
        $result = Start-Process -FilePath "cscript" -ArgumentList $installScript -Wait -PassThru -NoNewWindow
        
        if ($result.ExitCode -eq 0) {
            Write-Log "Service installed successfully" -Level Success
            
            # Start the service
            Write-Log "Starting AppDynamics Machine Agent service..."
            Start-Service -Name $Config.ServiceName -ErrorAction Stop
            Write-Log "Service started successfully" -Level Success
        }
        else {
            throw "Service installation failed with exit code: $($result.ExitCode)"
        }
    }
    catch {
        Write-Log "Error installing service: $($_.Exception.Message)" -Level Error
        throw
    }
}
#endregion

#region Main Script
try {
    Write-Log "Starting AppDynamics Machine Agent installation..." -Level Success
    Write-Log "Script Version: 2.0"
    
    # Verify administrator privileges
    if (-not (Test-Administrator)) {
        throw "This script requires Administrator privileges. Please run as Administrator."
    }
    
    # Load external configuration if provided
    if ($ConfigFile -and (Test-Path -Path $ConfigFile)) {
        Write-Log "Loading configuration from: $ConfigFile"
        try {
            $externalConfig = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
            
            # Override default config with external config values
            foreach ($property in $externalConfig.PSObject.Properties) {
                if ($Config.ContainsKey($property.Name)) {
                    $Config[$property.Name] = $property.Value
                    Write-Log "  Updated $($property.Name): $($property.Value)"
                }
            }
            Write-Log "External configuration loaded successfully" -Level Success
        }
        catch {
            Write-Log "Failed to load configuration file: $($_.Exception.Message)" -Level Error
            throw
        }
    }
    
    # Display configuration
    Write-Log "Configuration Summary:"
    Write-Log "  Base Install Directory: $($Config.BaseInstallDir)"
    Write-Log "  Install Destination: $($Config.InstallDestination)"
    Write-Log "  Controller Host: $($Config.ControllerHost)"
    Write-Log "  Controller Port: $($Config.ControllerPort)"
    Write-Log "  Application Name: $($Config.ApplicationName)"
    Write-Log "  Tier Name: $($Config.TierName)"
    Write-Log "  Node Name: $($Config.NodeName)"
    
    # Get agent files
    Write-Log "Locating AppDynamics Machine Agent files..."
    $agentFiles = Get-MachineAgentFiles -SearchPath $Config.BaseInstallDir
    
    Write-Log "Found agent files:"
    Write-Log "  Base Name: $($agentFiles.BaseName)"
    Write-Log "  File Name: $($agentFiles.FileName)"
    Write-Log "  Full Path: $($agentFiles.FullPath)"
    
    # Set paths
    $machineAgentPath = Join-Path $Config.InstallDestination "machine-agent"
    $agentInstallPath = Join-Path $Config.InstallDestination $agentFiles.BaseName
    
    # Check if agent is already installed
    if (Test-Path -Path $agentInstallPath) {
        Write-Log "Existing installation detected. Removing..." -Level Warning
        Remove-ExistingAgent -ServiceName $Config.ServiceName -MachineAgentPath $machineAgentPath
    }
    
    # Install the agent
    Install-MachineAgent -AgentFiles $agentFiles -InstallDestination $Config.InstallDestination -MachineAgentPath $machineAgentPath
    
    # Update configuration
    $configFilePath = Join-Path $machineAgentPath "conf\controller-info.xml"
    Update-ConfigurationFile -ConfigFilePath $configFilePath -ConfigMappings $ConfigMappings -AdditionalConfig $AdditionalConfig
    
    # Install and start service
    Install-Service -MachineAgentPath $machineAgentPath
    
    Write-Log "AppDynamics Machine Agent installation completed successfully!" -Level Success
    Write-Log "Service Status: $(Get-Service -Name $($Config.ServiceName) | Select-Object -ExpandProperty Status)"
}
catch {
    Write-Log "Installation failed: $($_.Exception.Message)" -Level Error
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
finally {
    Write-Log "Installation script completed."
}
#endregion