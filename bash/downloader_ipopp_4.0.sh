# Provided by NASA DRL: https://directreadout.sci.gsfc.nasa.gov
# as part of the IPOPP package.
# You must register on the NASA DRL site and accept the open source agreement
# before using this software

#!/bin/bash

SName="DRL-IPOPP_4.0"
SLocation="IPOPP_V4.0"
SPackage="package.txt"
SCheckSum="md5_checksum.txt"
SegName="DRL-IPOPP_4.0-seg"

DPath="https://drl-fs-1.sci.gsfc.nasa.gov/.SOFTWARE/.${SLocation}"
Dpackage=$( wget -q -O - $DPath/${SPackage} )

echo "Dpackage URL:$Dpackage"

pdisplay ()
{
  stZ="*-----*-----*-----*-----*"
  loop=0
  while true
  do
   case "$1" in
   Downloading)
    dSUM=$( du -bc ${SegName}* 2>/dev/null | tail -1 | awk '{print $1}')
    pSUM=$(echo "${dSUM}/${2}*100" | bc -l 2>/dev/null )
    pT=$( printf "%0.0f\n" $pSUM )"%   \r   "
    ;;
   Assembling)
    dSUM=$( du -bc ${SName}.tar.gz 2>/dev/null | tail -1 | awk '{print $1}')
    pSUM=$(echo "${dSUM}/${2}*100" | bc -l 2>/dev/null )
    pT=$( printf "%0.0f\n" $pSUM )"%   \r   "
    ;;
   Verifying)
    pT="   \r   "
    ;;
   esac
    loop=$(($loop % 25))
    echo -en "\e[K"$1" ${stZ:${loop}:5} "$pT
    loop=$(($loop + 5))
    sleep 5
  done
}
kdisplay ()
{
  exec 2>/dev/null
  kill $1
}
DPath="https://drl-fs-1.sci.gsfc.nasa.gov/.SOFTWARE/.${SLocation}"
Dpackage=$( wget -q -O - $DPath/${SPackage} )
#echo "Dpackage:$Dpackage"

SegSize=$( echo $Dpackage | xargs -n 1 wget --spider 2>&1 | grep Length | awk '{sum+=$2} END {printf ("%0.0f\n", sum)}' )
pdisplay "Downloading" $SegSize &
D_id=$!
trap "kdisplay $D_id; exit" INT TERM EXIT
echo $Dpackage | xargs -n 1 -P 22 wget -q -c -N
kdisplay $D_id
pdisplay "Assembling" $SegSize &
A_id=$!
trap "kdisplay $A_id; exit" INT TERM EXIT
cat ${SegName}* > "${SName}.tar.gz"
kdisplay $A_id
pdisplay "Verifying" &
N_id=$!
trap "kdisplay $N_id; exit" INT TERM EXIT
OK=$( md5sum -c ${SCheckSum} | grep OK | wc -l )
kdisplay $N_id
if [ $OK -eq "1" ]
then
rm ${SegName}* ${SCheckSum}
echo "File successfully downloaded"
else
echo "Download failed. Please contact DRL for assistance."
fi
