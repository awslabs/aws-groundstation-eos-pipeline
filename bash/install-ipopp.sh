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

SatelliteName=$1
S3_BUCKET=$2
IPOPP_PASSWORD=$3
REGION=$(curl -s 169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')

echo "Region: $REGION"
echo "S3 Bucket: $S3_BUCKET"

echo "Installing IPOPP pre-reqs"
yum update -y
yum install -y wget nano libaio tcsh bc ed rsync perl java libXp libaio-devel
yum install -y /lib/ld-linux.so.2
yum install -y epel-release
yum install -y python-pip python-devel
yum groupinstall -y 'development tools'
yum install -y ImageMagick
yum install -y python3-pip
pip install --upgrade pip --user || pip3 install --upgrade pip --user
pip install awscli --upgrade --user
pip3 install awscli --upgrade --user
export PATH=~/.local/bin:$PATH
source ~/.bash_profile

echo "Creating ipopp user"
adduser ipopp
sudo usermod -aG wheel ipopp

echo "Updating nproc limit"
echo "* soft nproc 65535" >> /etc/security/limits.d/20-nproc.conf

echo "Install the AWSCLI for the ipopp user"
runuser -l ipopp -c "pip3 install awscli --upgrade --user"


if [ ! -e /home/ipopp/DRL-IPOPP_4.0.tar.gz ]; then

  aws s3 ls s3://${S3_BUCKET}/software/IPOPP/DRL-IPOPP_4.0.tar --region $REGION | grep DRL-IPOPP_4.0.tar.gz

  if [ "$?" == "0" ] ; then
    echo "Downloading DRL-IPOPP_4.0.tar.gz from S3 Bucket: ${S3_BUCKET}"
    aws s3 cp s3://${S3_BUCKET}/software/IPOPP/DRL-IPOPP_4.0.tar.gz . --no-progress --region $REGION
  else
    echo "DRL-IPOPP_4.0.tar.gz not found in S3 Bucket. Downloading downloader_ipopp_4.0.sh from S3 Bucket: ${S3_BUCKET}"
    aws s3 cp s3://${S3_BUCKET}/software/IPOPP/downloader_ipopp_4.0.sh . --region $REGION
    chmod +x downloader_ipopp_4.0.sh
    ./downloader_ipopp_4.0.sh
  fi

else
  echo "DRL-IPOPP_4.0.tar.gz already exists. Skipping download"
fi

if [ ! -e /home/ipopp/drl/tools/services.sh ]; then
  echo "Starting IPOPP install"
  mkdir -p /home/ipopp
  mv DRL-IPOPP_4.0.tar.gz /home/ipopp
  cd /home/ipopp
  echo "Extracting IPOPP software"
  tar -vxzf DRL-IPOPP_4.0.tar.gz
  chmod -R 755 /home/ipopp/IPOPP
  chown -R ipopp:ipopp /home/ipopp/IPOPP
  echo "Installing IPOPP software"
  runuser -l ipopp -c "cd /home/ipopp/IPOPP && ./install_ipopp.sh"
else
  echo "/home/ipopp/drl/tools/services.sh already exists. Skipping Install"
fi

echo "Install IPOPP IMAP Patch"
cd /home/ipopp/drl
aws s3 cp s3://${S3_BUCKET}/software/IMAPP/IMAPP_3.1.1_SPA_1.4_PATCH_2.tar.gz . --region $REGION
chmod 755 IMAPP_3.1.1_SPA_1.4_PATCH_2.tar.gz
chown ipopp:ipopp IMAPP_3.1.1_SPA_1.4_PATCH_2.tar.gz
runuser -l ipopp -c "cd /home/ipopp/drl && ./tools/install_patch.sh IMAPP_3.1.1_SPA_1.4_PATCH_2.tar.gz -dontStop"

echo "Install IPOPP Patch 1"
cd /home/ipopp/drl
aws s3 cp s3://${S3_BUCKET}/software/IPOPP/DRL-IPOPP_4.0_PATCH_1.tar.gz . --region $REGION
chmod 755 DRL-IPOPP_4.0_PATCH_1.tar.gz
chown ipopp:ipopp DRL-IPOPP_4.0_PATCH_1.tar.gz
runuser -l ipopp -c "cd /home/ipopp/drl && ./tools/install_patch.sh DRL-IPOPP_4.0_PATCH_1.tar.gz -dontStop"

echo "Increasing java heap space for BlueMarble SPA"
FILES=(
h2g.sh
CopyGeotiffTags.sh
OverlayFires.sh
OverlayFireVectors.sh
OverlayShapeFile.sh
)

for FILE in ${FILES[@]}; do
  echo "Backing up file: $FILE"
  cp /home/ipopp/drl/SPA/BlueMarble/algorithm/h2g/bin/${FILE} /home/ipopp/drl/SPA/BlueMarble/algorithm/h2g/bin/${FILE}.bak
  echo "Increasing java heap space in file: $FILE"
  sed -i "s,-Xmx[0-9]g,-Xmx8g,g" /home/ipopp/drl/SPA/BlueMarble/algorithm/h2g/bin/${FILE}
done

echo "Installing Tiger VNC Server"
yum groupinstall -y "Server with GUI"
systemctl set-default graphical.target
systemctl default -f --no-block
yum install -y tigervnc-server

echo "Setting ipopp user password"
echo "ipopp:${IPOPP_PASSWORD}" | chpasswd

echo "Setting ipopp user vnc password"
mkdir -p /home/ipopp/.vnc
echo ${IPOPP_PASSWORD} | vncpasswd -f > /home/ipopp/.vnc/passwd
chown -R ipopp:ipopp /home/ipopp/.vnc
chmod 0600 /home/ipopp/.vnc/passwd

echo "IPOPP installation finished"

echo "Starting vncserver −xstartup bash"
runuser -l ipopp -c "vncserver"

echo "Adding logging to rc.local"
chmod +x /etc/rc.d/rc.local
echo "exec > >(tee /var/log/rc.local.log) 2>&1" >> /etc/rc.local

echo "Adding vncserver to rc.local"
echo "runuser -l ipopp -c \"vncserver\"" >> /etc/rc.local

echo "Creating ipopp logfile"
touch /opt/aws/groundstation/bin/ipopp-ingest.log
chmod 777 /opt/aws/groundstation/bin/ipopp-ingest.log

echo "Adding IPOPP ingest to rc.local"
echo "runuser -l ipopp -c \"/opt/aws/groundstation/bin/ipopp-ingest.sh ${SatelliteName} ${S3_BUCKET} | tee /opt/aws/groundstation/bin/ipopp-ingest.log 2>&1\"" >> /etc/rc.local

echo ""
echo "======================================================================"
echo ""
echo " Initial configuration complete."
echo " This instance will now auto-start ipopp-ingest.sh each time it is started"
echo " To configure the instance to auto-shut down, edit /etc/rc.local:"
echo "   add '&& systemctl poweroff -i' to the end of the ipopp-ingest.sh line"
echo ""
echo " IPOPP Configuration:"
echo " By default IPOPP will only create level 1A and level 1B data products"
echo " To configure IPOPP to create level 2 data products,"
echo "   the relevant level 2 SPAs must be enabled in the IPOPP dashboard"
echo ""
echo "======================================================================"

#echo "Starting IPOPP Ingest"
#runuser -l ipopp -c "/opt/aws/groundstation/bin/ipopp-ingest.sh ${SatelliteName} ${S3_BUCKET} | tee /opt/aws/groundstation/bin/ipopp-ingest.log 2>&1"
