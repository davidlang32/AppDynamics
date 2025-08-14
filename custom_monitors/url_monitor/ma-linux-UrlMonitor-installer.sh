#----------------------------------------------------------------------------------------------
# 1. Update the application value below - under "URLMonitor Custom Settings"
# 2. Copy the ma-linux-UrlMonitor-installer.sh and UrlMonitor_template.zip file to the local tmp directory (update BASEInstallDir if you want to use something other than /tmp)
# 3. Change to root
# 4. Assign installer to root and modify the ma-linux-UrlMonitor-installer.sh to 776
#		chown root:root /tmp UrlMonitor-installer.sh
#		chmod 776 /tmp/UrlMonitor-installer.sh
# 5. Execute the file:
#		/tmp/UrlMonitor-installer.sh
# NOTE: The variable api below requires the \ "escape character" because it's being used in a sed function
#----------------------------------------------------------------------------------------------


#----------------------------------------------------------------------------------------------
# Environment Settings
#----------------------------------------------------------------------------------------------
hostname=$HOSTNAME
hs=${HOSTNAME%%.*}
user=$(whoami)
machine_agent_user='root'
BASEInstallDir='/tmp'
destinationDir='/opt/appdynamics/machine-agent/monitors'

#----------------------------------------------------------------------------------------------
# URLMonitor Custom Settings
#----------------------------------------------------------------------------------------------
nodename=$hs
applicationname="applicationname"
port="8443"
apiname="healthcheck"
api="\/api\/healthcheck"

echo " ______________________________________________________________________________________________________________________"
echo "|                                                                                                                      |"
echo "|                            Verify that you're using the correct user account                                         |"
printf "|______________________________________________________________________________________________________________________|\n\n"
if [ $user != $machine_agent_user ]
then
    printf "This file must be run as: %s\n" "$machine_agent_user"
    printf "Please change to the %s user and run this file again.\n" "$machine_agent_user"
    exit 0
fi

echo " ______________________________________________________________________________________________________________________"
echo "|                                                                                                                       |"
echo "|                   Unzip the file to the destination location, change owner, change permissions                         |"
printf "|______________________________________________________________________________________________________________________|\n\n"

# Ensure the destination directory exists
mkdir -p $destinationDir"/UrlMonitor"$applicationname

# Unzip the file to the destination directory
unzip $BASEInstallDir"/UrlMonitor_template.zip" -d $destinationDir"/UrlMonitor"$applicationname

# Change owner and permissions
chown $user:$user -R $destinationDir"/UrlMonitor"$applicationname
chmod 776 -R $destinationDir"/UrlMonitor"$applicationname

echo " ______________________________________________________________________________________________________________________"
echo "|                                                                                                                      |"
echo "|                                         Configure the UrlMonitor                                                     |"
printf "|______________________________________________________________________________________________________________________|\n\n"

# Update configuration file
sed -i "s/<applicationname>/$applicationname/" "$destinationDir/UrlMonitor$applicationname/config.yml"
sed -i "s/<nodename>/$nodename/" "$destinationDir/UrlMonitor$applicationname/config.yml"
sed -i "s/<port>/$port/" "$destinationDir/UrlMonitor$applicationname/config.yml"
sed -i "s/<apiname>/$apiname/" "$destinationDir/UrlMonitor$applicationname/config.yml"
sed -i "s/<api>/$api/" "$destinationDir/UrlMonitor$applicationname/config.yml"

# Restart the service
systemctl restart appdynamics-machine-agent.service

echo " ______________________________________________________________________________________________________________________"
echo "|                                                                                                                      |"
echo "|                                                   COMPLETE...                                                        |"
printf "|______________________________________________________________________________________________________________________|\n\n"

