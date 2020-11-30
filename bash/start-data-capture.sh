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

export PYTHONUNBUFFERED=TRUE
SatelliteName=$1
S3_BUCKET=$2
MIN_RAW_FILESIZE=2000000
REGION=$(curl -s 169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')
LC_SatelliteName=$(echo $SatelliteName | tr "[:upper:]" "[:lower:]")

# Init some vars
ERROR=""
NUM_UPLOADED_RAW_FILES=0
NUM_UPLOADED_L0_FILES=0

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
  \"Errors\" : \"$ERROR\",
  \"LogFileName\" : \"${TIMESTR}-${SatelliteName}-data-capture.log\"
}"
    # Send SNS and quit
    #[ "${SNS_TOPIC}" != "" ] && sendSNS ${SNS_TOPIC} "S3 Bucket  : ${S3_BUCKET} ${NL} Satellite  : ${SatelliteName} ${NL} $(basename $0) Failed. Errors: $ERROR"
    [ "${SNS_TOPIC}" != "" ] && sendSNS ${SNS_TOPIC} "$MESSAGE"

    # Upload logfile e.g. data-capture_20200225-1844.log
    echo "Uploading /opt/aws/groundstation/bin/data-capture_${TIMESTR}.log to s3://${S3_BUCKET}/data/${SatelliteName}/logs/${TIMESTR}-${SatelliteName}-data-capture.log"
    aws s3 cp /opt/aws/groundstation/bin/data-capture_${TIMESTR}.log s3://${S3_BUCKET}/data/${SatelliteName}/logs/${TIMESTR}-${SatelliteName}-data-capture.log --region $REGION

    # Shutdown
    echo "Finished (With errors). Shutting down"
    shutdown -h now

  fi

}

# ========================================
#
# Main code section
#
# ========================================

export NOW=$(date '+%Y%m%d-%H:%M:%S')
START_TIME=$NOW
echo "$NOW	Satellite: ${SatelliteName}"
echo "$NOW	S3 bucket: ${S3_BUCKET}"

# If SNS topic is configured
if [ -f /opt/aws/groundstation/bin/getSNSTopic.sh ] ; then
  source /opt/aws/groundstation/bin/getSNSTopic.sh
  echo "$NOW	Using SNS Topic: ${SNS_TOPIC}"
fi

#	=============================
#	RT-STPS Install (if needed)
#	=============================

#	Check if RT-STPS is installed already
if [ -d "/root/rt-stps" ]; then
	export NOW=$(date '+%Y%m%d-%H:%M:%S')
	echo "$NOW	RT-STPS already installed, skipping installation"
else
	export NOW=$(date '+%Y%m%d-%H:%M:%S')
	echo "$NOW	Getting RT-STPS software from S3 bucket: ${S3_BUCKET}"
	cd ~
	aws s3 cp s3://${S3_BUCKET}/software/RT-STPS/RT-STPS_6.0.tar.gz . --region $REGION && \
	aws s3 cp s3://${S3_BUCKET}/software/RT-STPS/RT-STPS_6.0_PATCH_1.tar.gz . --region $REGION && \
	aws s3 cp s3://${S3_BUCKET}/software/RT-STPS/RT-STPS_6.0_PATCH_2.tar.gz . --region $REGION && \
	aws s3 cp s3://${S3_BUCKET}/software/RT-STPS/RT-STPS_6.0_PATCH_3.tar.gz . --region $REGION || handleError "Error code ${?}. Failed to get RT-STPS from s3://${S3_BUCKET}/software/RT-STPS/" "FATAL"

	export NOW=$(date '+%Y%m%d-%H:%M:%S')
	echo "$NOW	Installing RT-STPS..."
	cd ~
	# Extract main package
	tar xzf RT-STPS_6.0.tar.gz
	# Apply patch 2
	cp ~/rt-stps/config/jpss1.xml ~/rt-stps/config/jpss1.xml.old
	tar xzf RT-STPS_6.0_PATCH_2.tar.gz
	# Apply patch 3
	tar xzf RT-STPS_6.0_PATCH_3.tar.gz
	# Install
	cd rt-stps
	./install.sh
fi

#	=============================
#	Data Capture
#	=============================

#	Download the latest version of the software from S3 on every run
export NOW=$(date '+%Y%m%d-%H:%M:%S')

if [ -f ~/data-receiver/awsgs.py ] ; then
  echo "$NOW	~/data-receiver/awsgs.py exists, skipping download"
  cd ~/data-receiver
else
  echo "$NOW	Getting data receiver software from S3"
  mkdir -p ~/data-receiver && cd ~/data-receiver
  aws s3 cp s3://${S3_BUCKET}/software/data-receiver/awsgs.py awsgs.py --region $REGION || handleError "Error code ${?}. Failed to get s3://${S3_BUCKET}/software/data-receiver/awsgs.py" "FATAL"
  aws s3 cp s3://${S3_BUCKET}/software/data-receiver/receivedata.py receivedata.py --region $REGION || handleError "Error code ${?}. Failed to get s3://${S3_BUCKET}/software/data-receiver/receivedata.py" "FATAL"
