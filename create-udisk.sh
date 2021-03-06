#!/bin/bash
#description: create USB startup Disk used for deploying estuary.
#author: wangyanliang
#date: August 12, 2015

cwd=`dirname $0`
. $cwd/common.sh

export LANG=C


# Determine the absolute path to the executable
# EXE will have the PWD removed so we can concatenate with the PWD safely
PWD=`pwd`
EXE=$(echo $0 | sed "s/.*\///")
EXEPATH="$PWD"/"$EXE"
clear

entry_header() {
cat << EOF
-------------------------------------------------------------------------------
setup package script
This script will make sure you have the proper host support packages installed
This script requires administrator priviliges (sudo access) if packages are to be installed.
-------------------------------------------------------------------------------
EOF
}

exit_footer() {
cat << EOF
--------------------------------------------------------------------------------
Package verification and installation successfully completed
--------------------------------------------------------------------------------
EOF
}

entry_header

to_install_packages="jq parted dosfstools"
install_packages to_install_packages
# Print the exit statement to the console
exit_footer

cat << EOM

################################################################################

This script will create a bootable USB Disk.

Example:
 $ sudo ./create-udisk.sh

Formatting can be skipped if the USB Disk is already formatted and
partitioned properly.

################################################################################

EOM

AMIROOT=`whoami | awk {'print $1'}`
if [ "$AMIROOT" != "root" ] ; then

	echo "	**** Error *** must run script with sudo"
	echo ""
	exit
fi

THEPWD=$EXEPATH
PARSEPATH=`echo $THEPWD | grep -o -E 'estuary'`

if [ "$PARSEPATH" != "" ] ; then
PATHVALID=1
else
PATHVALID=0
fi

default_config=$cwd/estuarycfg.json
echo "--------------------------------------------------------------------------------"
echo "Please specify estuary config file (press return to use:$default_config)"
read -p "[ $default_config ] " CFGFILE

if [ ! -n "$CFGFILE" ]; then
    CFGFILE=$default_config
fi
echo "--------------------------------------------------------------------------------"
parse_config $CFGFILE

DISTROS=()
idx=0
idx_en=0
install=`jq -r ".distros[$idx].install" $CFGFILE`
while [ x"$install" != x"null" ];
do
    name=`jq -r ".distros[$idx].name" $CFGFILE`
    value=`jq -r ".distros[$idx].install" $CFGFILE`
    case $name in
        "Ubuntu")
        ubuntu_en=$value
        ;;
        "OpenSuse")
        opensuse_en=$value
        ;;
        "Fedora")
        fedora_en=$value
        ;;
        "Debian")
        debian_en=$value
        ;;
        *)
        ;;
    esac
    let idx=$idx+1
    install=`jq -r ".distros[$idx].install" $CFGFILE`
done

check_for_udisk()
{
    # find the avaible SD cards
    ROOTDRIVE=`mount | grep 'on / ' | awk {'print $1'} |  cut -c6-8`
    PARTITION_TEST=`cat /proc/partitions | grep -v $ROOTDRIVE | grep '\<sd.\>\|\<mmcblk.\>' | grep -n ''`
    if [ "$PARTITION_TEST" = "" ]; then
        echo -e "Please insert a USB disk to continue\n"
        while [ "$PARTITION_TEST" = "" ]; do
            read -p "Type 'y' to re-detect the USB disk or 'n' to exit the script: " REPLY
            if [ "$REPLY" = 'n' ]; then
                exit 1
            fi
            ROOTDRIVE=`mount | grep 'on / ' | awk {'print $1'} |  cut -c6-8`
            PARTITION_TEST=`cat /proc/partitions | grep -v $ROOTDRIVE | grep '\<sd.\>\|\<mmcblk.\>' | grep -n ''`
        done
    fi
}

