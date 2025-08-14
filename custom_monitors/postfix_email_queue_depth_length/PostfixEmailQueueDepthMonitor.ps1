# Function to count the number of items in a queue
function Get-QueueCount {
	param (
		[string]$command
	)
	
	# Run the command and count the lines matching the criteria
	$count = Invoke-Expression $command | Select-String '^[A-F0-9]' | Measure-Object -lines
	$count = $count.lines
	
	# Output the result in the format for AppDynamics Controller
	Write-Output "name=Custom Metrics|Postfix|EmailQueueDepth,value=$count"
}

# Define the command to check the queue
# Replace this with the appropriate command for your Windows Setup
$queueCommand = "postqueue -p"

# Run the function and capture the Output
Get-QueueCount -command $queueCommand
