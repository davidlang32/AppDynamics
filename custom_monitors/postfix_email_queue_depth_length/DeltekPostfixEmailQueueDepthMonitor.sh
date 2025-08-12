#!/bin/bash

# Function to count the number of emails in the postfix queue
count_postfix_queue() {
	local count
	count=$(postqueue -p | grep -c '^[A-F0-9]')
	echo "name=Custom Metrics|Postfix|EmailQueueDepth,value=$count"
}

# Run the function and capture the output
count_postfix_queue