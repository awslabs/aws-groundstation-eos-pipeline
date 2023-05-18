# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify,
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
# PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#!/bin/bash
# Run as the ipopp user

SatelliteName=$1
S3_BUCKET=$2
REGION=$(curl -s 169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')
LC_SatelliteName=$(echo $SatelliteName | tr "[:upper:]" "[:lower:]")
TIMESTR=$(date '+%Y%m%d-%H%M')

# Determines if a thumbnail should be created
# If created it is shared in the SNS notification as a public url or presigned url
# Valid options: 'disabled', 'public', 'presign'
THUMBNAIL_OPTION="disabled"

# ========================================
# Functions
# ========================================

function sendSNS {

  SNS_TOPIC=$1
  MESSAGE=$2
  echo "Sending SNS Message."
  echo "Topic Arn: ${SNS_TOPIC}"
  echo "Message: ${MESSAGE}"
  aws sns publish --topic-arn ${SNS_TOPIC} --message "$MESSAGE" --region $REGION

}

function handleError {

  # If ERROR is not blank concatenate with previous error
  [ "$ERROR" == "" ] && ERROR="${2}:${1}" || ERROR="$ERROR ; ${2}:${1}"

  # sendSNS if SNS_TOPIC is not blank
  if [ "$2" == "FATAL" ]; then
    echo "Fatal Error: $1"

MESSAGE="{
  \"Result\" : \"Failed\",
  \"S3Bucket\" : \"${S3_BUCKET}\",
  \"Satellite\" : \"${SatelliteName}\",
  \"Errors\" : \"$ERROR\"
}"
    # Send SNS and quit
    #[ "${SNS_TOPIC}" != "" ] && sendSNS ${SNS_TOPIC} "S3 Bucket  : ${S3_BUCKET} ${NL} Satellite  : ${SatelliteName} ${NL} $(basename $0) Failed. Errors: $ERROR"
    [ "${SNS_TOPIC}" != "" ] && sendSNS ${SNS_TOPIC} "$MESSAGE"
    exit 1
  fi

}

# ========================================
#
# Main code section
#
# ========================================

START_TIME=$(date '+%Y%m%d-%H:%M:%S')

# Stop IPOPP if running
#echo "Stopping IPOPP if running"
#/home/ipopp/drl/tools/services.sh stop

# If SNS topic is configured
if [ -f /opt/aws/groundstation/bin/getSNSTopic.sh ] ; then
  source /opt/aws/groundstation/bin/getSNSTopic.sh
  echo "Using SNS Topic: ${SNS_TOPIC}"
fi

# AQUA/MODIS Dirs:
# /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/modis/level0,1,2
# /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/gbad

# JPSS1/VIIRS Dirs:
# /home/ipopp/drl/data/pub/gsfcdata/jpss1/viirs/level0,1,2
# /home/ipopp/drl/data/pub/gsfcdata/jpss1/spacecraft/level0

# JPSS1/VIIRS Timings:
# VIIRS-L1: 21 mins!!
# L1-SDR: 2m 53s
# H2G vtoatcolour: 17s
# H2G vml2h5.getiff:

# if [ "$SatelliteName"=="AQUA" ]; then
#
#   BASE_DIR="/home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/modis"
#   OTHER_DIR="/home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/modis"
#
# elif [ "$SatelliteName"=="JPSS1" ]; then
#
# else
#
# fi

NUM_L0_FILES_BEFORE_INGEST=$(ls -l /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/modis/level0 | grep -v ^total | wc -l)
NUM_L1_FILES_BEFORE_INGEST=$(ls -l /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/modis/level1 | grep -v ^total | wc -l)
NUM_L2_FILES_BEFORE_INGEST=$(ls -l /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/modis/level2 | grep -v ^total | wc -l)
NUM_GBAD_FILES_BEFORE_INGEST=$(ls -l /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/gbad | grep -v ^total | wc -l)

#echo "NUM_L0_FILES_BEFORE_INGEST: $NUM_L0_FILES_BEFORE_INGEST"
#echo "NUM_L1_FILES_BEFORE_INGEST: $NUM_L1_FILES_BEFORE_INGEST"
#echo "NUM_L2_FILES_BEFORE_INGEST: $NUM_L2_FILES_BEFORE_INGEST"
#echo "NUM_GBAD_FILES_BEFORE_INGEST: $NUM_GBAD_FILES_BEFORE_INGEST"

