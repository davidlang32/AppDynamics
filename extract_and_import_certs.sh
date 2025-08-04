#!/usr/bin/env bash
set -euo pipefail

echo "#########################################################"
echo "# Discovering Machine Agent and Controller Information… #"
echo "#########################################################"
echo

# 1. Find the Machine Agent PID
PID=$(pgrep -f '[m]achineagent.jar' || true)
if [[ -z "$PID" ]]; then
  echo "ERROR: Could not find a running machineagent.jar process." >&2
  exit 1
fi

# 2. Locate machineagent.jar
JAR_PATH=$(tr '\0' ' ' < /proc/$PID/cmdline | sed -n 's/.*-jar \([^ ]*machineagent\.jar\).*/\1/p')
JAR_PATH=$(readlink -f "$JAR_PATH")
MACHINE_AGENT_HOME=$(dirname "$JAR_PATH")
echo "Discovered MACHINE_AGENT_HOME: $MACHINE_AGENT_HOME"

# 3. Extract controller info from XML
CONFIG_FILE="$MACHINE_AGENT_HOME/conf/controller-info.xml"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: Cannot find controller-info.xml at $CONFIG_FILE" >&2
  exit 1
fi

controllerName=$(grep -oPm1 '(?<=<controller-host>)[^<]+' "$CONFIG_FILE")
if [[ -z "$controllerName" ]]; then
  echo "ERROR: Could not extract controller host from $CONFIG_FILE" >&2
  exit 1
fi
echo "Discovered Controller Host: $controllerName"
echo

JRE_BIN_KEYTOOL="$MACHINE_AGENT_HOME/jre/bin/keytool"
if [[ ! -x "$JRE_BIN_KEYTOOL" ]]; then
  echo "ERROR: Cannot find keytool at $JRE_BIN_KEYTOOL" >&2
  exit 1
fi

cd "$MACHINE_AGENT_HOME"

echo "##########################################"
echo "Removing existing PEM and JKS files."
echo "##########################################"
rm -f *.pem *.jks
sleep 2

echo "Checking if the controller is providing any certs."
echo "###########################################################"
"$JRE_BIN_KEYTOOL" -printcert -sslserver "$controllerName"
sleep 2

echo "Creating a PEM file for all the certs provided by the controller."
echo "###################################################################"
"$JRE_BIN_KEYTOOL" -printcert -sslserver "$controllerName" -rfc > controllercerts.pem
sleep 2

echo "Splitting PEM into individual cert files..."
csplit -z controllercerts.pem /-----BEGIN/ '{*}' --prefix='cert'
sleep 2

echo "Importing certs into truststore.jks"
for inputfile in cert*; do
  mv "$inputfile" "${inputfile}.pem"
  echo "Importing ${inputfile}.pem..."
  "$JRE_BIN_KEYTOOL" -import -noprompt -alias "$inputfile" -file "${inputfile}.pem" -keystore truststore.jks -storepass changeit
  sleep 1
done

# Move truststore into conf directory
mv truststore.jks "$MACHINE_AGENT_HOME/conf/"
sleep 1

echo "##########################################"
echo "Verifying truststore.jks contents..."
"$JRE_BIN_KEYTOOL" --list -keystore "$MACHINE_AGENT_HOME/conf/truststore.jks" -storepass changeit
echo "##########################################"
sleep 2

# Update machine-agent startup script to use truststore if not already present
AGENT_SCRIPT="$MACHINE_AGENT_HOME/bin/machine-agent"
TRUSTSTORE_FLAG="-Djavax.net.ssl.trustStore=\${MACHINE_AGENT_HOME}/conf/truststore.jks -Djavax.net.ssl.trustStorePassword=changeit"

if ! grep -q "javax.net.ssl.trustStore" "$AGENT_SCRIPT"; then
  echo "Injecting truststore config into machine-agent script..."
  sed -i "s|\(JAVA_OPTS.*-Xmx256m\)|\1 $TRUSTSTORE_FLAG|" "$AGENT_SCRIPT"
else
  echo "Truststore config already present in machine-agent script."
fi

echo "##########################################"
echo "Restarting the Machine Agent..."
echo "##########################################"
systemctl stop appdynamics-machine-agent.service
sleep 2
systemctl start appdynamics-machine-agent.service
sleep 2

echo "✅ Done. Machine Agent is now using the updated truststore."