populate_2_partitions() {
    ENTERCORRECTLY="0"
	
    while [ $ENTERCORRECTLY -ne 1 ]
	do
		#read -e -p 'Enter path where USB disk tarballs were downloaded : '  TARBALLPATH
        TARBALLPATH="$PWD"/"udisk_images"
        echo ""
		ENTERCORRECTLY=1
		if [ -d $TARBALLPATH ]
		then
			echo "Directory exists"
			echo ""
			echo "This directory contains:"
			ls $TARBALLPATH
			echo ""
			read -p 'Is this correct? [y/n] : ' ISRIGHTPATH
				case $ISRIGHTPATH in
				"y" | "Y") ;;
				"n" | "N" ) ENTERCORRECTLY=0;continue;;
				*)  echo "Please enter y or n";ENTERCORRECTLY=0;continue;;
				esac
		else
			echo "Invalid path make sure to include complete path"
			ENTERCORRECTLY=0
            continue
		fi
        # Check that tarballs were found
        if [ ! -e "$TARBALLPATH""/boot.tar.gz" ]
        then
            echo "Could not find boot.tar.gz as expected.  Please"
            echo "point to the directory containing the boot.tar.gz"
            ENTERCORRECTLY=0
            continue
        fi

        if [ ! -e "$TARBALLPATH""/udisk_rootfs.tar.gz" ]
        then
            echo "Could not find udisk_rootfs.tar.gz as expected.  Please"
            echo "point to the directory containing the rootfs.tar.gz"
            ENTERCORRECTLY=0
            continue
        fi
       
       
	done

        # Make temporary directories and untar mount the partitions
        mkdir $PWD/boot
        mkdir $PWD/rootfs
        mkdir $PWD/tmp

        mount -t vfat ${DRIVE}${P}1 boot
        mount -t ext4 ${DRIVE}${P}2 rootfs

        # Remove any existing content in case the partitions were not
        # recreated
        sudo rm -rf boot/*
        sudo rm -rf rootfs/*

        # Extract the tarball contents.
cat << EOM

################################################################################
        Extracting boot partition tarball

################################################################################
EOM
        untar_progress $TARBALLPATH/boot.tar.gz tmp/
        if [ -e "./tmp/Image" ]
        then
            cp ./tmp/Image boot/
        fi
        cp -rf ./tmp/* boot/

cat << EOM

################################################################################
        Extracting rootfs partition tarball

################################################################################
EOM
        untar_progress $TARBALLPATH/udisk_rootfs.tar.gz rootfs/

        cp_distros rootfs

        cp -a sys_setup.sh rootfs/sys_setup/bin
        cp -a common.sh rootfs/sys_setup/bin
        cp -a find_disk.sh rootfs/sys_setup/bin
        cp -a $CFGFILE rootfs/sys_setup/bin/estuarycfg.json

        touch rootfs/etc/profile.d/antoStartUp.sh
        chmod a+x rootfs/etc/profile.d/antoStartUp.sh
cat > rootfs/etc/profile.d/antoStartUp.sh << EOM
#!/bin/bash

pushd /sys_setup/bin
sudo ./sys_setup.sh
popd
EOM
        umount boot rootfs
        sync;sync

        # Clean up the temp directories
        rm -rf boot rootfs tmp
}


# find the avaible SD cards
ROOTDRIVE=`mount | grep 'on / ' | awk {'print $1'} |  cut -c6-9`
if [ "$ROOTDRIVE" = "root" ]; then
    ROOTDRIVE=`readlink /dev/root | cut -c1-3`
else
    ROOTDRIVE=`echo $ROOTDRIVE | cut -c1-3`
fi

PARTITION_TEST=`cat /proc/partitions | grep -v $ROOTDRIVE | grep '\<sd.\>\|\<mmcblk.\>' | grep -n ''`
# Check for available mounts
check_for_udisk

echo -e "\nAvailible Drives to write images to: \n"
echo "#  major   minor    size   name "
cat /proc/partitions | grep -v $ROOTDRIVE | grep '\<sd.\>\|\<mmcblk.\>' | grep -n ''
echo " "

DEVICEDRIVENUMBER=
while true;
do
	read -p 'Enter Device Number or 'n' to exit: ' DEVICEDRIVENUMBER
	echo " "
        if [ "$DEVICEDRIVENUMBER" = 'n' ]; then
                exit 1
        fi

        if [ "$DEVICEDRIVENUMBER" = "" ]; then
                # Check to see if there are any changes
                check_for_udisk
                echo -e "These are the Drives available to write images to:"
                echo "#  major   minor    size   name "
                cat /proc/partitions | grep -v $ROOTDRIVE | grep '\<sd.\>\|\<mmcblk.\>' | grep -n ''
                echo " "
               continue
        fi

	DEVICEDRIVENAME=`cat /proc/partitions | grep -v 'sda' | grep '\<sd.\>\|\<mmcblk.\>' | grep -n '' | grep "${DEVICEDRIVENUMBER}:" | awk '{print $5}'`
	if [ -n "$DEVICEDRIVENAME" ]
	then
	        DRIVE=/dev/$DEVICEDRIVENAME
	        DEVICESIZE=`cat /proc/partitions | grep -v 'sda' | grep '\<sd.\>\|\<mmcblk.\>' | grep -n '' | grep "${DEVICEDRIVENUMBER}:" | awk '{print $4}'`
		break
	else
		echo -e "Invalid selection!"
                # Check to see if there are any changes
                check_for_udisk
                echo -e "These are the only Drives available to write images to: \n"
                echo "#  major   minor    size   name "
                cat /proc/partitions | grep -v $ROOTDRIVE | grep '\<sd.\>\|\<mmcblk.\>' | grep -n ''
                echo " "
	fi
done

echo "$DEVICEDRIVENAME was selected"
#Check the size of disk to make sure its under 16GB
if [ $DEVICESIZE -lt 7000000 ] ; then
cat << EOM

################################################################################

		**********WARNING**********

	Selected Device is less than 8GB
    Please plug in a USB Disk greater than 8GB.
################################################################################

EOM

exit 1

fi
echo ""

DRIVE=/dev/$DEVICEDRIVENAME
NUM_OF_DRIVES=`df | grep -c $DEVICEDRIVENAME`

# This if statement will determine if we have a mounted sdX or mmcblkX device.
# If it is mmcblkX, then we need to set an extra char in the partition names, 'p',
# to account for /dev/mmcblkXpY labled partitions.
if [[ ${DEVICEDRIVENAME} =~ ^sd. ]]; then
	echo "$DRIVE is an sdx device"
    umount ${DRIVE}${P}1
    cmd_str="parted $DRIVE rm 1"
    echo "initialize..."${DRIVE}${P}1
    eval $cmd_str
	P=''
else
	echo "$DRIVE is an mmcblkx device"
	P='p'
fi

if [ "$NUM_OF_DRIVES" != "0" ]; then
        echo "Unmounting the $DEVICEDRIVENAME drives"
		c=`cat /proc/partitions | grep -v 'sda' | grep "$DEVICEDRIVENAME." | grep -n '' | awk '{print $5}' | cut -c4`
		START_OF_DRIVES=$c
        for ((; c<"$NUM_OF_DRIVES" + "$START_OF_DRIVES"; c++ ))
        do
                unmounted=`df | grep '\<'$DEVICEDRIVENAME$P$c'\>' | awk '{print $1}'`
                if [ -n "$unmounted" ]
                then
                     echo " unmounted ${DRIVE}$P$c"
                     sudo umount -f ${DRIVE}$P$c
                fi

        done
fi

# Refresh this variable as the device may not be mounted at script instantiation time
# This will always return one more then needed
NUM_OF_PARTS=`cat /proc/partitions | grep -v 'sda' | grep -c $DEVICEDRIVENAME`
c=`cat /proc/partitions | grep -v 'sda' | grep "$DEVICEDRIVENAME." | grep -n '' | awk '{print $5}' | cut -c4`
START_OF_DRIVES=$c
for (( ; c<"$NUM_OF_PARTS" + "$START_OF_DRIVES" - 1; c++ ))
do
        SIZE=`cat /proc/partitions | grep -v 'sda' | grep '\<'$DEVICEDRIVENAME$P$c'\>'  | awk '{print $3}'`
        echo "Current size of $DEVICEDRIVENAME$P$c $SIZE bytes"
done

# check to see if the device is already partitioned
c=$START_OF_DRIVES
for (( ; c<"$NUM_OF_PARTS" + "$START_OF_DRIVES" - 1; c++ ))
do
	eval "SIZE$c=`cat /proc/partitions | grep -v 'sda' | grep '\<'$DEVICEDRIVENAME$P$c'\>'  | awk '{print $3}'`"
done

PARTITION="0"
if [ -n "$SIZE1" -a -n "$SIZE2" ] ; then
	if  [ "$SIZE1" -gt "72000" -a "$SIZE2" -gt "700000" ]
	then
		PARTITION=1
	fi
else
	echo "USB disk is not correctly partitioned"
	PARTITION=0
	PARTS=0
fi


#Partition is found
if [ "$PARTITION" -eq "1" ]
then
cat << EOM

################################################################################

   Detected device has $PARTS partitions already

################################################################################

EOM

	ENTERCORRECTLY=0
	while [ $ENTERCORRECTLY -ne 1 ]
	do
		read -p 'Would you like to re-partition the drive anyways [y/n] : ' CASEPARTITION
		echo ""
		echo " "
		ENTERCORRECTLY=1
		case $CASEPARTITION in
		"y")  echo "Now partitioning $DEVICEDRIVENAME ...";PARTITION=0;;
		"n")  echo "Skipping partitioning";;
		*)  echo "Please enter y or n";ENTERCORRECTLY=0;;
		esac
		echo ""
	done

fi

#Partition is not found, choose to partition 2 or 3 segments
if [ "$PARTITION" -eq "0" ]
then
cat << EOM

################################################################################

	USB Disk will be partitioned with boot and rootfs.

	****WARNING**** continuing will erase all data on $DEVICEDRIVENAME

################################################################################

EOM
	ENTERCORRECTLY=0
	while [ $ENTERCORRECTLY -ne 1 ]
	do

		read -p 'Are you sure to partition [y/n] : ' CASEPARTITIONNUMBER
		echo ""
		echo " "
		ENTERCORRECTLY=1
		case $CASEPARTITIONNUMBER in
		"y")  echo "Now partitioning $DEVICEDRIVENAME with 2 partitions...";PARTITION=2;;
		"n")  exit;;
		*)  echo "Please enter y or n";ENTERCORRECTLY=0;;
		esac
		echo " "
	done
fi


#Section for partitioning the drive


#create only 2 partitions
if [ "$PARTITION" -eq "2" ]
then

# Set the PARTS value as well
PARTS=2
cat << EOM

################################################################################

		Now making 2 partitions

################################################################################

EOM
dd if=/dev/zero of=$DRIVE bs=1024 count=262144

if ! ( parted $DRIVE mklabel gpt ); then
	echo "configure $DRIVE label as gpt FAIL"
	exit
fi

if ! ( parted $DRIVE mkpart uefi 1 256;set 1 boot on ); then
	echo "mkpart uefi boot ERR"
	exit
else
	echo "mkpart uefi boot ok"
fi

cat << EOM

################################################################################

		Partitioning Boot

################################################################################
EOM
	mkfs.vfat -F 32 -n "boot" ${DRIVE}${P}1
cat << EOM

################################################################################

		Partitioning rootfs

################################################################################
EOM
partition_size=$(($DEVICESIZE/1000-1024))
cmd_str="parted $DRIVE mkpart rootfs 256M ${partition_size}M"
echo -n "make root partition by "$cmd_str
eval $cmd_str

	mkfs.ext4 -L "rootfs" ${DRIVE}${P}2
	sync
	sync
	INSTALLSTARTHERE=n
fi



#Break between partitioning and installing file system
cat << EOM


################################################################################

   Partitioning is now done
   Continue to install filesystem or select 'n' to safe exit

   **Warning** Continuing will erase files any files in the partitions

################################################################################


EOM

pushd ..
if [ ! -d build/$build_PLATFORM/binary ]; then
    # Make sure that the build.sh file exists
    if [ -f $PWD/estuary/build.sh ]; then
        $PWD/estuary/build.sh -p $build_PLATFORM -d Ubuntu
        echo "execute build.sh"
    else
        echo "build.sh does not exist in the directory"
        exit 1
    fi
fi
popd

ENTERCORRECTLY=0
while [ $ENTERCORRECTLY -ne 1 ]
do
	read -p 'Would you like to continue? [y/n] : ' EXITQ
	echo ""
	echo " "
	ENTERCORRECTLY=1
	case $EXITQ in
	"y") ;;
	"n") exit;;
	*)  echo "Please enter y or n";ENTERCORRECTLY=0;;
	esac
done

if [ "$PARTS" -eq "2" ]
then
    mkdir $PWD/udisk_images 2> /dev/null
    mkdir $PWD/tmp 2> /dev/null
    mkdir -p tmp/boot/EFI/GRUB2 2> /dev/null
    mkdir -p tmp/distro 2> /dev/null
    mkdir -P $PWD/distro/$build_PLATFORM 2> /dev/null

    boot_dev=${DRIVE}${P}1
    boot_uuid=`ls -al /dev/disk/by-uuid/ | grep "${boot_dev##*/}" | awk {'print $9'}`
    rootfs_dev2=${DRIVE}${P}2
    rootfs_partuuid=`ls -al /dev/disk/by-partuuid/ | grep "${rootfs_dev2##*/}" | awk {'print $9'}`
    touch tmp/grub.cfg
