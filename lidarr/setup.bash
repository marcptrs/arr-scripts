#!/usr/bin/with-contenv bash
set -euo pipefail

scriptVersion="2.1.0"
SMA_PATH="/usr/local/sma"

setupReady="true"
if [ -f /config/setup_version.txt ]; then
  source /config/setup_version.txt
else
  setupReady="false"
fi

# Expected versions of all service scripts (bump these when service files change)
EXPECTED_setup="2.1.0"
EXPECTED_functions=""          # universal/functions.bash has no version header
EXPECTED_Audio="2.55"
EXPECTED_Video="4.2"
EXPECTED_AutoConfig="3.2"
EXPECTED_QueueCleaner=""       # tracked separately
EXPECTED_TidalVideoDownloader="2.1"
EXPECTED_AutoArtistAdder="2.4"
EXPECTED_UnmappedFilesCleaner="1.4"
EXPECTED_BeetsTagger="2.0"
EXPECTED_LyricExtractor="1.6"
EXPECTED_ArtworkExtractor="1.3"

if [ "${setupversion:-}" == "$EXPECTED_setup" ]; then
  if ! apk --no-cache list | grep installed | grep opus-tools | read; then
    setupReady="false"
  fi

  # Check each service file's embedded version
  serviceFiles="
/custom-services.d/Audio:EXPECTED_Audio
/custom-services.d/Video:EXPECTED_Video
/custom-services.d/AutoConfig:EXPECTED_AutoConfig
/custom-services.d/TidalVideoDownloader:EXPECTED_TidalVideoDownloader
/custom-services.d/AutoArtistAdder:EXPECTED_AutoArtistAdder
/custom-services.d/UnmappedFilesCleaner:EXPECTED_UnmappedFilesCleaner
/config/extended/BeetsTagger.bash:EXPECTED_BeetsTagger
/config/extended/LyricExtractor.bash:EXPECTED_LyricExtractor
/config/extended/ArtworkExtractor.bash:EXPECTED_ArtworkExtractor
/config/extended/functions:EXPECTED_functions
/config/extended/beets-config.yaml:EXPECTED_functions
/config/extended.conf:EXPECTED_functions
"

  while IFS=: read -r filePath varName; do
    [ -z "$filePath" ] && continue
    if [ ! -s "$filePath" ]; then
      echo "Setup check: missing required file $filePath"
      setupReady="false"
      continue
    fi
    # Check embedded version in service scripts
    expectedVersion="${!varName:-}"
    if [ -n "$expectedVersion" ]; then
      actualVersion="$(sed -n 's/.*scriptVersion="\([^"]*\)".*/\1/p' "$filePath" 2>/dev/null | head -n1)"
      if [ -n "$actualVersion" ] && [ "$actualVersion" != "$expectedVersion" ]; then
        echo "Setup check: $filePath version mismatch (expected $expectedVersion, got $actualVersion)"
        setupReady="false"
      fi
    fi
  done <<< "$serviceFiles"

  if ! python3 -c 'import colorama, yt_dlp, beets' >/dev/null 2>&1; then
    echo "Setup check: required python packages missing, re-running setup"
    setupReady="false"
  fi

  if [ "$setupReady" == "true" ]; then
    echo "Setup was previously completed, skipping..."
    exit
  fi
fi

echo "setupversion=$EXPECTED_setup" > /config/setup_version.txt

echo "*** install packages ***" && \
apk add -U --upgrade --no-cache \
  tidyhtml \
  musl-locales \
  musl-locales-lang \
  flac \
  jq \
  xq \
  git \
  gcc \
  ffmpeg \
  imagemagick \
  opus-tools \
  opustags \
  python3-dev \
  libc-dev \
  build-base \
  cmake \
  uv \
  parallel \
  nodejs \
  npm && \
echo "*** install freyr client ***" && \
apk add --no-cache -X http://dl-cdn.alpinelinux.org/alpine/edge/testing atomicparsley && \
npm install -g miraclx/freyr-js &&\
echo "*** install python packages ***" && \
uv pip install --system --upgrade --no-cache-dir --break-system-packages \
  jellyfish \
  beautifulsoup4 \
  "yt-dlp[default]" \
  beets \
  yq \
  pyxDamerauLevenshtein \
  pyacoustid \
  requests \
  colorama \
  python-telegram-bot \
  pylast \
  mutagen \
  r128gain \
  tidal-dl \
  deemix \
  langdetect \
  apprise || true

# Ensure runtime-critical python modules exist even if optional builds fail
uv pip install --system --upgrade --no-cache-dir --break-system-packages \
  "yt-dlp[default]" \
  pyxDamerauLevenshtein \
  colorama \
  requests \
  mutagen \
  python-telegram-bot \
  apprise \
  deemix

# Pre-install beets' core deps (pure Python, no build) for --no-deps fallback
uv pip install --system --break-system-packages \
  PyYAML \
  Jinja2 \
  Unidecode \
  musicbrainzngs \
  discogs-client \
  confuse \
  mediafile \
  packaging \
  munkres \
  lap \
  jellyfish \
  requests_ratelimiter \
  pyacoustid \
  pylast 2>/dev/null || true

# Install beets without numba/llvmlite (optional JIT dependency, needs LLVM to build)
uv pip install --system --break-system-packages beets --no-deps 2>/dev/null || true

# Upgrade yt-dlp to latest (YouTube changes frequently)
uv pip install --system --break-system-packages --upgrade "yt-dlp[default]" 2>/dev/null || yt-dlp -U 2>/dev/null || true

# Create yt-dlp config to use Node.js for EJS challenge solving (YouTube)
echo "Creating yt-dlp config for EJS Node.js runtime..."
mkdir -p /etc/yt-dlp
cat > /etc/yt-dlp/config.txt << 'EOF'
# Use Node.js for YouTube EJS challenge solving
--js-runtimes node
EOF
chmod 644 /etc/yt-dlp/config.txt


echo "************ setup SMA ************"
if [ -d "${SMA_PATH}"  ]; then
  rm -rf "${SMA_PATH}"
fi
echo "************ download repo ************" && \
git clone --depth 1 https://github.com/mdhiggins/sickbeard_mp4_automator.git ${SMA_PATH} && \
echo "************ create logging file ************" && \
touch ${SMA_PATH}/config/sma.log && \
chgrp users ${SMA_PATH}/config/sma.log && \
chmod g+w ${SMA_PATH}/config/sma.log && \
echo "************ install pip dependencies ************" && \
uv pip install --system --break-system-packages -r ${SMA_PATH}/setup/requirements.txt

mkdir -p /custom-services.d/python /config/extended

parallel ::: \
  'echo "Download QueueCleaner service..." && curl -sfL https://raw.githubusercontent.com/marcptrs/arr-scripts/main/universal/services/QueueCleaner -o /custom-services.d/QueueCleaner && echo "Done"' \
  'echo "Download AutoConfig service..." && curl -sfL https://raw.githubusercontent.com/marcptrs/arr-scripts/main/lidarr/AutoConfig.service.bash -o /custom-services.d/AutoConfig && echo "Done"' \
  'echo "Download Video service..." && curl -sfL https://raw.githubusercontent.com/marcptrs/arr-scripts/main/lidarr/Video.service.bash -o /custom-services.d/Video && echo "Done"' \
  'echo "Download Tidal Video Downloader service..." && curl -sfL https://raw.githubusercontent.com/marcptrs/arr-scripts/main/lidarr/TidalVideoDownloader.bash -o /custom-services.d/TidalVideoDownloader && echo "Done"' \
  'echo "Download Audio service..." && curl -sfL https://raw.githubusercontent.com/marcptrs/arr-scripts/main/lidarr/Audio.service.bash -o /custom-services.d/Audio && echo "Done"' \
  'echo "Download AutoArtistAdder service..." && curl -sfL https://raw.githubusercontent.com/marcptrs/arr-scripts/main/lidarr/AutoArtistAdder.bash -o /custom-services.d/AutoArtistAdder && echo "Done"' \
  'echo "Download UnmappedFilesCleaner service..." && curl -sfL https://raw.githubusercontent.com/marcptrs/arr-scripts/main/lidarr/UnmappedFilesCleaner.bash -o /custom-services.d/UnmappedFilesCleaner && echo "Done"' \
  'echo "Download ARLChecker service..." && curl -sfL https://raw.githubusercontent.com/marcptrs/arr-scripts/main/lidarr/python/ARLChecker.py -o /custom-services.d/python/ARLChecker.py && curl -sfL https://raw.githubusercontent.com/marcptrs/arr-scripts/main/lidarr/ARLChecker -o /custom-services.d/ARLChecker && echo "Done"' \
  'echo "Download Script Functions..." && curl -sfL https://raw.githubusercontent.com/marcptrs/arr-scripts/main/universal/functions.bash -o /config/extended/functions && echo "Done"' \
  'echo "Download PlexNotify script..." && curl -sfL https://raw.githubusercontent.com/marcptrs/arr-scripts/main/lidarr/PlexNotify.bash -o /config/extended/PlexNotify.bash  && echo "Done"' \
  'echo "Download SMA config..." && curl -sfL https://raw.githubusercontent.com/marcptrs/arr-scripts/main/lidarr/sma.ini -o /config/extended/sma.ini  && echo "Done"' \
  'echo "Download LyricExtractor script..." && curl -sfL https://raw.githubusercontent.com/marcptrs/arr-scripts/main/lidarr/LyricExtractor.bash -o /config/extended/LyricExtractor.bash && echo "Done"' \
  'echo "Download ArtworkExtractor script..." && curl -sfL https://raw.githubusercontent.com/marcptrs/arr-scripts/main/lidarr/ArtworkExtractor.bash -o /config/extended/ArtworkExtractor.bash && echo "Done"' \
  'echo "Download Beets Tagger script..." && curl -sfL https://raw.githubusercontent.com/marcptrs/arr-scripts/main/lidarr/BeetsTagger.bash -o /config/extended/BeetsTagger.bash && echo "Done"'


if [ ! -f /config/extended/beets-config.yaml ]; then
	echo "Download Beets config..."
	curl -sfL "https://raw.githubusercontent.com/marcptrs/arr-scripts/main/lidarr/beets-config.yaml" -o /config/extended/beets-config.yaml
	echo "Done"
fi

if [ ! -f /config/extended/beets-config-lidarr.yaml ]; then
	echo "Download Beets lidarr config..."
	curl -sfL "https://raw.githubusercontent.com/marcptrs/arr-scripts/main/lidarr/beets-config-lidarr.yaml" -o /config/extended/beets-config-lidarr.yaml
	echo "Done"
fi

if [ ! -f /config/extended/deemix_config.json ]; then
  echo "Download Deemix config..."
  curl -sfL "https://raw.githubusercontent.com/marcptrs/arr-scripts/main/lidarr/deemix_config.json" -o /config/extended/deemix_config.json
  echo "Done"
fi

if [ ! -f /config/extended/tidal-dl.json ]; then
  echo "Download Tidal config..."
  curl -sfL "https://raw.githubusercontent.com/marcptrs/arr-scripts/main/lidarr/tidal-dl.json" -o /config/extended/tidal-dl.json
  echo "Done"
fi

if [ ! -f /config/extended/beets-genre-whitelist.txt ]; then
	echo "Download beets-genre-whitelist.txt..."
	curl -sfL https://raw.githubusercontent.com/marcptrs/arr-scripts/main/lidarr/beets-genre-whitelist.txt -o /config/extended/beets-genre-whitelist.txt
	echo "Done"
fi

if [ ! -f /config/extended.conf ]; then
	echo "Download Extended config..."
	curl -sfL https://raw.githubusercontent.com/marcptrs/arr-scripts/main/lidarr/extended.conf -o /config/extended.conf
	chmod 777 /config/extended.conf
	echo "Done"
fi

chmod 777 -R /config/extended
chmod 777 -R /root

if [ -f /custom-services.d/scripts_init.bash ]; then
   # user misconfiguration detected, sleeping...
   sleep infinity
fi
exit
