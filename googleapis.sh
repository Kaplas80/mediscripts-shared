#!/usr/bin/env sh

###################################################################################
# Google Endpoint Scanner (GES)
# - Use this script to blacklist GDrive endpoints that have slow connections
# - This is done by adding one or more Google servers available at the time of
#   testing to this host's /etc/hosts file.
# - Run this script as a cronjob or any other way of automation that you feel
#   comfortable with.
###################################################################################
# Installation and usage:
# - install 'dig' and 'git';
# - in a dir of your choice, clone the repo that contains this script:
#   'git clone https://github.com/cgomesu/mediscripts-shared.git'
#   'cd mediscripts-shared/'
# - go over the non-default variables at the top of the script (e.g., REMOTE,
#   REMOTE_TEST_DIR, REMOTE_TEST_FILE, etc.) and edit them to your liking:
#   'nano googleapis.sh'
# - if you have not selected or created a dummy file to test the download
#   speed from your remote, then do so now. a file between 50MB-100MB should
#   be fine;
# - manually run the script at least once to ensure it works. using the shebang:
#   './googleapis.sh' (or 'sudo ./googleapis.sh' if not root)
#   or by calling 'sh' (or bash or whatever POSIX shell) directly:
#   'sh googleapis.sh' (or 'sudo sh googleapis.sh' if not root)
###################################################################################
# Noteworthy requirements:
# - rclone;
# - dig: in apt-based distros, install it via 'apt install dnsutils';
# - a dummy file on the remote: you can point to an existing file or create an
#                              empty one via 'fallocate -l 50M dummyfile' and
#                              then copying it to your remote.
###################################################################################
# Author: @cgomesu (this version is a rework of the original script by @Nebarik)
# Repo: https://github.com/cgomesu/mediscripts-shared
###################################################################################
# This script is POSIX shell compliant. Keep it that way.
###################################################################################

# uncomment and edit to set a custom name for the remote.
#REMOTE=""
DEFAULT_REMOTE="gcrypt"

# uncomment and edit to set a custom path to a config file. Default uses
# rclone's default ("$HOME/.config/rclone/rclone.conf").
#CONFIG=""

# uncomment to set the full path to the REMOTE directory containing a test file.
#REMOTE_TEST_DIR=""
DEFAULT_REMOTE_TEST_DIR="/tmp/"

# uncomment to set the name of a REMOTE file to test download speed.
#REMOTE_TEST_FILE=""
DEFAULT_REMOTE_TEST_FILE="dummyfile"

# Warning: be careful where you point the LOCAL_TMP dir because this script will
# delete it automatically before exiting!
# uncomment to set the LOCAL temporary root directory.
#LOCAL_TMP_ROOT=""
DEFAULT_LOCAL_TMP_ROOT="/tmp/"

# uncomment to set the LOCAL temporary application directory.
#TMP_DIR=""
DEFAULT_LOCAL_TMP_DIR="ges/"

# uncomment to set a default criterion. this refers to the integer (in mebibyte/s, MiB/s) of the download
# rate reported by rclone. lower or equal values are blacklisted, while higher values are whitelisted.
# by default, script whitelists any connection that reaches any MiB/s speed above 0 (e.g., 1, 2, 3, ...).
#SPEED_CRITERION=5
DEFAULT_SPEED_CRITERION=0

# uncomment to append to the hosts file ONLY THE BEST whitelisted endpoint IP to the API address (single host entry).
# by default, the script appends ALL whitelisted IPs to the host file.
#USE_ONLY_BEST_ENDPOINT="true"

# uncomment to indicate the application to store blacklisted ips PERMANENTLY and use them to filter
# future runs. by default, blacklisted ips are NOT permanently stored to allow the chance that a bad server
# might become good in the future.
#USE_PERMANENT_BLACKLIST="true"

#PERMANENT_BLACKLIST_DIR=""
DEFAULT_PERMANENT_BLACKLIST_DIR="$HOME/"
#PERMANENT_BLACKLIST_FILE=""
DEFAULT_PERMANENT_BLACKLIST_FILE="blacklisted_google_ips"

# uncomment to indicate the application to test a fix list of ips ADDITIONALY to the ones 
# found by the query to the dns server
#USE_CUSTOM_LIST="true"

#CUSTOM_LIST_DIR=""
DEFAULT_CUSTOM_LIST_DIR="$HOME/"
#CUSTOM_LIST_FILE=""
DEFAULT_CUSTOM_LIST_FILE="custom_google_ips"

# uncomment to set a custom API address.
#CUSTOM_API=""
DEFAULT_API="www.googleapis.com"

# uncomment to set a custom timeout.
#CUSTOM_TIMEOUT=""
DEFAULT_TIMEOUT="30s"

# full path to hosts file.
HOSTS_FILE="/etc/hosts"