cat > tmp/grub.cfg << EOM
#
# Sample GRUB configuration file
#

# Boot automatically after 0 secs.
set timeout=5

# By default, boot the Euler/Linux
set default=ubuntu_usb

# For booting GNU/Linux
menuentry "Ubuntu USB" --id ubuntu_usb {
    search --no-floppy --fs-uuid --set ${boot_uuid}
	linux /Image rdinit=/init root=PARTUUID=$rootfs_partuuid rootdelay=10 rootfstype=ext4 rw console=ttyS0,115200 earlycon=uart8250,mmio32,0x80300000 ip=::::::dhcp
	devicetree /hip05-d02.dtb
}
EOM

    cp -a ../build/$build_PLATFORM/binary/grub* tmp/boot/EFI/GRUB2
    rm -f tmp/boot/EFI/GRUB2/grub.cfg
    mv tmp/grub.cfg tmp/boot/
    cp -a ../build/$build_PLATFORM/binary/Image_$build_PLATFORM tmp/boot/Image
    cp -a ../build/$build_PLATFORM/binary/hip05-d02.dtb tmp/boot
    pushd tmp/boot
    tar -czf boot.tar.gz ./*
    popd
    cp -a tmp/boot/boot.tar.gz udisk_images/ 
    if [ ! -f  udisk_images/udisk_rootfs.tar.gz ]
    then
        wget -P udisk_images/ -c http://7xjz0v.com1.z0.glb.clouddn.com/dist/udisk_rootfs.tar.gz
    fi

    rm -rf tmp
    
    populate_2_partitions

    echo " "
    echo "Operation Finished"
    echo " "
    exit 0
fi

