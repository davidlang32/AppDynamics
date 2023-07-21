#! /bin/bash
#----------------------------------------------------------------------------------------------
# Applicaton Team Settings - default settings are initially set
#  - If not default values have been altered then just change the "Default Extension Settings for matching" to the current settings
#  - Here are the default values:
#         * maxNumberVolumes=5
#         * maxNumberNetworks=5
#         * maxNumberMonitoredClasses=20
#----------------------------------------------------------------------------------------------
maxNumberVolumes=25
maxNumberNetworks=5
maxNumberMonitoredClasses=20

#----------------------------------------------------------------------------------------------
# Environment Settings
#----------------------------------------------------------------------------------------------
user=$(whoami)
machine_agent_user='root'
BASEAppDDir='/opt/appdynamics/machine-agent'
extensionFile=$BASEAppDDir"/extensions/ServerMonitoring/conf/ServerMonitoring.yml"

#----------------------------------------------------------------------------------------------
# Default Extension Settings for matching
#----------------------------------------------------------------------------------------------
ext_maxNumberVolumes_match="maxNumberVolumes           : 5"
ext_maxNumberNetworks_match="maxNumberNetworks            : 5"
ext_maxNumberMonitoredClasses_match="maxNumberMonitoredClasses        : 20"

#----------------------------------------------------------------------------------------------
# Stripping out the default value
#----------------------------------------------------------------------------------------------
ext_maxNumberVolumes_replace="maxNumberVolumes           : "
ext_maxNumberNetworks_replace="maxNumberNetworks            : "
ext_maxNumberMonitoredClasses_replace="maxNumberMonitoredClasses        : "

#----------------------------------------------------------------------------------------------
# New settings
#----------------------------------------------------------------------------------------------
maxNumberVolumes=$ext_maxNumberVolumes_replace$maxNumberVolumes
maxNumberNetworks=$ext_maxNumberNetworks_replace$maxNumberNetworks
maxNumberMonitoredClasses=$ext_maxNumberMonitoredClasses_replace$maxNumberMonitoredClasses

echo " ______________________________________________________________________________________________________________________"
echo "|                                                                                                                      |"
echo "|                   check user name is the correct user to make the changes                                            |"
printf "|______________________________________________________________________________________________________________________|\n\n"
if [ $user != $machine_agent_user ]
then
    printf "This file must be run as: %s\n" "$machine_agent_user"
    printf "Please change to the %s user and run this file again.\n" "$machine_agent_user"
    exit 0
        fi
		
echo " ______________________________________________________________________________________________________________________"
echo "|                                                                                                                      |"
echo "|                   Applying changes to the Machine Agent Extensions                                                   |"
printf "|______________________________________________________________________________________________________________________|\n\n"
sed -i "s/$ext_maxNumberVolumes_match/$maxNumberVolumes/" $extensionFile
sed -i "s/$ext_maxNumberNetworks_match/$maxNumberNetworks/" $extensionFile
sed -i "s/$ext_maxNumberMonitoredClasses_match/$maxNumberMonitoredClasses/" $extensionFile

#----------------------------------------------------------------------------------------------
# Restart the machine agent to commmit the changes
#----------------------------------------------------------------------------------------------
systemctl start appdynamics-machine-agent.service

echo " ______________________________________________________________________________________________________________________"
echo "|                                                                                                                      |"
echo "|                                                   COMPLETE...                                                        |"
printf "|______________________________________________________________________________________________________________________|\n\n"