# do NOT edit these variables.
TEST_FILE="${REMOTE:-$DEFAULT_REMOTE}:${REMOTE_TEST_DIR:-$DEFAULT_REMOTE_TEST_DIR}${REMOTE_TEST_FILE:-$DEFAULT_REMOTE_TEST_FILE}"
API="${CUSTOM_API:-$DEFAULT_API}"
LOCAL_TMP="${LOCAL_TMP_ROOT:-$DEFAULT_LOCAL_TMP_ROOT}${TMP_DIR:-$DEFAULT_LOCAL_TMP_DIR}"
PERMANENT_BLACKLIST="${PERMANENT_BLACKLIST_DIR:-$DEFAULT_PERMANENT_BLACKLIST_DIR}${PERMANENT_BLACKLIST_FILE:-$DEFAULT_PERMANENT_BLACKLIST_FILE}"
CUSTOM_LIST="${CUSTOM_LIST_DIR:-$DEFAULT_CUSTOM_LIST_DIR}${CUSTOM_LIST_FILE:-$DEFAULT_CUSTOM_LIST_FILE}"
TIMEOUT="${CUSTOM_TIMEOUT:-$DEFAULT_TIMEOUT}"


# takes a status ($1) as arg. used to indicate whether to restore hosts file from backup or not.
cleanup () {
  # restore hosts file from backup before exiting with error
  if [ "$1" -ne 0 ] && check_root && [ -f "$HOSTS_FILE_BACKUP" ]; then
    cp "$HOSTS_FILE_BACKUP" "$HOSTS_FILE" > /dev/null 2>&1
  fi
  # append new blacklisted IPs to permanent list if using it and exiting wo error
  if [ "$1" -eq 0 ] && [ "$USE_PERMANENT_BLACKLIST" = 'true' ] && [ -f "$BLACKLIST" ]; then
    if [ -f "$PERMANENT_BLACKLIST" ]; then tee -a "$PERMANENT_BLACKLIST" < "$BLACKLIST" > /dev/null 2>&1; fi
  fi
  # remove local tmp dir and its files if the dir exists
  if [ -d "$LOCAL_TMP" ]; then
    rm -rf "$LOCAL_TMP" > /dev/null 2>&1
  fi
}

# takes msg ($1) and status ($2) as args
end () {
  cleanup "$2"
  echo '***********************************************'
  echo '* Finished Google Endpoint Scanner (GES)'
  echo "* Message: $1"
  echo '***********************************************'
  exit "$2"
}

start () {
  echo '***********************************************'
  echo '******** Google Endpoint Scanner (GES) ********'
  echo '***********************************************'
  msg "The application started on $(date)." 'INFO'
}

# takes message ($1) and level ($2) as args
msg () {
  echo "[GES] [$2] $1"
}

# checks user is root
check_root () {
  if [ "$(id -u)" -eq 0 ]; then return 0; else return 1; fi
}

# create temporary dir and files
create_local_tmp () {
  LOCAL_TMP_SPEEDRESULTS_DIR="$LOCAL_TMP""speedresults/"
  LOCAL_TMP_TESTFILE_DIR="$LOCAL_TMP""testfile/"
  mkdir -p "$LOCAL_TMP_SPEEDRESULTS_DIR" "$LOCAL_TMP_TESTFILE_DIR" > /dev/null 2>&1
  BLACKLIST="$LOCAL_TMP"'blacklist_api_ips'
  API_IPS="$LOCAL_TMP"'api_ips'
  touch "$BLACKLIST" "$API_IPS"
}

# hosts file backup
hosts_backup () {
  if [ -f "$HOSTS_FILE" ]; then
    HOSTS_FILE_BACKUP="$HOSTS_FILE"'.backup'
    if [ -f "$HOSTS_FILE_BACKUP" ]; then
      msg "Hosts backup file found. Restoring it." 'INFO'
      if ! cp "$HOSTS_FILE_BACKUP" "$HOSTS_FILE"; then return 1; fi
    else
      msg "Hosts backup file not found. Backing it up." 'WARNING'
      if ! cp "$HOSTS_FILE" "$HOSTS_FILE_BACKUP"; then return 1; fi
    fi
    return 0;
  else
    msg "The hosts file at $HOSTS_FILE does not exist." 'ERROR'
    return 1;
  fi
}

# takes a command as arg ($1)
check_command () {
  if command -v "$1" > /dev/null 2>&1; then return 0; else return 1; fi
}