fi

#	Generate log file name
export TIMESTR=$(date '+%Y%m%d-%H%M')
#export LOGFILE=${TIMESTR}-${SatelliteName}.log
#echo "Using Logfile: ${LOGFILE}"

#	Start data capture
export NOW=$(date '+%Y%m%d-%H:%M:%S')
echo "$NOW	Running python3 receivedata.py ${TIMESTR}-${SatelliteName}-raw.bin"
#python3 receivedata.py ${TIMESTR}-${SatelliteName}-raw.bin 2>&1 | tee $LOGFILE || handleError "Error code ${?}. Failed to call python3 receivedata.py ${TIMESTR}-${SatelliteName}-raw.bin" "FATAL"
python3 receivedata.py ${TIMESTR}-${SatelliteName}-raw.bin 2>&1 || handleError "Error code ${?}. Failed to call python3 receivedata.py ${TIMESTR}-${SatelliteName}-raw.bin" "FATAL"

#	Check size of raw file
if [ -e "${TIMESTR}-${SatelliteName}-raw.bin" ]; then
	FILESIZE=$(stat -c%s "${TIMESTR}-${SatelliteName}-raw.bin")
	export NOW=$(date '+%Y%m%d-%H:%M:%S')
	echo "$NOW Raw data size: $FILESIZE Bytes"
else
  handleError "Error code ${?}. File not found: ${TIMESTR}-${SatelliteName}-raw.bin" "FATAL"
fi

#	=============================
#	RT-STPS Processing
#	=============================

#	Only process if filesize is over 2MB
#	This skips processing if something went wrong

if (( $FILESIZE<$MIN_RAW_FILESIZE )); then
	#echo "$NOW Raw file less than $MIN_RAW_FILESIZE Bytes. Skipping further processing"
  #ERROR="Raw file less than $MIN_RAW_FILESIZE Bytes. Skipping further processing"
  handleError "Raw file less than $MIN_RAW_FILESIZE Bytes. Skipping further processing" "FATAL"
