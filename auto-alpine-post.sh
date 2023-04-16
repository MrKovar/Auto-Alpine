#!/bin/sh

default_eth0="
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
"

usage() {
	cat <<-__EOF__
		usage: auto-alpine-post [[-hadnot]] 

		Set up alpine linux after installation. Much more self explanatory than auto-alpine.sh.
		 -h  Show this help
         -a  Install all below options
         -d  Install docker
         -n  Install nano
         -o  Setup openssh
         -t  Setup tunnels to enable passing vpn through docker

	__EOF__
	exit $1
}

while getopts "hadnot" option; do
    case $option in
    h) usage 0 ;;
    a) all="$OPTIND" ;;
    d) docker="$OPTIND" ;;
    n) nano="$OPTIND" ;;
    o) openssh="$OPTIND" ;;
    t) tunnel="$OPTIND" ;;
    esac
done

default_eth0="
    auto lo
    iface lo inet loopback

    auto eth0
    iface eth0 inet dhcp
    "

echo "Adding desired values to world file ..."
if [[ ! -z "$all" || ! -z "$docker" ]]; then
    echo "openrc" >> /etc/apk/world
    echo "docker" >> /etc/apk/world
    echo "docker-cli-compose" >> /etc/apk/world
fi
if [[ ! -z "$all" || ! -z "$nano" ]]; then
    echo "nano" >> /etc/apk/world
fi
if [[ ! -z "$all" || ! -z "$tunnel" ]]; then
    echo "iproute2" >> /etc/apk/world
fi
printf "Done!\n"

echo "Creating temporary interfaces file ..."
touch interfaces-file
echo "$default_eth0" > interfaces-file
printf "Done!\n"

echo "RE-Setting up interfaces ..."
setup-interfaces -i < interfaces-file
printf "Done!\n"

echo "Setting DNS to Cloudflare ..."
printf "\n" | setup-dns -n 1.1.1.1
printf "Done!\n"

echo "Restarting networking services ..."
/etc/init.d/networking restart

echo "Enabling networking service to start on boot..."
rc-update add networking
printf "Done!\n"

echo "Setting timezone to UTC ..."
setup-timezone -z UTC
printf "Done!\n"

echo "Setting up SSH ..."
setup-sshd -c openssh
printf "Done!\n"

if [[ ! -z "$all" || ! -z "$openssh" ]]; then
    printf "Configuring SSH to allow password login temporarily ..."
    sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/g" /etc/ssh/sshd_config
    printf "Done!\n"

    echo "Restart sshd service ..."
    /etc/init.d/sshd restart
    printf "Done!\n"

    echo "Enabling sshd service to start on boot..."
    rc-update add sshd boot
    printf "Done!\n"
fi

echo "Installing desired software via world ..."
apk update
apk add 
printf "Done!\n"

if [[ ! -z "$all" || ! -z "$docker" ]]; then
    echo "Enabling Docker service to start on boot..."
    rc-update add docker boot
    printf "Done!\n"

    echo "Start Docker service ..."
    /etc/init.d/docker start
    printf "Done!\n"

    echo "Adding new user to docker group and enabling non-root docker..."
    addgroup $new_user docker
    rc-update add cgroups
    printf "Done!\n"
fi

echo "Allowing dev/tun/tap ..."
if [[ ! -z "$all" || ! -z "$tunnel" ]]; then
    modprobe tun
fi
printf "Done!\n"


echo "Setting next boot motd ..."
echo > /etc/motd
echo "Okay hear me out, Alpine, but automated!" >> /etc/motd
echo -en "\n\n\n\n" >> /etc/motd
printf "Done!\n"

if [[ ! -z "$all" || ! -z "$openssh" ]]; then
    printf "You can now login via SSH with the root password you set earlier.\n"
    printf "IMPORTANT! It is HIGHLY recommended that you set an SSH key for your user and"
    printf "disable ssh root login for security reasons (or at least set login via SSH key only)."
    printf "Please run auto-alpine-secure.sh when you have used ssh-copy-id to copy your key to the OS.\n"
    read -p "Press enter to confirm you have read this message and understand the risks of leaving ssh root login enabled."
fi

printf "Installation Complete! Thanks again for using auto-alpine!\n"

