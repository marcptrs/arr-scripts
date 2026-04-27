log () {
  m_time=`date "+%F %T"`
  echo $m_time" :: $scriptName :: $scriptVersion :: "$1
  echo $m_time" :: $scriptName :: $scriptVersion :: "$1 >> "/config/logs/$logFileName"
}

logfileSetup () {
  logFileName="$scriptName-$(date +"%Y_%m_%d_%I_%M_%p").txt"

  # Keep only the last 2 log files for 3 active log files at any given time...
  rm -f $(ls -1t /config/logs/$scriptName-* | tail -n +2)
  # delete log files older than 5 days
  find "/config/logs" -type f -iname "$scriptName-*.txt" -mtime +5 -delete
  
  if [ ! -f "/config/logs/$logFileName" ]; then
    echo "" > "/config/logs/$logFileName"
    chmod 666 "/config/logs/$logFileName"
  fi
}

getArrAppInfo () {
  # Get Arr App information
  if [ -z "$arrUrl" ] || [ -z "$arrApiKey" ]; then
    arrUrlBase="$(cat /config/config.xml | xq | jq -r .Config.UrlBase)"
    if [ "$arrUrlBase" == "null" ]; then
      arrUrlBase=""
    else
      arrUrlBase="/$(echo "$arrUrlBase" | sed "s/\///")"
    fi
    arrName="$(cat /config/config.xml | xq | jq -r .Config.InstanceName)"
    arrApiKey="$(cat /config/config.xml | xq | jq -r .Config.ApiKey)"
    arrPort="$(cat /config/config.xml | xq | jq -r .Config.Port)"
    arrUrl="http://127.0.0.1:${arrPort}${arrUrlBase}"
  fi
}

verifyApiAccess () {
  until false
  do
    arrApiTest=""
    arrApiVersion=""

    # Check newest -> oldest and select the first valid API version
    for apiVersion in v5 v4 v3 v2 v1; do
      arrApiTest="$(curl -s "$arrUrl/api/$apiVersion/system/status?apikey=$arrApiKey" | jq -r '.instanceName // empty' 2>/dev/null)"
      if [ -n "$arrApiTest" ]; then
        arrApiVersion="$apiVersion"
        break
      fi
    done

    if [ -n "$arrApiTest" ] && [ -n "$arrApiVersion" ]; then
      log "Detected API version: $arrApiVersion"
      break
    else
      log "$arrName is not ready, sleeping until valid response..."
      sleep 1
    fi
  done
}

ConfValidationCheck () {
  if [ ! -f "/config/extended.conf" ]; then
    log "ERROR :: \"extended.conf\" file is missing..."
    log "ERROR :: Download the extended.conf config file and place it into \"/config\" folder..."
    log "ERROR :: Exiting..."
    exit
  fi
  if [ -z "$enableAutoConfig" ]; then
    log "ERROR :: \"extended.conf\" file is unreadable..."
    log "ERROR :: Likely caused by editing with a non unix/linux compatible editor, to fix, replace the file with a valid one or correct the line endings..."
    log "ERROR :: Exiting..."
    exit
  fi
}

logfileSetup
ConfValidationCheck
