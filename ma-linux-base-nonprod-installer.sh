#! /bin/bash
#----------------------------------------------------------------------------------------------
# Environment Settings
#----------------------------------------------------------------------------------------------
hostname=$HOSTNAME
hs=${HOSTNAME%%.*}
user=$(whoami)
machine_agent_user='root'
BASEInstallDir='/tmp'

#----------------------------------------------------------------------------------------------
# Application Team Settings
#----------------------------------------------------------------------------------------------
applicationname="Application"
tiername="App"
nodename=$hs

#----------------------------------------------------------------------------------------------
# Controller Settings
#----------------------------------------------------------------------------------------------
controllerhost='delteknonprod.saas.appdynamics.com'
controllerport='443'
controllerssl='true'
orchestration='false'
uniquehostid=$hs
accountaccesskey='7p0cmyv3fic2'
accountname='delteknonprod'
sim='true'
issapmachine=''
machinepath=''

#----------------------------------------------------------------------------------------------
# Matching criteria for default values on controller-info.xml file
#----------------------------------------------------------------------------------------------
controller_host_match="<controller-host>"
controller_port_match="<controller-port>"
controller_ssl_enabled_match="<controller-ssl-enabled>false"
enable_orchestration_match="<enable-orchestration>false"
unique_host_id_match="<unique-host-id>"
account_access_key_match="<account-access-key>"
account_name_match="<account-name>"
sim_enabled_match="<sim-enabled>false"
is_sap_machine_match="<is-sap-machine>"
machine_path_match="<machine-path>"
insert_config_key="<\/unique-host-id>"

#----------------------------------------------------------------------------------------------
# Modifying criteria for default values on controller-info.xml file
#----------------------------------------------------------------------------------------------
controller_host='<controller-host>'
controller_port='<controller-port>'
controller_ssl_enabled='<controller-ssl-enabled>'
enable_orchestration='<enable-orchestration>'
unique_host_id='<unique-host-id>'
account_access_key='<account-access-key>'
account_name='<account-name>'
sim_enabled='<sim-enabled>'
is_sap_machine='<is-sap-machine>'
machine_path='<machine-path>'
application_name_start="<application-name>"
application_name_end="<\/application-name>"
tier_name_start="<tier-name>"
tier_name_end="<\/tier-name>"
node_name_start="<node-name>"
node_name_end="<\/node-name>"

#----------------------------------------------------------------------------------------------
# Controller Settings
#----------------------------------------------------------------------------------------------
controllerhost=$controller_host$controllerhost
controllerport=$controller_port$controllerport
controllerssl=$controller_ssl_enabled$controllerssl
orchestration=$enable_orchestration$orchestration
uniquehostid=$unique_host_id$uniquehostid
accountaccesskey=$account_access_key$accountaccesskey
accountname=$account_name$accountname
sim=$sim_enabled$sim
issapmachine=$is_sap_machine$issapmachine
machinepath=$machine_path$machinepath
applicationname=$application_name_start$applicationname$application_name_end
tiername=$tier_name_start$tiername$tier_name_end
nodename=$node_name_start$nodename$node_name_end


echo " ______________________________________________________________________________________________________________________"
echo "|                                                                                                                      |"
echo "|                   check user name and see if AppDynamics machine-agent exists                                        |"
printf "|______________________________________________________________________________________________________________________|\n\n"
if [ $user != $machine_agent_user ]
then
    printf "This file must be run as: %s\n" "$machine_agent_user"
    printf "Please change to the %s user and run this file again.\n" "$machine_agent_user"
    exit 0
        fi

if [ -d "/opt/appdynamics/" ]; then
        if [ -d "/opt/appdynamics/machine-agent" ];then
                printf "Removing current AppDynamics Machine agent.\n"
                systemctl stop appdynamics-machine-agent
                rm -r /opt/appdynamics/machine-agent/ -f
        fi
else
    printf "/opt/appdynamics does not exists.\nNow installing the AppDynamics machine-agent.\n"
    mkdir /opt/appdynamics
fi

echo " ______________________________________________________________________________________________________________________"
echo "|                                                                                                                      |"
echo "|               Unpack the agent into the /opt/appdynamics/machine-agent folder                                        |"
printf "|______________________________________________________________________________________________________________________|\n\n"
mv $BASEInstallDir/machineagent-bundle* $BASEInstallDir/machine-agent.zip
chown $user:$user machine-agent.zip
unzip $BASEInstallDir/machine-agent.zip -d /opt/appdynamics/machine-agent


echo " ______________________________________________________________________________________________________________________"
echo "|                                                                                                                      |"
echo "|                                  Configure the AppDynamics Machine Agent!                                            |"
printf "|______________________________________________________________________________________________________________________|\n\n"
sed -i "s/$controller_host_match/$controllerhost/" /opt/appdynamics/machine-agent/conf/controller-info.xml
sed -i "s/$controller_port_match/$controllerport/" /opt/appdynamics/machine-agent/conf/controller-info.xml
sed -i "s/$controller_ssl_enabled_match/$controllerssl/" /opt/appdynamics/machine-agent/conf/controller-info.xml
sed -i "s/$enable_orchestration_match/$orchestration/" /opt/appdynamics/machine-agent/conf/controller-info.xml
sed -i "s/$unique_host_id_match/$uniquehostid/" /opt/appdynamics/machine-agent/conf/controller-info.xml
sed -i "s/$account_access_key_match/$accountaccesskey/" /opt/appdynamics/machine-agent/conf/controller-info.xml
sed -i "s/$account_name_match/$accountname/" /opt/appdynamics/machine-agent/conf/controller-info.xml
sed -i "s/$sim_enabled_match/$sim/" /opt/appdynamics/machine-agent/conf/controller-info.xml
sed -i "s/$is_sap_machine_match/$issapmachine/" /opt/appdynamics/machine-agent/conf/controller-info.xml
sed -i "s/$machine_path_match/$machinepath/" /opt/appdynamics/machine-agent/conf/controller-info.xml
sed -i "s/$insert_config_key/$insert_config_key\\n    $applicationname/" /opt/appdynamics/machine-agent/conf/controller-info.xml
sed -i "s/$application_name_end/$application_name_end\\n    $tiername/" /opt/appdynamics/machine-agent/conf/controller-info.xml
sed -i "s/$tier_name_end/$tier_name_end\\n    $nodename/" /opt/appdynamics/machine-agent/conf/controller-info.xml

echo " ______________________________________________________________________________________________________________________"
echo "|                                                                                                                      |"
echo "|                              Enabling systemd for the machine agent service.                                         |"
printf "|______________________________________________________________________________________________________________________|\n\n"
chmod 776 -R /opt/appdynamics/machine-agent
sed -i "s/User=appdynamics-machine-agent/User=$machine_agent_user/" /opt/appdynamics/machine-agent/etc/systemd/system/appdynamics-machine-agent.service
sed -i "s/Environment=MACHINE_AGENT_USER=appdynamics-machine-agent/Environment=MACHINE_AGENT_USER=$machine_agent_user/" /opt/appdynamics/machine-agent/etc/systemd/system/appdynamics-machine-agent.service
cp /opt/appdynamics/machine-agent/etc/systemd/system/appdynamics-machine-agent.service /etc/systemd/system -f
systemctl daemon-reload
systemctl enable appdynamics-machine-agent.service
systemctl start appdynamics-machine-agent.service

echo " ______________________________________________________________________________________________________________________"
echo "|                                                                                                                      |"
echo "|                                                   COMPLETE...                                                        |"
printf "|______________________________________________________________________________________________________________________|\n\n"