#----------------------------------------------------------------------------------------------
# EUM web.config update
# This script makes a change to the web.config file to properly insert the java script during the URL rewrite insertion
#----------------------------------------------------------------------------------------------


#----------------------------------------------------------------------------------------------
# Define variables
#----------------------------------------------------------------------------------------------
$file_name="web.config"
$web_config_file_location="C:\AppDynamics"
$find_text="&lt;head>*"
$find_test_replace="&lt;head&gt;"


#----------------------------------------------------------------------------------------------
# Verify existance of the file and then make the update
#----------------------------------------------------------------------------------------------
if(!(Test-Path -Path $web_config_file_location\$file_name)) {
	(Get-Content $web_config_file_location\$file_name -Raw) -replace $find_text, $find_test_replace | Set-Content $web_config_file_location\$file_name
	}