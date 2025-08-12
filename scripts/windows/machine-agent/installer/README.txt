How to use the script:

Option 1: Direct Script Modification (Simplest)
Option 2: External Configuration File (Recommended)
Option 3: PowerShell Configuration File (Alternative)

How to Use Each Option:
Option 1: Direct Script Modification
powershell# Just run the script after editing the config section
.\Install-AppDynamicsMachineAgent.ps1

Option 2: JSON Configuration File
powershell# Save the JSON config as 'appdconfig.json' and run:
.\Install-AppDynamicsMachineAgent.ps1 -ConfigFile "appdconfig.json"

Option 3: PowerShell Configuration File
If you want to use a PowerShell config file, you'd need to modify the script slightly to use Import-PowerShellDataFile:
powershell# Save as 'appdconfig.psd1' and run:
.\Install-AppDynamicsMachineAgent.ps1 -ConfigFile "appdconfig.psd1"



Recommended Approach:
I recommend Option 2 (JSON Configuration File) because:

Separation of Concerns: Configuration is separate from code
Version Control: You can version control configs separately
Environment-Specific: Different configs for dev/test/prod
Security: Sensitive data like access keys aren't in the script
Easy to Read: JSON is human-readable and widely supported

Sample Usage Workflow:

Create your configuration file (appdconfig.json):

json{
    "ApplicationName": "MyWebApp",
    "TierName": "WebTier",
    "ControllerHost": "mycompany.saas.appdynamics.com",
    "AccountAccessKey": "your-secret-key",
    "AccountName": "your-account"
}

Run the installer:

powershell.\Install-AppDynamicsMachineAgent.ps1 -ConfigFile "appdconfig.json"

For multiple environments, create separate config files:
appdconfig-dev.json
appdconfig-test.json
appdconfig-prod.json



This approach makes the script much more maintainable and secure!