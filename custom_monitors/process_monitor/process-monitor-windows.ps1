#Requires -Version 5.1

<#
.SYNOPSIS
    Enhanced Process Monitor for AppDynamics Custom Metrics
    
.DESCRIPTION
    Monitors specified processes and outputs custom metrics in AppDynamics format.
    Supports configuration files, logging, and flexible output formats.
    
.PARAMETER ConfigFile
    Path to JSON configuration file containing process names and settings
    
.PARAMETER OutputFormat
    Output format: AppDynamics (default), JSON, CSV, or Console
    
.PARAMETER LogFile
    Path to log file (optional)
    
.PARAMETER IncludeDetails
    Include additional process details like CPU, Memory usage
    
.PARAMETER Quiet
    Suppress console output except for metrics
    
.EXAMPLE
    .\ProcessMonitor.ps1
    
.EXAMPLE
    .\ProcessMonitor.ps1 -ConfigFile "processes.json" -OutputFormat JSON -LogFile "monitor.log"
    
.EXAMPLE
    .\ProcessMonitor.ps1 -IncludeDetails -OutputFormat Console
    
.NOTES
    Author: Enhanced Process Monitor
    Version: 2.0
    Compatible with AppDynamics Machine Agent custom metrics
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('AppDynamics', 'JSON', 'CSV', 'Console')]
    [string]$OutputFormat = 'AppDynamics',
    
    [Parameter(Mandatory = $false)]
    [string]$LogFile,
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeDetails,
    
    [Parameter(Mandatory = $false)]
    [switch]$Quiet
)

# Set error handling
$ErrorActionPreference = 'Stop'

#region Configuration
# Default process names to monitor
$DefaultProcessNames = @(
    # Security & Endpoint Protection
    'CSFalconService', 'falcon-sensor', 'BESClient', 'QualysAgent',
    
    # Logging & Monitoring
    'splunkd', 'logger',
    
    # BigFix/IBM Endpoint Manager
    'FillDB', 'GatherDB', 'BESRootServer', 'BESWebReportsServer', 
    'BESPluginService', 'BESWebUI', 'BESRelay', 'BESPluginPortal',
    
    # Certificate Services
    'certsrv',
    
    # K2/Nintex
    'K2HostServer', 'SourceCode.Configuration.Api', 'K2ServerEvent', 'Nanobot',
    
    # Web Servers
    'apache2.conf', 'httpd',
    
    # Java Applications
    'java',
    
    # System Services
    'Services.msc',
    
    # Broker Services
    'BrokerAgent', 'BrokerService', 'CdfSvc',
    
    # Citrix Services
    'Citrix.ADIdentity', 'Citrix.Analytics', 'Citrix.AppLibrary',
    'Citrix.Authentication.FederatedAuthenticationService', 'Citrix.Configuration',
    'Citrix.ConfigurationLogging', 'Citrix.DelegatedAdmin',
    'Citrix.DeliveryServices.ConfigurationReplicationService.ServiceHost',
    'Citrix.DeliveryServices.CredentialWallet.ServiceHost',
    'Citrix.DeliveryServices.DomainServices.ServiceHost',
    'Citrix.DeliveryServices.PeerResolutionService.ServiceHost',
    'Citrix.DeliveryServices.ServiceMonitor.ServiceHost',
    'Citrix.DeliveryServices.SubscriptionsStore.ServiceHost',
    'Citrix.EnvTest', 'Citrix.Host', 'Citrix.MachineCreation',
    'Citrix.Monitor', 'Citrix.Orchestration', 'Citrix.Storefront',
    'Citrix.Storefront.PrivilegedService', 'Citrix.Trust',
    'ConfigSyncService', 'CpSvc', 'CseEngine', 'CtxCeipSvc',
    'CtxLocalUserSrv', 'CtxLSPortSvc', 'CtxRdr', 'CtxSvcHost',
    'encsvc', 'HighAvailabilityService', 'ImaAdvanceSrv64',
    'lmadmin', 'SCService64', 'SemsService', 'TelemetryService',
    'UWACacheService', 'WebSocketService', 'XaXdCloudProxy',
    
    # Oracle Database
    'asm_pmon_+ASM', 'ora_pmon_cdb12201', 'ora_pmon_cdb19300', 'tnslsnr'
)

# Configuration object
$Config = @{
    ProcessNames = $DefaultProcessNames
    MetricPrefix = 'Custom Metrics|ProcessMon'
    TimeoutSeconds = 30
    MaxRetries = 3
}
#endregion

#region Utility Functions
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Debug')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Console output (unless quiet mode)
    if (-not $Quiet -or $Level -eq 'Error') {
        switch ($Level) {
            'Info' { Write-Host $logMessage -ForegroundColor White }
            'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
            'Error' { Write-Host $logMessage -ForegroundColor Red }
            'Debug' { Write-Host $logMessage -ForegroundColor Gray }
        }
    }
    
    # File logging
    if ($LogFile) {
        try {
            Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
        }
        catch {
            # Ignore logging errors to prevent script failure
        }
    }
}

function Load-Configuration {
    param([string]$ConfigFilePath)
    
    if (-not $ConfigFilePath -or -not (Test-Path $ConfigFilePath)) {
        Write-Log "Using default configuration" -Level Info
        return $Config
    }
    
    try {
        Write-Log "Loading configuration from: $ConfigFilePath" -Level Info
        $configData = Get-Content -Path $ConfigFilePath -Raw | ConvertFrom-Json
        
        # Update configuration with loaded values
        if ($configData.ProcessNames) {
            $Config.ProcessNames = $configData.ProcessNames
        }
        if ($configData.MetricPrefix) {
            $Config.MetricPrefix = $configData.MetricPrefix
        }
        if ($configData.TimeoutSeconds) {
            $Config.TimeoutSeconds = $configData.TimeoutSeconds
        }
        
        Write-Log "Configuration loaded successfully. Monitoring $($Config.ProcessNames.Count) processes" -Level Info
        return $Config
    }
    catch {
        Write-Log "Failed to load configuration: $($_.Exception.Message). Using defaults." -Level Warning
        return $Config
    }
}

