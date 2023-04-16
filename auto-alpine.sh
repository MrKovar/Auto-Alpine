#!/bin/sh

setup_gpt_disk() {
    printf "Installing required packages for setting up GPT disk ..."
    apk add lvm2 gptfdisk sgdisk
    printf "Done!\n"

    printf "Creating GPT partition table via gdisk..."

    printf "%s\n" "$disk_name" "o" "y" "n" "1" "" "+$boot_partition_size" "ef02" "n" "2" "" "+$file_system_partition_size" "8300" "n" "3" "" "" "8e00" "x" "a" "2" "2" "" "w" "y"| gdisk

    printf "Refreshing partition table ..."
    partprobe
    printf "Done!\n"

    partition_2="${disk_name}2"
    partition_3="${disk_name}3"

    pvcreate $partition_3
    vgcreate vg00 $partition_3

    lvcreate -n swap -C y -L +$swap_partition_size vg00
    lvcreate -n rootfs -l100%FREE vg00
    rc-update add lvm

    vgchange -ay

    mkfs.ext3 /dev/sda2
    mkfs.ext4 /dev/vg00/rootfs
    s# mkswap /dev/vg00/swapg

    mount -t ext4 /dev/vg00/rootfs /mnt
    mkdir /mnt/boot
    mount -t ext3 $partition_2 /mnt/boot

    printf "Done!\n"
}

usage() {
	cat <<-__EOF__
		usage: auto-alpine [-hg] [-d DISK_NAME] [-r NEW_ROOT_PASSWORD] [-u NEW_USER]
        [-p NEW_USER_PASS] [-b BOOT_PARTITION_SIZE] [-f FILE_SYSTEM_PARTITION_SIZE] [-s SWAP_PARTITION_SIZE]
        [-n NO_PROMPT_REBOOT]

		Helps kickstart a quick and automated install alpine on a specified disk.
		 -h  Show this help
		 -g  Use GPT partition table instead of MBR for default installation
        
        By default on Alpine Linux the setup-disk command will create a MBR partition table which
        is not compatable with disk sizes greater than 2TB. To create a GPT partition table instead
        use the -g flag. If IS_GPT is not specified, the default partition table will be MBR and will
        fail if the disk size is greater than 2TB.

        This script will not automatically reboot when installation is complete to verify installation or
        to change other attributes manual. To set the system to reboot
        on completion, use the -n flag. On root login after reboot, you should run the follow-up script to 
        complete the installation with preferred options.
	__EOF__
	exit $1
}

while getopts "hi:r:u:p:gn:d:b:f:sn" option; do
    case $option in
        h) usage 0
            exit ;;
        i) hostname="$OPTARG" ;;
        r) new_root_pass="$OPTARG" ;;
        u) new_user="$OPTARG" ;;
        p) new_user_pass="$OPTARG" ;;
        g) is_gpt="$OPTIND" ;;
        d) disk_name="$OPTARG" ;;
        b) boot_partition_size="$OPTARG" ;;
        f) file_system_partition_size="$OPTARG" ;;
        s) swap_partition_size="$OPTARG" ;;
        n) no_prompt_reboot="$OPTIND" ;;
        # TODO: Add option to specify DNS Server other than Cloudflare as default
        # TODO: Add option to specify LVM names other than vg00 as default
        # TODO: Add option to specify Timezone other that UTC as defualt

    esac
done

default_eth0="
    auto lo
    iface lo inet loopback

    auto eth0
    iface eth0 inet dhcp
    "

if [ -z "$hostname" ]; then
    read -p "Please enter your desired hostname for alpine (e.g. localhost): " hostname
fi
if [ -z "$new_root_pass" ]; then
    read -p "Please enter a new password for the root user: " new_root_pass
fi
if [ -z "$new_user" ]; then
    read -p "Please enter a new username for non-admin user: " new_user
fi
if [ -z "$new_user_pass" ]; then
    read -p "Please enter a password for new non-admin user $new_user: " new_user_pass
fi
if [ -z "$disk_name" ]; then
    read -p "Please enter the disk you want to install alpine on (e.g. /dev/sda): " disk_name