echo "Getting new files from S3"
S3_DOWNLOAD_START=$(date '+%Y%m%d-%H:%M:%S')
export SOURCE="s3://${S3_BUCKET}/data/${SatelliteName}/level0/"
export DEST="/home/ipopp/drl/data/dsm/ingest"

# Include the following Product Data Set (PDS) files:
# Although RT-STPS may produce more PDS files, IPOPP can only currently process these.
# P*0064: TERRA / MODIS Packet and CSR files
# P*0957: AQUA GBAD Packet and CSR Files
# P15*0000, P15*0008, P15*0011: SNPP+JPSS S/C
# P15*0826VIIRSSCIENCE: SNMP+JPSS VIRS
# P157056*AAAAAA: SNMP OMPS
# P159061*AAAAAA: JPSS OMPS
aws s3 sync $SOURCE $DEST --no-progress --region $REGION --exclude "*" \
--include "P*0064AAAAAAAAAAAAAA*" --include "P*0957AAAAAAAAAAAAAA*" \
--include "P15*AAAAAAAAAAAAA*" --include "P15*0008AAAAAAAAAAAAA*" --include "P15*0011AAAAAAAAAAAAA*" \
--include "P15*0826VIIRSSCIENCE*" \
--include "P157056*AAAAAA*" --include "P159061*AAAAAA*" || handleError "Error code ${?}. Failed to run aws s3 sync $SOURCE $DEST --region $REGION" "FATAL"

S3_DOWNLOAD_END=$(date '+%Y%m%d-%H:%M:%S')

# Test if we have access to the NASA site for ancillary files
echo "Testing access to https://is.sci.gsfc.nasa.gov"
curl --silent https://is.sci.gsfc.nasa.gov > /dev/null
EXIT_CODE=$?

if [ $EXIT_CODE != 0 ] ; then

  handleError "Error code $EXIT_CODE. Failed to connect to https://is.sci.gsfc.nasa.gov for IPOPP ancillary files" "WARNING"
  echo "No access to https://is.sci.gsfc.nasa.gov Getting IPOPP ancillary files from S3"

  TODAY=$(date '+%Y%m%d')
  LEAPSEC_FILE=leapsec.${TODAY}00.dat
  LEAPSEC_FILE_PATH=/home/ipopp/drl/data/pub/ancillary/temporal/${LEAPSEC_FILE}

  SOURCE="s3://${S3_BUCKET}/software/IPOPP/ancillary-data/"
  DEST="/home/ipopp/drl/data/pub/CompressedArchivedAncillary/"
  aws s3 sync ${SOURCE} ${DEST} --no-progress --region $REGION || handleError "Error code ${?}. Failed to run aws s3 sync ${SOURCE} ${DEST} --region $REGION" "WARNING"
  #  Update permissions to avoid rm delete confirmation prompts from IPOPP ancillary download script
  chmod -R 777 /home/ipopp/drl/data/pub/CompressedArchivedAncillary

else

  echo "Connection to https://is.sci.gsfc.nasa.gov OK"

fi

# Start IPOPP services
IPOPP_INGEST_START=$(date '+%Y%m%d-%H:%M:%S')
echo "Starting IPOPP services"
/home/ipopp/drl/tools/services.sh start || handleError "Error code ${?}. Failed to start IPOPP services" "FATAL"

# Start IPOPP ingest
echo "Ingesting files into IPOPP"
/home/ipopp/drl/tools/ingest_ipopp.sh || handleError "Error code ${?}. Failed to run IPOPP ingest" "FATAL"
IPOPP_INGEST_END=$(date '+%Y%m%d-%H:%M:%S')

# Sleep to allow IPOPP to process some files
echo "Sleeping for 60 mins to wait for IPOPP to create files"
sleep 3600

# The IPOPP ingest tasks copies file from and to the locations below
# Therefore we can remove all files in the S3 bucket that exist in the 'to' dir
# This avoids them being processed again during the next ingest
# from: /home/ipopp/drl/data/dsm/ingest
# to: /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/modis
echo "Removing ingested level 0 files from S3 bucket"
export LOCAL_DIR="/home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/modis/level0"
export REMOTE_DIR="s3://${S3_BUCKET}/data/${SatelliteName}/level0"

