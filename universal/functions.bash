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
  if [ -n "$arrUrl" ] && [ -n "$arrApiKey" ]; then
    return
  fi

  if [ ! -f "/config/config.xml" ]; then
    log "ERROR :: /config/config.xml not found, unable to detect Arr connection details"
    return
  fi

  readConfigTag () {
    tag="$1"
    sed -n "s:.*<$tag>\(.*\)</$tag>.*:\1:p" /config/config.xml | head -n1
  }

  # Primary parser (xq+jq), fallback to XML tag extraction
  if command -v xq >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    arrUrlBase="$(xq < /config/config.xml 2>/dev/null | jq -r '.Config.UrlBase // empty' 2>/dev/null)"
    arrName="$(xq < /config/config.xml 2>/dev/null | jq -r '.Config.InstanceName // empty' 2>/dev/null)"
    arrApiKey="$(xq < /config/config.xml 2>/dev/null | jq -r '.Config.ApiKey // empty' 2>/dev/null)"
    arrPort="$(xq < /config/config.xml 2>/dev/null | jq -r '.Config.Port // empty' 2>/dev/null)"
  fi

  [ -z "$arrUrlBase" ] && arrUrlBase="$(readConfigTag UrlBase)"
  [ -z "$arrName" ] && arrName="$(readConfigTag InstanceName)"
  [ -z "$arrApiKey" ] && arrApiKey="$(readConfigTag ApiKey)"
  [ -z "$arrPort" ] && arrPort="$(readConfigTag Port)"

  arrUrlBase="$(echo "$arrUrlBase" | sed 's#^/*##; s#/*$##')"
  if [ -n "$arrUrlBase" ]; then
    arrUrlBase="/$arrUrlBase"
  fi

  if [ -z "$arrUrl" ] && [ -n "$arrPort" ]; then
    arrUrl="http://127.0.0.1:${arrPort}${arrUrlBase}"
  fi

  if [ -z "$arrName" ]; then
    arrName="ArrApp"
  fi
}

verifyApiAccess () {
  until false
  do
    arrApiTest=""
    arrApiVersion=""

    if [ -z "$arrUrl" ] || [ -z "$arrApiKey" ]; then
      getArrAppInfo
    fi

    if [ -z "$arrUrl" ] || [ -z "$arrApiKey" ]; then
      log "${arrName:-ArrApp} connection settings missing (arrUrl/arrApiKey), sleeping until valid response..."
      sleep 2
      continue
    fi

    # Check newest -> oldest and select the first valid API version
    for apiVersion in v5 v4 v3 v2 v1; do
      arrApiTest="$(curl -s "$arrUrl/api/$apiVersion/system/status?apikey=$arrApiKey" | jq -r '.instanceName // empty' 2>/dev/null)"
      if [ -z "$arrApiTest" ]; then
        arrApiTest="$(curl -s -H "X-Api-Key: $arrApiKey" "$arrUrl/api/$apiVersion/system/status" | jq -r '.instanceName // empty' 2>/dev/null)"
      fi
      if [ -n "$arrApiTest" ]; then
        arrApiVersion="$apiVersion"
        break
      fi
    done

    if [ -n "$arrApiTest" ] && [ -n "$arrApiVersion" ]; then
      log "Detected API version: $arrApiVersion ($arrApiTest)"
      break
    else
      log "${arrName:-ArrApp} is not ready, sleeping until valid response..."
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