# add/parse bad IPs to/from a permanent blacklist
blacklisted_ips () {
  API_IPS_PROGRESS="$LOCAL_TMP"'api-ips-progress'
  mv "$API_IPS_FRESH" "$API_IPS_PROGRESS"
  if [ -f "$PERMANENT_BLACKLIST" ]; then
    msg "Found permanent blacklist. Parsing it." 'INFO'
    while IFS= read -r line; do
      if validate_ipv4 "$line"; then
        # grep with inverted match
        grep -v "$line" "$API_IPS_PROGRESS" > "$API_IPS" 2>/dev/null
        mv "$API_IPS" "$API_IPS_PROGRESS"
      fi
    done < "$PERMANENT_BLACKLIST"
  else
    msg "Did not find a permanent blacklist at $PERMANENT_BLACKLIST. Creating a new one." 'WARNING'
    mkdir -p "$PERMANENT_BLACKLIST_DIR" 2>/dev/null
    touch "$PERMANENT_BLACKLIST" 2>/dev/null
  fi
  mv "$API_IPS_PROGRESS" "$API_IPS"
}

# add IPs from a custom list
custom_ips () {
  API_IPS_PROGRESS="$LOCAL_TMP"'api-ips-progress'
  mv "$API_IPS_FRESH" "$API_IPS_PROGRESS"
  if [ -f "$CUSTOM_LIST" ]; then
    msg "Found custom ip list. Parsing it." 'INFO'
    while IFS= read -r line; do
      if validate_ipv4 "$line"; then
        # grep with inverted match to remove if already exists
        grep -v "$line" "$API_IPS_PROGRESS" > "$API_IPS" 2>/dev/null
        mv "$API_IPS" "$API_IPS_PROGRESS"
        # add line to the end
        echo "$line" >> "$API_IPS_PROGRESS"
      fi
    done < "$CUSTOM_LIST"
  fi
  mv "$API_IPS_PROGRESS" "$API_IPS_FRESH"
}

# ip checker that tests Google endpoints for download speed.
# takes an IP addr ($1) and its name ($2) as args.
ip_checker () {
  IP="$1"
  NAME="$2"
  HOST="$IP $NAME"
  RCLONE_LOG="$LOCAL_TMP"'rclone.log'

  echo "$HOST" | tee -a "$HOSTS_FILE" > /dev/null 2>&1
  msg "Please wait. Downloading the test file from $IP... " 'INFO'

  # rclone download command
  if check_command "rclone"; then
    if [ -n "$CONFIG" ]; then
      timeout "$TIMEOUT" rclone copy --config "$CONFIG" --log-file "$RCLONE_LOG" -v "${TEST_FILE}" "$LOCAL_TMP_TESTFILE_DIR"
    else
      timeout "$TIMEOUT" rclone copy --log-file "$RCLONE_LOG" -v "${TEST_FILE}" "$LOCAL_TMP_TESTFILE_DIR"
    fi
  else
    msg "Rclone is not installed or is not reachable in this user's \$PATH." 'ERROR'
    end 'Cannot continue. Fix the rclone issue and try again.' 1
  fi

  # parse log file
  if [ -f "$RCLONE_LOG" ]; then
    if grep -qi "failed" "$RCLONE_LOG"; then
      msg "Unable to connect with $IP." 'WARNING'
    else
      msg "Parsing connection with $IP." 'INFO'
      # only whitelist MiB/s connections
      if grep -qi "MiB/s" "$RCLONE_LOG"; then
        SPEED=$(grep "MiB/s" "$RCLONE_LOG" | cut -d, -f3 | cut -c 2- | cut -c -5 | tail -1)
        # use speed criterion to decide whether to whilelist or not
        SPEED_INT="$(echo "$SPEED" | cut -f 1 -d '.')"
        if [ "$SPEED_INT" -gt "${SPEED_CRITERION:-$DEFAULT_SPEED_CRITERION}" ]; then
          # good endpoint
          msg "$SPEED MiB/s. Above criterion endpoint. Whitelisting IP '$IP'." 'INFO'
          echo "$IP" | tee -a "$LOCAL_TMP_SPEEDRESULTS_DIR$SPEED" > /dev/null
        else
          # below criterion endpoint
          msg "$SPEED MiB/s. Below criterion endpoint. Blacklisting IP '$IP'." 'INFO'
          echo "$IP" | tee -a "$BLACKLIST" > /dev/null
        fi
      elif grep -qi "KiB/s" "$RCLONE_LOG"; then
        SPEED=$(grep "KiB/s" "$RCLONE_LOG" | cut -d, -f3 | cut -c 2- | cut -c -5 | tail -1)
        msg "$SPEED KiB/s. Abnormal endpoint. Blacklisting IP '$IP'." 'WARNING'
        echo "$IP" | tee -a "$BLACKLIST" > /dev/null
      else
        # assuming it's either KiB/s or MiB/s, else parses as error and do nothing
        msg "Could not parse connection with IP '$IP'." 'WARNING'
      fi
    fi
    # local cleanup of tmp file and log
    rm "$LOCAL_TMP_TESTFILE_DIR${REMOTE_TEST_FILE:-$DEFAULT_REMOTE_TEST_FILE}" > /dev/null 2>&1
    rm "$RCLONE_LOG" > /dev/null 2>&1
  fi
  # restore hosts file from backup
  cp "$HOSTS_FILE_BACKUP" "$HOSTS_FILE" > /dev/null 2>&1
}

