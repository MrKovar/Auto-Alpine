#!/bin/sh

usage() {
	cat <<-__EOF__
		usage: auto-alpine [-hsdk]

		Helps kickstart a quick and automated install alpine on a specified disk.
		 -h  Show this help
		 -s  Set new ssh port (default is 22)
         -d  Disable root login for ssh
         -k  Disable root login for ssh except for key login
        
	__EOF__
	exit $1
}

while getopts "s:hdk" option; do
    case $option in
    h) usage 0 ;;
    s) new_ssh_port="$OPTARG" ;;
    d) disable_root_login="$OPTIND" ;;
    k) login_via_key="$OPTIND" ;;
    esac
done

if [ ! -z "$new_ssh_port" ]; then
    printf "Setting ssh port to $new_ssh_port ..."
    sed -i "s/#Port 22/Port $new_ssh_port/g" /etc/ssh/sshd_config
    printf "Done!\n"
fi

if [ ! -z "login_via_key" ]; then
    printf "Disabling root login for ssh except for key login ..."
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
    printf "Done!\n"
fi

if [ ! -z "$disable_root_login" ]; then
    printf "Disabling root login for ssh ..."
    sed -i 's/PermitRootLogin yes/#PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
    printf "Done!\n"
fi

echo "Restarting sshd ..."
rc-service sshd restart
printf "Done!\n"

echo "Securing SSH completed!"