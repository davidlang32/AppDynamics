#!/bin/bash

if [ $# -ne 1 ]
  then
       echo "Invalid number of arguments supplied!!! Please enter the controller url while running the shell script e.g. ./extractcertscript.sh ces-controller.saas.appdynamics.com"
    exit 1
fi

controllerName=$1

echo "##########################################"
echo "Removing Exsisting pem and jks files."
echo "##########################################"
echo
rm *.pem
rm *.jks
sleep 3

echo "Checking if the controller is providing any certs or not."
echo "###########################################################"
echo
sleep 2

/opt/appdynamics/machine-agent/jre/bin/keytool -printcert -sslserver $controllerName

sleep 2

echo "###################################################################"
echo "Creating a pem file for all the certs provided by the controller."
echo "###################################################################"
echo
/opt/appdynamics/machine-agent/jre/bin/keytool -printcert -sslserver $controllerName -rfc >> controllercerts.pem
echo

sleep 3
echo " Creating multiple cert files."
csplit -z controllercerts.pem /-----BEGIN/ '{*}' --prefix='cert'
sleep 2
echo
for inputfile in cert*;
do
    mv $inputfile ${inputfile}.pem
    echo "##########################################"
    echo " Content of the cert file "${inputfile}.pem ": "
    echo "##########################################"
    echo
    cat ${inputfile}.pem
    echo "##########################################"
    echo
    sleep 5
    echo "importing cert: "${inputfile}.pem " into the truststore"
    echo
    /opt/appdynamics/machine-agent/jre/bin/keytool -import -noprompt -alias $inputfile -file ${inputfile}.pem -keystore truststore.jks -storepass changeit
    echo
    sleep 3
done

sleep 2
echo "##########################################"
echo "verifying the truststore.jsk file."
echo "##########################################"
sleep 3
/opt/appdynamics/machine-agent/jre/bin/keytool --list -keystore truststore.jks -storepass changeit

echo
sleep 3
echo "##########################################"
sleep 3;
/opt/appdynamics/machine-agent/jre/bin/keytool --list -keystore truststore.jks -storepass changeit -v
sleep 2
echo "##########################################"
echo "Telling the machine-agent to use the truststore.jsk file."
echo "##########################################"
sleep 3
sed -i "s/JAVA_OPTS -Xmx256m/JAVA_OPTS -Xmx256m -Djavax.net.ssl.trustStore=\${MACHINE_AGENT_HOME}\/conf\/truststore.jks -Djavax.net.ssl.trustStorePassword=changeit/" /opt/appdynamics/machine-agent/bin/machine-agent
sleep 2
echo "##########################################"
echo "Restarting the machine-agent service."
echo "##########################################"
systemctl stop appdynamics-machine-agent.service
systemctl start appdynamics-machine-agent.service