function Get-ProcessDetails {
    param([System.Diagnostics.Process]$Process)
    
    try {
        $details = [PSCustomObject]@{
            Name = $Process.ProcessName
            Id = $Process.Id
            StartTime = $null
            CPU = $null
            WorkingSet = $null
            VirtualMemory = $null
            Status = 'Running'
        }
        
        # Get additional details if requested
        if ($IncludeDetails) {
            try {
                $details.StartTime = $Process.StartTime
                $details.CPU = [math]::Round($Process.TotalProcessorTime.TotalSeconds, 2)
                $details.WorkingSet = [math]::Round($Process.WorkingSet64 / 1MB, 2)
                $details.VirtualMemory = [math]::Round($Process.VirtualMemorySize64 / 1MB, 2)
            }
            catch {
                # Some processes may not allow access to these properties
                Write-Log "Could not get detailed info for $($Process.ProcessName): $($_.Exception.Message)" -Level Debug
            }
        }
        
        return $details
    }
    catch {
        Write-Log "Error getting process details for $($Process.ProcessName): $($_.Exception.Message)" -Level Warning
        return $null
    }
}

function Format-Output {
    param(
        [array]$ProcessResults,
        [string]$Format
    )
    
    switch ($Format) {
        'AppDynamics' {
            foreach ($result in $ProcessResults) {
                $metricName = "$($Config.MetricPrefix)|$($result.Name)"
                Write-Output "name=$metricName,value=1"
                
                if ($IncludeDetails -and $result.CPU -ne $null) {
                    Write-Output "name=$($Config.MetricPrefix)|$($result.Name)|CPU,value=$($result.CPU)"
                    Write-Output "name=$($Config.MetricPrefix)|$($result.Name)|Memory,value=$($result.WorkingSet)"
                }
            }
        }
        
        'JSON' {
            $output = @{
                Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Processes = $ProcessResults
                Summary = @{
                    Total = $ProcessResults.Count
                    MonitoredProcesses = $Config.ProcessNames.Count
                }
            }
            Write-Output ($output | ConvertTo-Json -Depth 3)
        }
        
        'CSV' {
            $ProcessResults | ConvertTo-Csv -NoTypeInformation | Write-Output
        }
        
        'Console' {
            Write-Host ""
            Write-Host "=== Process Monitor Results ===" -ForegroundColor Green
            Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
            Write-Host "Processes Found: $($ProcessResults.Count) / $($Config.ProcessNames.Count) monitored" -ForegroundColor Gray
            Write-Host ""
            
            $ProcessResults | Format-Table -AutoSize | Out-Host
        }
    }
}
#endregion

#region Main Process Monitoring Logic
function Get-MonitoredProcesses {
    param([array]$ProcessNames)
    
    $results = @()
    $processHash = @{}
    
    try {
        Write-Log "Starting process scan..." -Level Info
        
        # Get all processes once for efficiency
        $allProcesses = Get-Process -ErrorAction SilentlyContinue
        
        # Create hashtable for quick lookup
        foreach ($proc in $allProcesses) {
            if (-not $processHash.ContainsKey($proc.ProcessName)) {
                $processHash[$proc.ProcessName] = @()
            }
            $processHash[$proc.ProcessName] += $proc
        }
        
        # Check each monitored process
        foreach ($processName in $ProcessNames) {
            if ($processHash.ContainsKey($processName)) {
                foreach ($process in $processHash[$processName]) {
                    $details = Get-ProcessDetails -Process $process
                    if ($details) {
                        $results += $details
                        Write-Log "Found: $processName (PID: $($process.Id))" -Level Debug
                    }
                }
            }
            else {
                Write-Log "Not running: $processName" -Level Debug
            }
        }
        
        Write-Log "Process scan completed. Found $($results.Count) running processes" -Level Info
        return $results
    }
    catch {
        Write-Log "Error during process scan: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Start-ProcessMonitoring {
    try {
        Write-Log "Process Monitor Starting..." -Level Info
        Write-Log "Output Format: $OutputFormat" -Level Info
        
        # Load configuration
        $currentConfig = Load-Configuration -ConfigFilePath $ConfigFile
        
        # Get monitored processes
        $monitoredProcesses = Get-MonitoredProcesses -ProcessNames $currentConfig.ProcessNames
        
        # Format and output results
        Format-Output -ProcessResults $monitoredProcesses -Format $OutputFormat
        
        Write-Log "Process monitoring completed successfully" -Level Info
        
        # Return results for potential further processing
        return $monitoredProcesses
    }
    catch {
        Write-Log "Process monitoring failed: $($_.Exception.Message)" -Level Error
        throw
    }
}
#endregion

#region Main Execution
try {
    # Initialize logging
    if ($LogFile) {
        $logDir = Split-Path $LogFile -Parent
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        Write-Log "Logging to: $LogFile" -Level Info
    }
    
    # Start monitoring
    $results = Start-ProcessMonitoring
    
    # Exit with success code
    exit 0
}
catch {
    Write-Log "Script execution failed: $($_.Exception.Message)" -Level Error
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    
    # Exit with error code
    exit 1
}
finally {
    if (-not $Quiet) {
        Write-Log "Script execution completed" -Level Info
    }
}
#endregion