pushd $LOCAL_DIR
for PDS_FILE in *.PDS; do

    # Skip if not a file
    [ -f "$PDS_FILE" ] || break

    echo "Found locally processed PDS file: $PDS_FILE. Removing from S3 bucket if it exists"
    echo "aws s3 rm $REMOTE_DIR/$PDS_FILE --region $REGION"
    aws s3 rm $REMOTE_DIR/$PDS_FILE --region $REGION || handleError "Error code ${?}. Failed to run aws s3 rm $REMOTE_DIR/$PDS_FILE --region $REGION" "WARNING"

    if [ "$SatelliteName" == "AQUA" ] ; then

      echo "Removing associated AQUA CSR PDS file from S3 bucket if it exists"
      CSR_FILE=${PDS_FILE:0:4}0957${PDS_FILE:8:32}
      echo "aws s3 rm $REMOTE_DIR/$CSR_FILE --region $REGION"
      aws s3 rm $REMOTE_DIR/$CSR_FILE --region $REGION || handleError "Error code ${?}. Failed to run aws s3 rm $REMOTE_DIR/$CSR_FILE --region $REGION" "WARNING"

    fi
done

# Push gbad files to S3
echo "Pushing gbad files to S3"
aws s3 sync /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/gbad/ s3://${S3_BUCKET}/data/${SatelliteName}/gbad/ --no-progress --region $REGION || handleError "Error code ${?}. Failed to run aws s3 sync /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/gbad/ s3://${S3_BUCKET}/data/${SatelliteName}/gbad/ --region $REGION" "WARNING"

# Start loop to push files to S3
SOURCE="/home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/modis/"
DEST="s3://${S3_BUCKET}/data/${SatelliteName}/modis/"
SLEEPTIME=400
x=1
MAX_ITERATIONS=3
NUM_NEW_L2_FILES_AFTER_SLEEP=0

while [ $x -le $MAX_ITERATIONS ]
do
    echo "Pushing modis files to S3"
    aws s3 sync $SOURCE $DEST --no-progress --region $REGION || handleError "Error code ${?}. Failed to run aws s3 sync $SOURCE $DEST --region $REGION" "WARNING"

    echo "Getting num L2 files, before sleep"
    NUM_L2_FILES_BEFORE_SLEEP=$(ls -l /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/modis/level2 | grep -v ^total | wc -l)

    echo "[$x] Sleeping for $SLEEPTIME seconds"
    x=$(( $x + 1 ))
    sleep $SLEEPTIME

    echo "Getting num L2 files, after sleep"
    NUM_L2_FILES_AFTER_SLEEP=$(ls -l /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/modis/level2 | grep -v ^total | wc -l)
    let NUM_NEW_L2_FILES_AFTER_SLEEP=$NUM_L2_FILES_AFTER_SLEEP-$NUM_L2_FILES_BEFORE_SLEEP

    if [[ "$NUM_NEW_L2_FILES_AFTER_SLEEP" == '0' ]]; then
      echo "No new L2 files created after sleeping. Considering the processing finished."
      break
    fi

done
echo "Finished!"

NUM_L0_FILES_AFTER_INGEST=$(ls -l /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/modis/level0 | grep -v ^total | wc -l)
NUM_L1_FILES_AFTER_INGEST=$(ls -l /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/modis/level1 | grep -v ^total | wc -l)
NUM_L2_FILES_AFTER_INGEST=$(ls -l /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/modis/level2 | grep -v ^total | wc -l)
NUM_GBAD_FILES_AFTER_INGEST=$(ls -l /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/gbad | grep -v ^total | wc -l)

echo "NUM_L0_FILES_AFTER_INGEST: $NUM_L0_FILES_AFTER_INGEST"
echo "NUM_L1_FILES_AFTER_INGEST: $NUM_L1_FILES_AFTER_INGEST"
echo "NUM_L2_FILES_AFTER_INGEST: $NUM_L2_FILES_AFTER_INGEST"
echo "NUM_GBAD_FILES_AFTER_INGEST: $NUM_GBAD_FILES_AFTER_INGEST"

let NUM_NEW_L0_FILES=$NUM_L0_FILES_AFTER_INGEST-$NUM_L0_FILES_BEFORE_INGEST
let NUM_NEW_L1_FILES=$NUM_L1_FILES_AFTER_INGEST-$NUM_L1_FILES_BEFORE_INGEST
let NUM_NEW_L2_FILES=$NUM_L2_FILES_AFTER_INGEST-$NUM_L2_FILES_BEFORE_INGEST
let NUM_NEW_GBAD_FILES=$NUM_GBAD_FILES_AFTER_INGEST-$NUM_GBAD_FILES_BEFORE_INGEST

echo "New L0 Files : ${NUM_NEW_L0_FILES}"
echo "New L1 Files : ${NUM_NEW_L1_FILES}"
echo "New L2 Files : ${NUM_NEW_L2_FILES}"
echo "New GBAD Files : ${NUM_NEW_GBAD_FILES}"

