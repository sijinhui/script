#!/usr/bin/env bash
NEW_DISK=$1
FILE_NAME=`df -Th|grep "/$"|awk '{print $1}'`
VG_TYPE=`df -Th|grep "/$"|awk '{print $2}'`
VG_NAME=`vgdisplay |grep "VG Name"|awk '{print $3}'`

fdisk ${NEW_DISK} << diskEof
n
p



t
8e
w
diskEof
pvcreate ${NEW_DISK}1
vgextend ${VG_NAME} ${NEW_DISK}1
lvextend -l +100%FREE ${FILE_NAME}
if [ $VG_TYPE == "xfs" ];then
   xfs_growfs ${FILE_NAME}
   echo "Disk capacity expansion is finish"
else
   resize2fs ${FILE_NAME}
   echo "Disk capacity expansion is finish"
fi