fi
if [[ ! -z "$is_gpt" && -z "$boot_partition_size" ]]; then
    read -p "Please enter the size you want the boot partition to be using [KMG to denote units](e.g. 100M): " boot_partition_size
fi
if [[ ! -z "$is_gpt" && -z "$file_system_partition_size" ]]; then
    read -p "Please enter the size you want the file system partition to be using [KMG to denote units](e.g. 100M): " file_system_partition_size
fi
if [[ ! -z "$is_gpt" && -z "$swap_partition_size" ]]; then
    read -p "Please enter the size you want the swap partition to be using [KMG to denote units](e.g. 2G): " swap_partition_size
fi

#TODO: Regex check user input here - new function

printf "Setting hostname to $hostname ..."
setup-hostname -n $hostname
printf "Done!\n"

printf "Creating temporary interfaces file ..."
touch interfaces-file
echo "$default_eth0" > interfaces-file
printf "Done!\n"

printf "Setting up interfaces ..."
setup-interfaces -i < interfaces-file
printf "Done!\n"

printf "Restarting networking services ..."
/etc/init.d/networking restart
printf "Done!\n"

printf "Setting DNS to Cloudflare ..."
printf "\n" | setup-dns -n 1.1.1.1
printf "Done!\n"

printf "Setting timezone to UTC ..."
setup-timezone -z UTC
printf "Done!\n"

printf "Creating new user and setting password to input ..."
printf '%s\n%s\n' $new_user_pass $new_user_pass | adduser $new_user
printf "Done!\n"

printf "Setting root password to input ..."
printf '%s\n%s\n' $new_root_pass $new_root_pass | passwd root
printf "Done!\n"

printf "Finding fastest apk mirror and set it as default ..."
setup-apkrepos -f
printf "Done!\n"

echo "Adding main and community repos ..."
echo "http://dl-cdn.alpinelinux.org/alpine/v3.17/main" >/etc/apk/repositories
echo "http://dl-cdn.alpinelinux.org/alpine/v3.17/community" >>/etc/apk/repositories
apk update
printf "Done!\n"

printf "Installing tools for setup-disk ..."
apk add sfdisk syslinux e2fsprogs
printf "Done!\n"

if [ -z "$is_gpt" ]; then
    printf "Setting installation location to $disk_name ..."
    printf "%s\n" "y" | setup-disk -m sys "$disk_name"
    printf "Done!\n"
    printf "Mounting new filesystem /mnt ..."
    mount /dev/sda3 /mnt
    printf "Done!\n"
else
    setup_gpt_disk "$disk_name" "$boot_partition_size" "$file_system_partition_size" "$swap_partition_size"
    printf "Installing OS to $disk_name ..."
    printf "%s\n" "y" | setup-disk -m sys /mnt
    printf "Done!\n"

    printf "Installing new MBR to $disk_name ..."
    dd bs=440 conv=notrunc count=1 if=/usr/share/syslinux/gptmbr.bin of="$disk_name"
fi

printf "Making new home directory for new user ..."
mkdir "/mnt/home/$new_user"
printf "Done!\n"

printf "Setting new user as owner of new home directory ..."
chown -R $new_user "/mnt/home/$new_user"
printf "Done!\n"

printf "Moving follow-up scripts to new filesystem under root..."
cp auto-alpine-post.sh /mnt/root
cp auto-alpine-secure.sh /mnt/root
printf "Done!\n"

printf "Setting next boot motd ..."
echo >/mnt/etc/motd
echo "Thanks for using auto-alpine!" >>/mnt/etc/motd
echo "Please run the following commands to finish setup:" >>/mnt/etc/motd
echo "chmod +x custom-alpine-post.sh" >>/mnt/etc/motd
echo "./auto-alpine-post.sh -h" >>/mnt/etc/motd
echo "Read available options closely or add your own, then run it: " >>/mnt/etc/motd
echo "./custom-alpine-post.sh [-a all | -d docker | -o openssh | -n nano | -t tunnels]" >>/mnt/etc/motd
echo -en "\n\n\n\n" >>/mnt/etc/motd
printf "Done!\n"


if [ ! -z "$no_prompt_reboot" ]; then
    reboot
else
    read -p "Installation Complete! Press enter to continue or ctrl+c to exit to vm" blank
fi
