# Function to check the status of a service
function Check-ServiceStatus {
    param (
        [string]$ServiceName
    )
    
    # Check if the service exists and is running
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq 'Running') {
        Write-Output "name=Custom Metrics|CheckServicesMonitor|$ServiceName,value=1"
    }
}

# List of services to check
$services = @(
    "appdynamics-machine-agent",
    "AjeraCRMService",
    "AjeraNotificationsService",
    "vstsagent.tfs.Vantagepoint-DeltekVantagepointCloud.*",
    "DeltekVantagepointProcessServer",
    "DeltekVantagepointProcessServer*",
    "DeltekVisionProcessServer",
    "DeltekVisionProcessServer*",
    "SQLServerReportingServices",
    "tabadminagent*",
    "tabadmincontroller*",
    "tabsvc",
    "clientfileservice*",
    "appzookeeper*",
    "tablicsrv",
    "tabsvc*",
    "MSSQLSERVER",
    "MSSQL*",
    "SQLSERVERAGENT",
    "SQLAgent*",
    "MSSQLServerOLAPService",
    "SQLBrowser",
    "SQLWriter"
)

# Iterate over the list of services and check their status
foreach ($service in $services) {
    Check-ServiceStatus -ServiceName $service
}