#	===================================================
#	Create thumbnail of the composite RGB crefl image
#	===================================================

if [ $THUMBNAIL_OPTION != 'disabled' ] ; then

  echo "Creating crefl thumbnail image"

  # Get the latest crefl image
  WORKING_DIR="/home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/modis/level2"
  pushd ${WORKING_DIR}
  LATEST_CREFL_IMAGE=$(ls -lt MYDcrefl_TrueColor.* | head -1 | awk '{print $9}')

  # Create a 200px high thumbnail image
  convert -thumbnail x200 ${LATEST_CREFL_IMAGE} thumb.${LATEST_CREFL_IMAGE}

  # Generate S3 path
  TARGET_S3_PATH="s3://${S3_BUCKET}/data/${SatelliteName}/modis/level2/thumb.${LATEST_CREFL_IMAGE}"

fi

if [ $THUMBNAIL_OPTION == 'presign' ] ; then

  echo "Uploading thumbnail crefl image and creating presigned url"

  # Upload as private and create presigned URL
  aws s3 cp ${WORKING_DIR}/thumb.${LATEST_CREFL_IMAGE} ${TARGET_S3_PATH} --region $REGION
  THUMBNAIL_URL=$(aws s3 presign ${TARGET_S3_PATH} --expires-in 604800 --region $REGION)

elif [ $THUMBNAIL_OPTION == 'public' ] ; then

  echo "Uploading thumbnail crefl image as public-read"

  # Alternative to a pre-signed URL, upload with public-read access
  aws s3 cp ${WORKING_DIR}/thumb.${LATEST_CREFL_IMAGE} ${TARGET_S3_PATH} --acl public-read --region $REGION
  THUMBNAIL_URL="https://${S3_BUCKET}.s3.${REGION}.amazonaws.com/data/${SatelliteName}/modis/level2/thumb.${LATEST_CREFL_IMAGE}"

fi

#	=============================
#	Send SNS Notification
#	=============================

if [ -f /opt/aws/groundstation/bin/getSNSTopic.sh ] ; then

# The following command assumes there is only one mounted volume
DISK_USED_PERCENT=$(df -h | grep "^/dev/root" | awk '{print $5}')

# Get number of IPOPP Errors
/home/ipopp/drl/nsls/bin/print-logs.sh -eventlevel e > /tmp/ipopp.errors
NUM_ERRORS=$(egrep '^ERROR' /tmp/ipopp.errors | wc -l)

MESSAGE="{
  \"Result\" : \"Success\",
  \"Errors\" : \"$ERROR\",
  \"NumIpoppErrors\" : \"${NUM_ERRORS}\",
  \"S3Bucket\" : \"${S3_BUCKET}\",
  \"Satellite\" : \"${SatelliteName}\",
  \"StartTime\" : \"${START_TIME}\",
  \"S3DownloadStartTime\" : \"${S3_DOWNLOAD_START}\",
  \"S3DownloadEndTime\" : \"${S3_DOWNLOAD_END}\",
  \"IpoppIngestStartTime\" : \"${IPOPP_INGEST_START}\",
  \"IpoppIngestEndTime\" : \"${IPOPP_INGEST_END}\",
  \"NumNewL0Files\" : \"${NUM_NEW_L0_FILES}\",
  \"NumNewL1Files\" : \"${NUM_NEW_L1_FILES}\",
  \"NumNewL2Files\" : \"${NUM_NEW_L2_FILES}\",
  \"NumNewGbadFiles\" : \"${NUM_NEW_GBAD_FILES}\",
  \"LogFileName\" : \"${TIMESTR}-${SatelliteName}-ipopp-ingest.log\",
  \"DiskUsedPercent\" : \"${DISK_USED_PERCENT}\",
  \"ThumbnailUrl\" : \"${THUMBNAIL_URL}\"
}"

sendSNS ${SNS_TOPIC} "$MESSAGE"

fi

# Upload logfile to S3 /opt/aws/groundstation/bin/ipopp-ingest.log
echo "Uploading /opt/aws/groundstation/bin/ipopp-ingest.log to s3://${S3_BUCKET}/data/${SatelliteName}/logs/${TIMESTR}-${SatelliteName}-ipopp-ingest.log"
aws s3 cp /opt/aws/groundstation/bin/ipopp-ingest.log s3://${S3_BUCKET}/data/${SatelliteName}/logs/${TIMESTR}-${SatelliteName}-ipopp-ingest.log --region $REGION

echo "Stopping IPOPP services"
/home/ipopp/drl/tools/services.sh stop
