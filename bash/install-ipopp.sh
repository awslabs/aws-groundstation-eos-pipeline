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

S3_BUCKET=$1
REGION=$2


if [ ! -e /home/ipopp/DRL-IPOPP_5.0.tar.gz ]; then

  aws s3 ls s3://${S3_BUCKET}/software/IPOPP/DRL-IPOPP_5.0.tar --region $REGION | grep DRL-IPOPP_5.0.tar.gz

  if [ "$?" = "0" ] ; then
    echo "Downloading DRL-IPOPP_5.0.tar.gz from S3 Bucket: ${S3_BUCKET}"
    aws s3 cp s3://${S3_BUCKET}/software/IPOPP/DRL-IPOPP_5.0.tar.gz /home/ipopp/DRL-IPOPP_5.0.tar.gz --region $REGION
  fi

else
  echo "DRL-IPOPP_5.0.tar.gz already exists. Skipping download"
fi

if [ ! -e /home/ipopp/drl/tools/services.sh ]; then
  echo "Installing IPOPP software"
  cd /home/ipopp && tar -vxzf DRL-IPOPP_5.0.tar.gz
  chmod -R 755 /home/ipopp/IPOPP
  cd /home/ipopp/IPOPP && ./install_ipopp.sh
else
  echo "/home/ipopp/drl/tools/services.sh already exists. Skipping Install"
fi

echo "Listing IPOPP Versions"
/home/ipopp/drl/tools/list_version_info.sh

IPOPP_CHECK=$(/home/ipopp/drl/tools/list_version_info.sh | grep IPOPP)
echo "Version: $IPOPP_CHECK"

echo "IPOPP installation finished"

echo ""
echo "======================================================================"
echo ""
echo " Initial configuration complete."
echo " This instance will now auto-start ipopp-ingest.sh each time it is started"
echo ""
echo " IPOPP Configuration:"
echo " By default IPOPP will only create level 1A and level 1B data products"
echo " To configure IPOPP to create level 2 data products,"
echo "   the relevant level 2 SPAs must be enabled in the IPOPP dashboard"
echo ""
echo " Restart the instance to make sure the instalation completed succesfully." 
echo "======================================================================"

