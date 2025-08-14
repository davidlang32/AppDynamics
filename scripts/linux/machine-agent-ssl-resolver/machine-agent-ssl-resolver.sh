#!/usr/bin/env bash
set -euo pipefail

echo "#########################################################"
echo "# Discovering Machine Agent and Controller Information… #"
echo "#########################################################"
echo

# ========================================
# SECTION 1: DISCOVER MACHINE AGENT
# ========================================
# Find the running Machine Agent process
PID=$(pgrep -f '[m]achineagent.jar' || true)
if [[ -z "$PID" ]]; then
  echo "ERROR: Could not find a running machineagent.jar process." >&2
  exit 1
fi

# Extract the JAR path from the process command line and resolve installation directory
JAR_PATH=$(tr '\0' ' ' < /proc/$PID/cmdline | sed -n 's/.*-jar \([^ ]*machineagent\.jar\).*/\1/p')
JAR_PATH=$(readlink -f "$JAR_PATH")
MACHINE_AGENT_HOME=$(dirname "$JAR_PATH")
echo "Discovered MACHINE_AGENT_HOME: $MACHINE_AGENT_HOME"

# ========================================
# SECTION 2: EXTRACT CONTROLLER CONFIG
# ========================================
# Parse controller hostname from XML configuration file
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

# Verify keytool is available in the agent's JRE
JRE_BIN_KEYTOOL="$MACHINE_AGENT_HOME/jre/bin/keytool"
if [[ ! -x "$JRE_BIN_KEYTOOL" ]]; then
  echo "ERROR: Cannot find keytool at $JRE_BIN_KEYTOOL" >&2
  exit 1
fi

# Change to agent directory for certificate operations
cd "$MACHINE_AGENT_HOME"

# ========================================
# SECTION 3: CERTIFICATE CLEANUP
# ========================================
echo "##########################################"
echo "Removing existing PEM and JKS files."
echo "##########################################"
rm -f *.pem *.jks
sleep 2

# ========================================
# SECTION 4: DOWNLOAD CERTIFICATES
# ========================================
# Test SSL connectivity and display certificate chain
echo "Checking if the controller is providing any certs."
echo "###########################################################"
"$JRE_BIN_KEYTOOL" -printcert -sslserver "$controllerName"
sleep 2

# Download the complete certificate chain in PEM format
echo "Creating a PEM file for all the certs provided by the controller."
echo "###################################################################"
"$JRE_BIN_KEYTOOL" -printcert -sslserver "$controllerName" -rfc > controllercerts.pem
sleep 2

# ========================================
# SECTION 5: PROCESS CERTIFICATE CHAIN
# ========================================
# Split the combined PEM file into individual certificate files
echo "Splitting PEM into individual cert files..."
csplit -z controllercerts.pem /-----BEGIN/ '{*}' --prefix='cert'
sleep 2

# ========================================
# SECTION 6: CREATE TRUSTSTORE
# ========================================
# Import each certificate into a new Java KeyStore (truststore)
echo "Importing certs into truststore.jks"
for inputfile in cert*; do
  mv "$inputfile" "${inputfile}.pem"
  echo "Importing ${inputfile}.pem..."
  "$JRE_BIN_KEYTOOL" -import -noprompt -alias "$inputfile" -file "${inputfile}.pem" -keystore truststore.jks -storepass changeit
  sleep 1
done

# Deploy truststore to agent configuration directory
mv truststore.jks "$MACHINE_AGENT_HOME/conf/"
sleep 1

# Verify the truststore was created successfully
echo "##########################################"
echo "Verifying truststore.jks contents..."
"$JRE_BIN_KEYTOOL" --list -keystore "$MACHINE_AGENT_HOME/conf/truststore.jks" -storepass changeit
echo "##########################################"
sleep 2

# ========================================
# SECTION 7: UPDATE AGENT CONFIGURATION
# ========================================
# Configure the Machine Agent startup script to use the new truststore
AGENT_SCRIPT="$MACHINE_AGENT_HOME/bin/machine-agent"
TRUSTSTORE_FLAG="-Djavax.net.ssl.trustStore=\${MACHINE_AGENT_HOME}/conf/truststore.jks -Djavax.net.ssl.trustStorePassword=changeit"

# Only add truststore configuration if not already present
if ! grep -q "javax.net.ssl.trustStore" "$AGENT_SCRIPT"; then
  echo "Injecting truststore config into machine-agent script..."
  sed -i "s|\(JAVA_OPTS.*-Xmx256m\)|\1 $TRUSTSTORE_FLAG|" "$AGENT_SCRIPT"
else
  echo "Truststore config already present in machine-agent script."
fi

# ========================================
# SECTION 8: RESTART AGENT SERVICE
# ========================================
echo "##########################################"
echo "Restarting the Machine Agent..."
echo "##########################################"
systemctl stop appdynamics-machine-agent.service
sleep 2
systemctl start appdynamics-machine-agent.service
sleep 2

echo "✅ Done. Machine Agent is now using the updated truststore."