else
	#	Generate leapsec file name
	export TODAY=$(date '+%Y%m%d')
	export LEAPSEC_FILE=leapsec.${TODAY}00.dat

	export NOW=$(date '+%Y%m%d-%H:%M:%S')

  if [ -e ~/rt-stps/${LEAPSEC_FILE} ] ; then
    echo "$NOW	Found required leapsec file: ~/rt-stps/${LEAPSEC_FILE}"
  else
    echo "$NOW	~/rt-stps/${LEAPSEC_FILE} not found. Getting latest leapsec file (${LEAPSEC_FILE}) from nasa.gov"
  	cd ~/rt-stps
  	curl https://is.sci.gsfc.nasa.gov/ancillary/temporal/${LEAPSEC_FILE} -o ${LEAPSEC_FILE} || handleError "Error code ${?}. Failed to get leapsec file from https://is.sci.gsfc.nasa.gov/ancillary/temporal/${LEAPSEC_FILE}" "WARNING"
  fi

	export NOW=$(date '+%Y%m%d-%H:%M:%S')
	echo "$NOW	Starting RT-STPS..."

	export CONFIG_FILE=~/rt-stps/config/${LC_SatelliteName}.xml
	export INPUT_FILE=~/data-receiver/${TIMESTR}-${SatelliteName}-raw.bin

	cd ~/rt-stps

	# Delete previous data
	rm -rf ~/data/*

	# Start RT-STPS server
  RTSTPS_START=$(date '+%Y%m%d-%H:%M:%S')
	./jsw/bin/rt-stps-server.sh start || handleError "Error code ${?}. Failed start RT-STPS server" "FATAL"

	# Process the raw data using RT-STPS batch mode
	./bin/batch.sh $CONFIG_FILE $INPUT_FILE || handleError "Error code ${?}. Failed to run RT-STPS batch mode" "FATAL"

	# Stop the server
	./jsw/bin/rt-stps-server.sh stop || handleError "Error code ${?}. Failed stop RT-STPS server" "WARNING"
  RTSTPS_END=$(date '+%Y%m%d-%H:%M:%S')

  # Check for new level 0 files
  NUM_NEW_L0_FILES=0
  NUM_NEW_L0_FILES=$(ls -l ~/data/ | grep -v ^total | wc -l)
  echo "${NUM_NEW_L0_FILES} new Level 0 files created by RT-STPS"

  # Skip S3 upload if no new files
  if [ $NUM_NEW_L0_FILES == 0 ] ; then
    handleError "No new files found in ~/data/ Skipping S3 upload" "FATAL"
  fi

	#	=============================
	#	S3 Upload
	#	=============================

  S3_UPLOAD_START=$(date '+%Y%m%d-%H:%M:%S')
	echo "$NOW	Uploading raw data to S3"
  NUM_RAW_FILES_BEFORE_UPLOAD=$(aws s3 ls s3://${S3_BUCKET}/data/${SatelliteName}/raw/ --region $REGION | grep -v ^total | wc -l)
	aws s3 cp ~/data-receiver/${TIMESTR}-${SatelliteName}-raw.bin s3://${S3_BUCKET}/data/${SatelliteName}/raw/${TIMESTR}-${SatelliteName}-raw.bin --no-progress --region $REGION || handleError "Error code ${?}. Failed to call aws s3 cp ~/data-receiver/${TIMESTR}-${SatelliteName}-raw.bin s3://${S3_BUCKET}/data/${SatelliteName}/raw/${TIMESTR}-${SatelliteName}-raw.bin --region $REGION" "FATAL"
  NUM_RAW_FILES_AFTER_UPLOAD=$(aws s3 ls s3://${S3_BUCKET}/data/${SatelliteName}/raw/ --region $REGION | grep -v ^total | wc -l)

  let NUM_UPLOADED_RAW_FILES=$NUM_RAW_FILES_AFTER_UPLOAD-$NUM_RAW_FILES_BEFORE_UPLOAD

  if [ $NUM_UPLOADED_RAW_FILES == 0 ] ; then
    handleError "No new raw file uploaded to S3." "WARNING"
  fi

	export NOW=$(date '+%Y%m%d-%H:%M:%S')
	echo "$NOW	Uploading level 0 data to S3"
  NUM_L0_FILES_BEFORE_UPLOAD=$(aws s3 ls s3://${S3_BUCKET}/data/${SatelliteName}/level0/ --region $REGION | grep -v ^total | wc -l)
	aws s3 sync ~/data/ s3://${S3_BUCKET}/data/${SatelliteName}/level0/ --no-progress --region $REGION || handleError "Error code ${?}. aws s3 sync ~/data/ s3://${S3_BUCKET}/data/${SatelliteName}/level0/ --region $REGION" "FATAL"
  NUM_L0_FILES_AFTER_UPLOAD=$(aws s3 ls s3://${S3_BUCKET}/data/${SatelliteName}/level0/ --region $REGION | grep -v ^total | wc -l)
  S3_UPLOAD_END=$(date '+%Y%m%d-%H:%M:%S')

  let NUM_UPLOADED_L0_FILES=$NUM_L0_FILES_AFTER_UPLOAD-$NUM_L0_FILES_BEFORE_UPLOAD

  if [ $NUM_UPLOADED_RAW_FILES == 0 ] ; then
    handleError "No new L0 files uploaded to S3." "WARNING"
  fi

fi

#	=============================
#	Send SNS Notification
#	=============================

if [ -f /opt/aws/groundstation/bin/getSNSTopic.sh ] ; then

MESSAGE="{
  \"Result\" : \"Success\",
  \"Errors\" : \"$ERROR\",
  \"S3Bucket\" : \"${S3_BUCKET}\",
  \"Satellite\" : \"${SatelliteName}\",
  \"StartTime\" : \"${START_TIME}\",
  \"RtStpsStartTime\" : \"${RTSTPS_START}\",
  \"RtStpsEndTime\" : \"${RTSTPS_END}\",
  \"S3UploadStartTime\" : \"${S3_UPLOAD_START}\",
  \"S3UploadEndTime\" : \"${S3_UPLOAD_END}\",
  \"NumUploadedRawFiles\" : \"${NUM_UPLOADED_RAW_FILES}\",
  \"NumUploadedL0Files\" : \"${NUM_UPLOADED_L0_FILES}\",
  \"BytesReceived\" : \"${FILESIZE}\",
  \"RawDataFileName\" : \"${TIMESTR}-${SatelliteName}-raw.bin\",
  \"LogFileName\" : \"${TIMESTR}-${SatelliteName}-data-capture.log\"
}"

sendSNS ${SNS_TOPIC} "$MESSAGE"

fi

# Upload logfile e.g. data-capture_20200225-1844.log
echo "Uploading /opt/aws/groundstation/bin/data-capture_${TIMESTR}.log to s3://${S3_BUCKET}/data/${SatelliteName}/logs/${TIMESTR}-${SatelliteName}-data-capture.log"
aws s3 cp /opt/aws/groundstation/bin/data-capture_${TIMESTR}.log s3://${S3_BUCKET}/data/${SatelliteName}/logs/${TIMESTR}-${SatelliteName}-data-capture.log --region $REGION || handleError "Error code ${?}. Failed to call aws s3 cp /opt/aws/groundstation/bin/data-capture_${TIMESTR}.log s3://${S3_BUCKET}/data/${SatelliteName}/logs/data-capture_${TIMESTR}.log --region $REGION" "WARNING"

# Shutdown
echo "Finished. Shutting down"
shutdown -h now