# returns the fastest IP from speedresults
fastest_host () {
  LOCAL_TMP_SPEEDRESULTS_COUNT="$LOCAL_TMP"'speedresults_count'
  ls "$LOCAL_TMP_SPEEDRESULTS_DIR" > "$LOCAL_TMP_SPEEDRESULTS_COUNT"
  MAX=$(sort -nr "$LOCAL_TMP_SPEEDRESULTS_COUNT" | head -1)
  # same speed file can contain multiple IPs, so get whatever is at the top
  MACS=$(head -1 "$LOCAL_TMP_SPEEDRESULTS_DIR$MAX" 2>/dev/null)
  echo "$MACS"
}

# takes an address as arg ($1)
validate_ipv4 () {
  # lack of match in grep should return an exit code other than 0
  if echo "$1" | grep -oE "[[:digit:]]{1,3}.[[:digit:]]{1,3}.[[:digit:]]{1,3}.[[:digit:]]{1,3}" > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# parse results and append only the best whitelisted IP to hosts
append_best_whitelisted_ip () {
  BEST_IP=$(fastest_host)
  if validate_ipv4 "$BEST_IP"; then
    msg "The fastest IP is $BEST_IP. Putting into the hosts file." 'INFO'
    echo "$BEST_IP $API" | tee -a "$HOSTS_FILE" > /dev/null 2>&1
  else
    msg "The selected '$BEST_IP' address is not a valid IP number." 'ERROR'
    end "Unable to find the best IP address. Original hosts file will be restored." 1
  fi
}

# parse results and append all whitelisted IPs to hosts
append_all_whitelisted_ips () {
  for file in "$LOCAL_TMP_SPEEDRESULTS_DIR"*; do
    if [ -f "$file" ]; then
      # same speed file can contain multiple IPs
      while IFS= read -r line; do
        WHITELISTED_IP="$line"
        if validate_ipv4 "$WHITELISTED_IP"; then
          msg "The whitelisted IP '$WHITELISTED_IP' will be added to the hosts file." 'INFO'
          echo "$WHITELISTED_IP $API" | tee -a "$HOSTS_FILE" > /dev/null 2>&1
        else
          msg "The whitelisted IP '$WHITELISTED_IP' address is not a valid IP number. Skipping it." 'WARNING'
        fi
      done < "$file"
    else
      msg "Did not find any whitelisted IP at '$LOCAL_TMP_SPEEDRESULTS_DIR'." 'ERROR'
      end "Unable to find whitelisted IP addresses. Original hosts file will be restored." 1
    fi
  done
}

############
# main logic
start

trap "end 'Received a signal to stop' 1" INT HUP TERM

# need root permission to write hosts
if ! check_root; then end "User is not root but this script needs root permission. Run as root or append 'sudo'." 1; fi

# prepare local files
create_local_tmp
if ! hosts_backup; then end "Unable to backup the hosts file. Check its path and continue." 1; fi

# prepare remote file
# TODO: (cgomesu) add function to allocate a dummy file in the remote

# start running test
if ! check_command "timeout"; then
  msg "The command 'timeout' is not installed or not reachable in this user's \$PATH." 'ERROR'
  end "Install timeout or make sure its executable is reachable, then try again." 1
fi

if check_command "dig"; then
  # redirect dig output to tmp file to be parsed later
  API_IPS_FRESH="$LOCAL_TMP"'api-ips-fresh'
  dig "$1" +answer "$API" +short 1> "$API_IPS_FRESH" 2>/dev/null
else
  msg "The command 'dig' is not installed or not reachable in this user's \$PATH." 'ERROR'
  end "Install dig or make sure its executable is reachable, then try again." 1
fi

if [ "$USE_CUSTOM_LIST" = 'true' ]; then
  # add custom ips to the list
  custom_ips
fi

if [ "$USE_PERMANENT_BLACKLIST" = 'true' ]; then
  # bad IPs are permanently blacklisted
  blacklisted_ips
else
  # bad IPs are blacklisted on a per-run basis
  mv "$API_IPS_FRESH" "$API_IPS"
fi

while IFS= read -r line; do
  # checking each ip in API_IPS
  if validate_ipv4 "$line"; then ip_checker "$line" "$API"; fi
done < "$API_IPS"

# parse whitelisted IPs and edit hosts file accordingly
if [ "$USE_ONLY_BEST_ENDPOINT" = 'true' ]; then
  append_best_whitelisted_ip
else
  append_all_whitelisted_ips
fi

# end the script wo errors
end "Reached EOF without errors" 0
