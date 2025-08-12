#!/bin/bash
#Check if Wookbook service is running
#
#Function to check the status of a service

check_service_status() {
	local service_name=$1
	if systemctl is-active --quiet "$service_name"; then
		echo "name=Custom Metrics|CheckServicesMonitor|$service,value=1"
#	else
#		echo "name=Custom Metrics|CheckServicesMonitor|$service,value=0"
	fi
}

# List of services to check
services=(
	"appdynamics-machine-agent"
    "splunk"
    "besclient"
    "falcon-sensor"
    "puppet"
    "sophos-spl"
    "puppetserver"
    "sendmail"
    "hdp"
)

# Iterate over the list of services and chekc their status
for service in "${services[@]}"; do
        check_service_status "$service"
done
