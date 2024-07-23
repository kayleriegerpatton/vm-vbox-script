#!/bin/bash

# fresh_install.sh
# Author: Benjamin Twechuizen
#
# Usage: curl -s https://cdn.molecubes.com/fresh_install.sh | bash -s -- -s SERIAL
# If you need to run on a virtual server for testing, run: curl -s https://cdn.molecubes.com/fresh_install.sh | bash -s -- -v SERIAL

if [[ ! $LC_CTYPE ]]; then
	export LC_CTYPE='en_US.UTF-8'
fi
if [[ ! $LC_ALL ]]; then
	export LC_ALL='en_US.UTF-8'
fi

################################################################################
# Usage
################################################################################
ME=$(basename "$0")
function usage {
	returnCode="$1"
	echo -e "Usage: $ME -s <SERIAL> :
	[-s <SERIAL>]\t - SERIAL for the device in the form of SXXXXXX, CXXXXXX, PXXXXXX or WXXXXXX"
	exit "$returnCode"
}

## Configuration options
PACKAGEVERSION="1.6.8"
UBUNTU_VERSION="16.04"

## end

DATETIME=$(date +%Y%m%d%H%M%S)

VIRTUAL=false

################################################################################
# Terminal output helpers
################################################################################

# echo_equals() outputs a line with =
#   seq does not exist under OpenBSD
function echo_equals() {
	COUNTER=0
	while [  $COUNTER -lt "$1" ]; do
		printf '='
		(( COUNTER=COUNTER+1 ))
	done
}

# echo_title() outputs a title padded by =, in yellow.
function echo_title() {
	TITLE=$1
	if [ "$VIRTUAL" = false ]; then
		NCOLS=$(tput cols)
		NEQUALS=$(((NCOLS-${#TITLE})/2-1))
		tput setaf 3 0 0 # 3 = yellow
		echo_equals "$NEQUALS"
		printf " %s " "$TITLE"
		echo_equals "$NEQUALS"
		tput sgr0  # reset terminal
	else
		echo_equals 10
		printf " %s " "$TITLE"
		echo_equals 10
	fi
	echo
}

# echo_step() outputs a step collored in cyan, without outputing a newline.
function echo_step() {
	[ "$VIRTUAL" = true ] || tput setaf 6 0 0 # 6 = cyan
	echo -n "$1"
	echo -e "\n$1" >>"$FRESH_INSTALL_LOG"
	[ "$VIRTUAL" = true ] || tput sgr0  # reset terminal
}

# echo_step_info() outputs additional step info in cyan, without a newline.
function echo_step_info() {
	[ "$VIRTUAL" = true ] || tput setaf 6 0 0 # 6 = cyan
	echo -n " ($1)"
	echo -ne "\t($1)" >>"$FRESH_INSTALL_LOG"
	[ "$VIRTUAL" = true ] || tput sgr0  # reset terminal
}

# echo_right() outputs a string at the rightmost side of the screen.
function echo_right() {
	TEXT=$1
	echo
	[ "$VIRTUAL" = true ] || tput cuu1
	[ "$VIRTUAL" = true ] || tput cuf "$(tput cols)"
	[ "$VIRTUAL" = true ] || tput cub ${#TEXT}
	echo "$TEXT"
	echo -ne "\t$TEXT" >>"$FRESH_INSTALL_LOG"
}

# echo_failure() outputs [ FAILED ] in red, at the rightmost side of the screen.
function echo_failure() {
	[ "$VIRTUAL" = true ] || tput setaf 1 0 0 # 1 = red
	echo_right "[ FAILED ]"
	[ "$VIRTUAL" = true ] || tput sgr0  # reset terminal
}

# echo_success() outputs [ OK ] in green, at the rightmost side of the screen.
function echo_success() {
	[ "$VIRTUAL" = true ] || tput setaf 2 0 0 # 2 = green
	echo_right "[ OK ]"
	[ "$VIRTUAL" = true ] || tput sgr0  # reset terminal
}

# echo_warning() outputs a message and [ WARNING ] in yellow, at the rightmost side of the screen.
function echo_warning() {
	[ "$VIRTUAL" = true ] || tput setaf 3 0 0 # 3 = yellow
	echo_right "[ WARNING ]"
	[ "$VIRTUAL" = true ] || tput sgr0  # reset terminal
}

# exit_with_message() outputs and logs a message before exiting the script.
function exit_with_message() {
	echo
	echo "$1"
	echo -e "\n$1" >>"$FRESH_INSTALL_LOG"
	if [[ $FRESH_INSTALL_LOG && "$2" -eq 1 ]]; then
		echo "For additional information, check the install log: $FRESH_INSTALL_LOG"
	fi
	echo
	#debug_variables
	echo
	exit 1
}

# exit_with_failure() calls echo_failure() and exit_with_message().
function exit_with_failure() {
	echo_failure
	exit_with_message "FAILURE: $1" 1
}

################################################################################
# Helper functions
################################################################################

# disable output of stack changes
pushd () {
    command pushd "$@" > /dev/null
}

# disable output of stack changes
popd () {
    command popd "$@" > /dev/null
}

# use the given FRESH_INSTALL_LOG or set it to a random file in /tmp
function set_install_log() {
	if [[ ! $FRESH_INSTALL_LOG ]]; then
		export FRESH_INSTALL_LOG="fresh_install_$DATETIME.log"
	fi
	if [ -e "$FRESH_INSTALL_LOG" ]; then
		exit_with_failure "$FRESH_INSTALL_LOG already exists"
	fi
}

# command_exists() tells if a given command exists.
function command_exists() {
	command -v "$1" >/dev/null 2>&1
}

# check_fetcher() check if curl is installed
function check_fetcher() {
	echo_step "  Checking if wget is installed"
	if command_exists wget; then
		export FETCHER="wget --quiet --progress=bar --show-progress --no-check-certificate"
	else
		sudo apt install --assume-yes wget
		if ! command_exists wget; then
			exit_with_failure "'wget' is needed. Please install 'wget'."
		else
			export FETCHER="wget --quiet --progress=bar --show-progress --no-check-certificate"
		fi
	fi
	echo -e "\nfetcher: $FETCHER" >> "$FRESH_INSTALL_LOG"
	echo_success
}

function install_nvidia() {
	if [ "$VIRTUAL" = true ]; then
		echo_step "  Checking nvidia drivers disabled for virtual systems"
		echo_success
		return 0
	fi

	echo_step "  Checking nvidia drivers"
	UPDATE=true
	if command_exists nvidia-smi; then
		NVIDIA_DRIVER_VERSION=$(nvidia-smi -q | grep "Driver Version" | cut -d':' -f2 | tr -d ' ')
		NVIDIA_CUDA_VERSION=$(nvidia-smi -q | grep "CUDA Version" | cut -d':' -f2 | tr -d ' ')

		echo -e "\ncurrent installed nvidia version: $NVIDIA_DRIVER_VERSION / $NVIDIA_CUDA_VERSION" >> "$FRESH_INSTALL_LOG"

		if [ "$NVIDIA_DRIVER_VERSION" = "470.86" ] && [ "$NVIDIA_CUDA_VERSION" = "11.4" ]; then
			echo_step_info "470.86/11.4"
			UPDATE=false
		fi
	fi

	if [ "$UPDATE" = true ]; then
		PACKAGE_LOCATION=/home/dev
		echo_step_info "Installing nvidia 470.86"
		if [ ! -f $PACKAGE_LOCATION/cuda47086.run ]; then
			$FETCHER https://cdn.molecubes.com/builds/NVIDIA-Linux-x86_64-470.86.run -O $PACKAGE_LOCATION/cuda47086.run
		fi
		if [ ! -f $PACKAGE_LOCATION/cuda47086.run ]; then
			exit_with_failure "Unable to download cuda driver v470.86"
		fi
		sudo sh $PACKAGE_LOCATION/cuda47086.run --silent --no-cc-version-check
	
		NVIDIA_DRIVER_VERSION=$(nvidia-smi -q | grep "Driver Version" | cut -d':' -f2 | tr -d ' ')
		NVIDIA_CUDA_VERSION=$(nvidia-smi -q | grep "CUDA Version" | cut -d':' -f2 | tr -d ' ')

		if [ "$NVIDIA_DRIVER_VERSION" != "470.86" ] || [ "$NVIDIA_CUDA_VERSION" != "11.4" ]; then
			exit_with_failure "Installation of driver 470.86 failed."
		fi
	fi
	echo_success
}

function detect_system_type() {
	ISACQ=false
	ISRECON=false
	ISXRAY=false
	DEVICE_MODALITY=""
	HOST=$(hostnamectl | grep hostname | sed "s/.*: //")
	if [[ "$HOST" =~ "xcubeacqrecon" ]]; then
		ISACQ=true
	 	ISRECON=true
		DEVICE_MODALITY="CT"
	elif [[ "$HOST" =~ "xrayserver" ]]; then
		ISXRAY=true
		DEVICE_MODALITY="CT"
	elif [[ "$HOST" =~ "bcubeacq" ]]; then
		ISACQ=true
		DEVICE_MODALITY="PET"
	elif [[ "$HOST" =~ "bcuberecon" ]]; then
		ISRECON=true
		DEVICE_MODALITY="PET"
	elif [[ "$HOST" =~ "ycubeacq" ]]; then
		ISACQ=true
		DEVICE_MODALITY="SPECT"
	elif [[ "$HOST" =~ "ycuberecon" ]]; then
		ISRECON=true
		DEVICE_MODALITY="SPECT"
	elif [[ "$HOST" =~ "remi" ]]; then
		ISRECON=true
		DEVICE_MODALITY="REMI"
	else
		exit_with_failure "Failed to detect the system type from hostname $HOST"
	fi
	echo_step "  Detecting if the system should contain acquisition configuration and software"
	if [ "$ISACQ" = true ]; then
		echo_step_info "yes"
	else
		echo_step_info "no"
	fi
	echo_success
	echo_step "  Detecting if the system should contain reconstruction configuration and software"
	if [ "$ISRECON" = true ]; then
		echo_step_info "yes"
	else
		echo_step_info "no"
	fi
	echo_success
	echo_step "  Detecting if the system should contain xray configuration and software"
	if [ "$ISXRAY" = true ]; then
		echo_step_info "yes"
	else
		echo_step_info "no"
	fi
	echo_success
	echo -e "\nISACQ: $ISACQ" >> "$FRESH_INSTALL_LOG"
	echo -e "\nISRECON: $ISRECON" >> "$FRESH_INSTALL_LOG"
	echo -e "\nISXRAY: $ISXRAY" >> "$FRESH_INSTALL_LOG"
	echo -e "\nmodality: $DEVICE_MODALITY" >> "$FRESH_INSTALL_LOG"
}

function detect_architecture() {
	echo_step "  Detecting architecture"
	ARCHITECTURE=$(uname -m)
	export ARCHITECTURE
	echo -e "\narchitecture: $ARCHITECTURE" >> "$FRESH_INSTALL_LOG"
	echo_step_info "$ARCHITECTURE"
	echo_success
}

function detect_ubuntu_version() {
	echo_step "  Detecting ubuntu version"
	UBUNTU_VERSION=$(grep DISTRIB_RELEASE /etc/lsb-release | cut -d'=' -f2 | tr -d ' ')
	export UBUNTU_VERSION
	echo -e "\nubuntu version: $UBUNTU_VERSION" >> "$FRESH_INSTALL_LOG"
	echo_step_info "$UBUNTU_VERSION"
	echo_success
}

################################################################################
# common install functions
################################################################################

function configure_network() {
	if [ "$DEVICE_MODALITY" = "REMI" ]; then
		return
	fi
	if [ "$VIRTUAL" = true ]; then
		echo_step "  Configuring network is disabled for virtual servers"
		echo_success
		return 0
	fi
	echo_step "  Configuring network"
	if [ ! -f /etc/iptables.sav ]; then
		sudo mv /etc/iptables /etc/iptables.sav
	fi
	if ! grep -rIzl '^#![[:blank:]]*/bin/sh' /etc/rc.local ; then
		echo -e "#!/bin/sh -e" | sudo tee /etc/rc.local.temp > /dev/null
		cat /etc/rc.local | sudo tee -a /etc/rc.local.temp > /dev/null
		echo "exit 0" | sudo tee -a /etc/rc.local.temp > /dev/null
		sudo mv /etc/rc.local.temp /etc/rc.local
	fi
	sudo sed -i -e "s/del-net/del -net/" /etc/rc.local
	if [ "$DEVICE_MODALITY" = "CT" ]; then
		if ! grep -q "sleep 3" /etc/rc.local ; then
			sudo sed -i -e "s/^\(exit 0\)/sleep 3\nroute del default gw 10.0.0.2 || true\n\1/" /etc/rc.local
		fi
		if ! grep -q "dport 2245" /etc/iptables.sav ; then
			sudo sed -i "s/^\(-A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT\)$/-A FORWARD -i enp2s0 -p tcp --dport 2245 -j ACCEPT\n\1/g" /etc/iptables.sav
			sudo sed -i "s/^\(-A POSTROUTING -o enp2s0 -j MASQUERADE\)$/\1\n-A PREROUTING -i enp2s0 -p tcp --dport 2245 -j DNAT --to-destination 10.0.0.2:22/g" /etc/iptables.sav
			sudo iptables-restore < /etc/iptables.sav
		fi
	fi
	if [ "$DEVICE_MODALITY" = "PET" ]; then
		if [ "$ISACQ" = true ]; then
			if ! grep -q "dport 2245" /etc/iptables.sav ; then
				sudo sed -i "s/^\(-A FORWARD -i enp2s0 -p tcp\) -d .* \(--dport.*\)$/\1 \2/g" /etc/iptables.sav
				sudo sed -i "s/\(^.*5001.*ACCEPT$\)/-A FORWARD -i enp2s0 -p tcp --dport 2245 -j ACCEPT\n-A FORWARD -i enp2s0 -p tcp --dport 4049 -j ACCEPT\n\1\n-A FORWARD -i enp2s0 -p tcp --dport 7000 -j ACCEPT\n-A FORWARD -i enp2s0 -p tcp --dport 7001 -j ACCEPT\n-A FORWARD -i enp2s0 -p tcp --dport 50005 -j ACCEPT/g" /etc/iptables.sav
				sudo sed -i "s/\(^.*5001$\)/-A PREROUTING -i enp2s0 -p tcp --dport 2245 -j DNAT --to-destination 10.0.0.2:22\n-A PREROUTING -i enp2s0 -p tcp --dport 4049 -j DNAT --to-destination 10.0.0.2:2049\n\1\n-A PREROUTING -i enp2s0 -p tcp --dport 7000 -j DNAT --to-destination 10.0.0.2:7000\n-A PREROUTING -i enp2s0 -p tcp --dport 7001 -j DNAT --to-destination 10.0.0.2:7001\n-A PREROUTING -i enp2s0 -p tcp --dport 50005 -j DNAT --to-destination 10.0.0.2:50005/g" /etc/iptables.sav
				sudo iptables-restore < /etc/iptables.sav
			fi
			sudo grep -q "dport 2245" /etc/iptables.sav && echo_success || ( echo -e "Failed to configure network" >> "$FRESH_INSTALL_LOG" && echo_failure )
		fi
	elif [ "$DEVICE_MODALITY" = "SPECT" ]; then
		if [ "$ISACQ" = true ]; then
			if ! grep -q "dport 2245" /etc/iptables.sav ; then
				sudo sed -i "s/^\(-A FORWARD -i enp2s0 -p tcp\) -d .* \(--dport.*\)$/\1 \2/g" /etc/iptables.sav
				sudo sed -i "s/\(^.*5001.*ACCEPT$\)/-A FORWARD -i enp2s0 -p tcp --dport 2245 -j ACCEPT\n-A FORWARD -i enp2s0 -p tcp --dport 4049 -j ACCEPT\n\1\n-A FORWARD -i enp2s0 -p tcp --dport 7000 -j ACCEPT\n-A FORWARD -i enp2s0 -p tcp --dport 7001 -j ACCEPT\n-A FORWARD -i enp2s0 -p tcp --dport 50005 -j ACCEPT/g" /etc/iptables.sav
				sudo sed -i "s/\(^.*5001$\)/-A PREROUTING -i enp2s0 -p tcp --dport 2245 -j DNAT --to-destination 10.0.0.2:22\n-A PREROUTING -i enp2s0 -p tcp --dport 4049 -j DNAT --to-destination 10.0.0.2:2049\n\1\n-A PREROUTING -i enp2s0 -p tcp --dport 7000 -j DNAT --to-destination 10.0.0.2:7000\n-A PREROUTING -i enp2s0 -p tcp --dport 7001 -j DNAT --to-destination 10.0.0.2:7001\n-A PREROUTING -i enp2s0 -p tcp --dport 50005 -j DNAT --to-destination 10.0.0.2:50005/g" /etc/iptables.sav
				sudo iptables-restore < /etc/iptables.sav
			fi
			sudo grep -q "dport 2245" /etc/iptables.sav && echo_success || ( echo -e "Failed to configure network" >> "$FRESH_INSTALL_LOG" && echo_failure )
		fi
	fi
	sudo chmod a+x /etc/rc.local
	sudo /etc/rc.local
	
	echo_success
}

function common_install() {
	sudo rm -rf /home/molecubes/*
	configure_network
	install_packages
	disable_updates
	set_ntp
	update_grub
	check_sensors
	add_users
	create_directories
	enable_debugging
	
	if [ "$UBUNTU_VERSION" != "18.04" ]; then
		set_ssh_config
	fi
	if [ "$ISXRAY" = true ]; then
		create_xray_logs
		setup_ctxray_network_drives
		create_xray_files
	fi
	if [ "$ISACQ" = true ]; then
		create_acq_logs
		configure_motors
		setup_network_drives
		create_acq_files
	fi
	if [ "$ISRECON" = true ]; then
		create_recon_logs
		setup_network_drives
		create_recon_files
	fi
}

function common_ubuntu18_install() {
	set_ubuntu18_config && common_install
}

function install_packages() {
	# Install packages
	echo_step "  Installing packages"
    sudo apt-get -qq update || exit_with_failure "failed to update"
	sleep 1
	sudo apt-get -qq --assume-yes install intel-microcode build-essential lm-sensors nfs-kernel-server nfs-common gdb zip python3 python3-numpy python3-scipy || exit_with_failure "failed to install packages"
	if [ "$UBUNTU_VERSION" != "18.04" ]; then
		sudo apt-get -qq --assume-yes install libcurl3 || exit_with_failure "failed to install packages"
	fi
	if [ "$ISXRAY" = false ]; then
		sudo apt-get -qq --assume-yes install avahi-daemon autofs || exit_with_failure "failed to install packages"
	fi
	if [ "$DEVICE_MODALITY" = "REMI" ]; then
		sudo apt-get -qq --assume-yes install python3-pip python3-dev libpq-dev postgresql postgresql-contrib nginx || exit_with_failure "failed to install packages"
		sudo -H pip3 install --upgrade pip && sudo -H pip install django gunicorn psycopg2-binary && sudo -H pip install django-tables2 && sudo -H pip install django-mathfilters && sudo -H pip install python-dateutil && sudo -H pip install django-filter || exit_with_failure "failed to install pip packages"
	fi
	if [[ "$DEVICE_MODALITY" = "SPECT" && "$ISACQ" = true ]]; then
		sudo apt-get -qq --assume-yes install octave || exit_with_failure "failed to install packages"
	fi
	sleep 1
	sudo apt-get -qq update || exit_with_failure "failed to update"
	echo_success
}

function disable_updates() {
	# Disable updates
	echo_step "  Disabling updates"
	sudo sed -i "s/\(APT::Periodic::Update-Package-Lists.*\"\)1/\10/g" /etc/apt/apt.conf.d/10periodic
	sudo sed -i "s/\(APT::Periodic::Unattended-Upgrade.*\"\)1/\10/g" /etc/apt/apt.conf.d/10periodic
	echo -e "APT::Periodic::Update-Package-Lists \"0\";
APT::Periodic::Unattended-Upgrade \"0\";" | sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null
	sudo cp /etc/sysctl.conf /etc/sysctl.conf.old
	if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
		echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf > /dev/null
		echo "1" | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null
	fi
	echo_success
}

function set_ntp() {
	if [ "$VIRTUAL" = true ]; then
		echo_step "NTP is setup automatically in virtual systems"
		echo_success
		return 1
	fi

	# Set NTP
	if ! grep -q "ntp.ugent.be" /etc/systemd/timesyncd.conf; then
		echo_step "  Setting NTP"
		echo "NTP=0.pool.ntp.org 1.pool.ntp.org ntp.ubuntu.com ntp.ugent.be" | sudo tee -a /etc/systemd/timesyncd.conf > /dev/null
		sudo timedatectl set-ntp on
		sudo systemctl restart systemd-timesyncd
		sudo grep -q "ntp.ugent.be" /etc/systemd/timesyncd.conf && echo_success || ( echo -e "Failed to set NTP" >> "$FRESH_INSTALL_LOG" && echo_failure )
	fi
}

function update_grub() {
	if [ "$VIRTUAL" = true ]; then
		echo_step "Not updating GRUB on virtual systems"
		echo_success
		return 1
	fi

	# Update grub
	echo_step "  Updating grub"
	sudo cp /etc/default/grub /etc/default/grub.old
	sudo cat "/etc/default/grub.old" | sudo grep -v "GRUB_HIDDEN_TIMEOUT" | sudo grep -v "GRUB_TIMEOUT" | sudo grep -v "GRUB_RECORDFAIL_TIMEOUT" | sudo tee /etc/default/grub > /dev/null
	echo "GRUB_TIMEOUT=5
GRUB_RECORDFAIL_TIMEOUT=5" | sudo tee -a /etc/default/grub  > /dev/null
	sudo update-grub > /dev/null && echo_success || ( echo -e "Failed to update GRUB " >> "$FRESH_INSTALL_LOG" && echo_failure )
}

function check_sensors() {
	if [ "$VIRTUAL" = true ]; then
		echo_step "No sensors in virtual systems"
		echo_success
		return 1
	fi

	echo_step "  Checking sensors"
	if ! grep -q "nct6775" /etc/modules; then
		sudo sensors-detect --auto 1>/dev/null 2>&1
		echo "
coretemp
nct6775
" | sudo tee -a /etc/modules > /dev/null
		sudo service kmod start
	fi
	sudo sensors | grep -q "temp1" && echo_success || ( echo -e "Failed to check sensors" >> "$FRESH_INSTALL_LOG" && echo_failure )
}

function add_users() {
	# Add users
	echo_step "  Adding users"
	echo
	sudo useradd -m dev -s /bin/bash
	sudo usermod -aG sudo dev && echo 'dev:devMolecubes47' | sudo chpasswd
	id dev > /dev/null || exit_with_failure "failed to add user dev"
	sleep 1
	sudo useradd -m molecubes -s /bin/bash
	sudo usermod -aG sudo molecubes && echo 'molecubes:Molecubes47' | sudo chpasswd
	id molecubes > /dev/null || exit_with_failure "failed to add user molecubes"
	sudo gpasswd --add molecubes dialout && sudo gpasswd --add dev dialout && sudo usermod -aG adm molecubes && sudo usermod -aG adm dev && sudo chmod 700 /home/dev && echo_success
}

function set_ubuntu18_config() {
	if ! grep -q "blacklist nouveau" /etc/modprobe.d/blacklist-nouveau.conf; then
		echo_step "  Disabling nouveau"
		# Blacklist nouveau
		echo "blacklist nouveau
options nouveau modeset=0" | sudo tee -a /etc/modprobe.d/blacklist-nouveau.conf > /dev/null
		sudo update-initramfs -u > /dev/null && echo_success || ( echo -e "Failed to disable nouveau" >> "$FRESH_INSTALL_LOG" && echo_failure )
	fi
	if [ "$VIRTUAL" = false ]; then
		# Set default runlevel
		echo_step "  Setting default runlevel"
		sudo systemctl set-default runlevel3.target && echo_success || ( echo -e "Failed to set default runlevel"  >> "$FRESH_INSTALL_LOG" && echo_failure )
	fi
	if [ "$ISACQ" = true ] && [ "$VIRTUAL" = false ]; then
		# Delete default gateway
		echo_step "  Deleting default gateway 10.0.0.2"
		sudo sed -i -e "s/^.*gateway4: 10.0.0.2.*$//" /etc/netplan/01-netcfg.yaml || ( echo -e "Failed to delete default gateway 10.0.0.2" >> "$FRESH_INSTALL_LOG" && echo_failure )
		echo_success
	fi

	# Add molecubes libs to path
	echo_step "  Adding molecubes/libs to resolve path"
	echo -e "/home/molecubes/libs/" | sudo tee /etc/ld.so.conf.d/molecubes.conf > /dev/null
	sudo ldconfig -v > /dev/null && echo_success || ( echo -e "Failed to add molecubes/libs to resolve path"  >> "$FRESH_INSTALL_LOG" && echo_failure )
	
	sudo apt-get -qq --assume-yes install libcurl4-openssl-dev || exit_with_failure "failed to install libcurl4"

	if [ "$DEVICE_MODALITY" = "REMI" ]; then
		if ! grep -q "fs.inotify.max_user_watches=65536" /etc/sysctl.conf; then
			echo "fs.inotify.max_user_watches=65536" | sudo tee -a /etc/sysctl.conf && sudo sysctl -p
		fi
	fi
	#if ! grep -q "alias curl='LD_LIBRARY_PATH=/usr/local/lib/libcurl4/ curl" /etc/bash.bashrc; then
	#	sudo apt -qq --assume-yes install binutils libcurl3
	#	echo_step "  Installing curl"
	#	mkdir -p /home/dev/temp
	#	cd /home/dev/temp
	#	sudo apt-get download libcurl4 && sudo ar x libcurl4* && sudo tar -xvf data.tar.xz && sudo mkdir -p /usr/local/lib/libcurl4/ && sudo cp usr/lib/x86_64-linux-gnu/libcurl.so.4 /usr/local/lib/libcurl4/ || exit_with_failure "failed to install libcurl4"
	#	sudo apt-get download curl && sudo ar x curl* && sudo tar -xvf control.tar.xz && sudo sed -i -e "s/\(libcurl4[^,]*\)/libcurl3 (>= 7.16.2)/" control && sudo tar -cJvf control.tar.xz control md5sums && sudo ar rcs curl-local.deb debian-binary control.tar.xz data.tar.xz && sudo dpkg -i curl-local.deb || exit_with_failure "failed to install curl"
	#	echo -e "alias curl='LD_LIBRARY_PATH=/usr/local/lib/libcurl4/ curl'" | sudo tee -a /etc/bash.bashrc
	#	source /etc/bash.bashrc
	#	source ~/.bashrc
	#	cd /home/dev/ && sudo rm -rf /home/dev/temp
	#	echo_success
	#fi
}

function enable_debugging() {
	if ! grep -qs "unpackaged=true" /home/molecubes/.config/apport/settings; then
		echo_step "  Enabling debugging"
		echo -e "root\t-\tcore\tunlimited" | sudo tee -a /etc/security/limits.conf > /dev/null
		echo -e "*\t-\tcore\tunlimited" | sudo tee -a /etc/security/limits.conf > /dev/null
		echo "kernel.randomize_va_space = 0" | sudo tee /etc/sysctl.d/01-disable-aslr.conf > /dev/null
		sudo mkdir -p /home/molecubes/.config/apport/
		sudo chown -R molecubes:molecubes /home/molecubes/*
		echo "[main]
unpackaged=true" | sudo tee /home/molecubes/.config/apport/settings > /dev/null
		sudo chown -R molecubes:molecubes /home/molecubes/.config
		sudo sed -i -e "s/^\(.*\)\('problem_types.*\)$/\1# \2/" /etc/apport/crashdb.conf
		sudo systemctl restart apport
		grep -q "unpackaged=true" /home/molecubes/.config/apport/settings && echo_success || ( echo -e "Failed to enable debugging" >> "$FRESH_INSTALL_LOG" && echo_failure )
	fi
}

function create_directories() {
	echo_step "  Creating necessary directories"
	sudo mkdir -p /home/molecubes/bin && sudo mkdir -p /home/molecubes/data/reports && sudo mkdir -p /home/molecubes/libs && echo_success || ( echo -e "Failed to create default directories" >> "$FRESH_INSTALL_LOG" && echo_failure )
	if [ "$DEVICE_MODALITY" = "PET" ]; then
		if [ "$ISACQ" = true ]; then
			sudo mkdir -p /home/molecubes/conf/Systems/ && sudo mkdir -p /home/molecubes/conf/Mains/ && sudo mkdir -p /home/molecubes/conf/Detectors/ && sudo mkdir -p /home/molecubes/conf/Recon/ && sudo mkdir -p /home/molecubes/conf/Calib/sensitivity/ && sudo mkdir -p /home/molecubes/data/qc/daily && sudo mkdir -p /home/molecubes/data/qc/monthly && sudo mkdir -p /home/molecubes/data/qc/periodic && sudo mkdir -p /home/molecubes/conf/Calib/default && sudo mkdir -p /home/molecubes/conf/Calib/Library && sudo mkdir -p /home/molecubes/data/calibration/calib && sudo mkdir -p /home/molecubes/data/calibration/vop && echo_success || ( echo -e "Failed to create default PET directories" >> "$FRESH_INSTALL_LOG" && echo_failure )
		else
			sudo mkdir -p /home/molecubes/conf/Calib/sensitivity && sudo mkdir -p /home/molecubes/conf/Calib/normalisation && sudo mkdir -p /home/molecubes/conf/Recon/ && sudo mkdir -p /home/molecubes/conf/Systems/ && echo_success || ( echo -e "Failed to create default PET directories" >> "$FRESH_INSTALL_LOG" && echo_failure )
		fi
	elif [ "$DEVICE_MODALITY" = "SPECT" ]; then
		if [ "$ISACQ" = true ]; then
			sudo mkdir -p /home/molecubes/conf/ && sudo mkdir -p /home/molecubes/conf/Systems/ && sudo mkdir -p /home/molecubes/conf/Mains && sudo mkdir -p /home/molecubes/conf/Detectors && echo_success || ( echo -e "Failed to create default SPECT directories" >> "$FRESH_INSTALL_LOG" && echo_failure )
		else
			sudo mkdir -p /home/molecubes/conf/ && sudo mkdir -p /home/molecubes/conf/Systems/ && sudo mkdir -p /home/molecubes/conf/Calib/sensitivity/ && sudo mkdir -p /home/molecubes/conf/Calib/normalisation/ && sudo mkdir -p /home/molecubes/conf/Recon/ && sudo mkdir -p /home/molecubes/calib/ && echo_success || ( echo -e "Failed to create default SPECT directories" >> "$FRESH_INSTALL_LOG" && echo_failure )
		fi
	elif [ "$DEVICE_MODALITY" = "REMI" ]; then
		sudo mkdir -p /home/dev/workstation /home/dev/temp && sudo chown dev:dev /home/dev/workstation && echo_success || ( echo -e "Failed to create default REMI directories" >> "$FRESH_INSTALL_LOG" && echo_failure )
	fi
	sudo chown -R molecubes:molecubes /home/molecubes/*
	sudo chown dev:dev /home/dev/temp
}

function set_ssh_config() {
	if [ "$VIRTUAL" = true ]; then
		echo_step "  Not adjusting SSH settings of virtual systems"
		echo_success
		return
	fi

	if ! grep -q "Ciphers arcfour,chacha20-poly1305@openssh.com" /etc/ssh/sshd_config; then
		echo_step "  Setting SSH config"
		sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.original
		echo "
# Cipher default + arcfour
Ciphers arcfour,chacha20-poly1305@openssh.com,aes128-ctr,aes192-ctr,aes256-ctr,aes128-gcm@openssh.com,aes256-gcm@openssh.com" | sudo tee -a /etc/ssh/sshd_config
		sudo grep -q "Ciphers arcfour,chacha20-poly1305@openssh.com" /etc/ssh/sshd_config && echo_success || ( echo -e "Failed to set SSH config" >> "$FRESH_INSTALL_LOG" && echo_failure )
	fi
}

function create_acq_logs() {
	echo_step "  Creating acquisition logs"
	echo "\$umask 0000" | sudo tee /etc/rsyslog.d/30-acquisitionserver.conf > /dev/null
	echo "\$FileCreateMode 0644" | sudo tee -a /etc/rsyslog.d/30-acquisitionserver.conf > /dev/null
	echo ":syslogtag,startswith,\"AcquisitionServer\" -/var/log/acquisitionserver.log" | sudo tee -a /etc/rsyslog.d/30-acquisitionserver.conf > /dev/null
	sudo service rsyslog restart
	echo_success
}

function create_recon_logs() {
	echo_step "  Creating reconstruction logs"
	echo "\$umask 0000" | sudo tee /etc/rsyslog.d/30-reconstructionserver.conf > /dev/null
	echo "\$FileCreateMode 0644" | sudo tee -a /etc/rsyslog.d/30-reconstructionserver.conf > /dev/null
	echo ":syslogtag,startswith,\"ReconstructionServer\" -/var/log/reconstructionserver.log" | sudo tee -a /etc/rsyslog.d/30-reconstructionserver.conf > /dev/null
	sudo service rsyslog restart
	echo_success
}

function create_xray_logs() {
	echo_step "  Creating xray logs"
	echo "\$umask 0000" | sudo tee /etc/rsyslog.d/30-xrayserver.conf > /dev/null
	echo "\$FileCreateMode 0644" | sudo tee -a /etc/rsyslog.d/30-xrayserver.conf > /dev/null
	echo ":syslogtag,startswith,\"XRayServer\" -/var/log/xrayserver.log" | sudo tee -a /etc/rsyslog.d/30-xrayserver.conf > /dev/null
	sudo service rsyslog restart
	echo_success
}

function create_acq_files() {
	echo_step "  Creating acquisition specific files"
	echo -e "[Unit]
Description=Molecubes Acquisitionserver
After=syslog.target network.target network-online.target remote-fs.target autofs.target" | sudo tee /lib/systemd/system/acquisitionserver.service > /dev/null
if [ "$DEVICE_MODALITY" = "CT" ]; then
	echo "RequiresMountsFor=/mnt/data/" | sudo tee -a /lib/systemd/system/acquisitionserver.service > /dev/null
fi

echo -e "

[Service]
Type=simple
User=molecubes
Group=molecubes
# How to stop the service
KillSignal=SIGINT
ExecReload=/bin/kill -SIGHUP \$MAINPID
# restart for every return code except when clean exit code or signal
Restart=on-failure
# restart after 5 seconds wait
RestartSec=5
WorkingDirectory=/home/molecubes/
ExecStart=/home/molecubes/serverloader /home/molecubes/acquisitionserver.mmf 50000 --config=/home/molecubes/acquisitionserver.ini

[Install]
WantedBy=multi-user.target
" | sudo tee -a /lib/systemd/system/acquisitionserver.service > /dev/null
	sudo systemctl daemon-reload

	echo -e "acquisitionserver.so
$PACKAGEVERSION
LDJDA12" | sudo tee /home/molecubes/acquisitionserver.mmf > /dev/null
	sudo touch /home/molecubes/acquisitionserver.so && sudo chown molecubes:molecubes /home/molecubes/acquisitionserver.mmf /home/molecubes/acquisitionserver.so && echo_success || ( echo -e "Failed to set permissions for SO's" >> "$FRESH_INSTALL_LOG" && echo_failure )
	if [ "$DEVICE_MODALITY" = "CT" ]; then
		create_ctacq_files
	elif [ "$DEVICE_MODALITY" = "PET" ]; then
		create_petacq_files
	elif [ "$DEVICE_MODALITY" = "SPECT" ]; then
		create_spectacq_files
	fi
}

function create_recon_files() {
	echo_step "  Creating reconstruction specific files"
	echo -e "[Unit]
Description=Molecubes Reconstructionserver
After=syslog.target network.target network-online.target remote-fs.target autofs.target
" | sudo tee /lib/systemd/system/reconstructionserver.service > /dev/null
if [ "$DEVICE_MODALITY" = "PET" ]; then
	echo "RequiresMountsFor=/mnt/conf/" | sudo tee -a /lib/systemd/system/reconstructionserver.service > /dev/null
elif [ "$DEVICE_MODALITY" = "SPECT" ]; then
	echo "RequiresMountsFor=/mnt/data/" | sudo tee -a /lib/systemd/system/reconstructionserver.service > /dev/null
fi

echo -e "

[Service]
Type=simple
User=molecubes
Group=molecubes
# How to stop the service
KillSignal=SIGINT
ExecReload=/bin/kill -SIGHUP \$MAINPID
# restart for every return code except when clean exit code or signal
Restart=on-failure
# restart after 5 seconds wait
RestartSec=5
WorkingDirectory=/home/molecubes/
ExecStart=/home/molecubes/serverloader /home/molecubes/reconstructionserver.mmf 50005 --config=/home/molecubes/reconstructionserver.ini

[Install]
WantedBy=multi-user.target" | sudo tee -a /lib/systemd/system/reconstructionserver.service > /dev/null
	sudo systemctl daemon-reload

	echo -e "reconstructionserver.so
$PACKAGEVERSION
LDADE34" | sudo tee /home/molecubes/reconstructionserver.mmf > /dev/null
	sudo touch /home/molecubes/reconstructionserver.so && sudo chown molecubes:molecubes /home/molecubes/reconstructionserver.mmf /home/molecubes/reconstructionserver.so && echo_success || ( echo -e "Failed to set permissions for SO's" >> "$FRESH_INSTALL_LOG" && echo_failure )
	if [ "$DEVICE_MODALITY" = "CT" ]; then
		create_ctrecon_files
	elif [ "$DEVICE_MODALITY" = "PET" ]; then
		create_petrecon_files
	elif [ "$DEVICE_MODALITY" = "SPECT" ]; then
		create_spectrecon_files
	elif [ "$DEVICE_MODALITY" = "REMI" ]; then
		create_remi_files
	fi
	echo_success
}

function configure_motors() {
	if [ "$VIRTUAL" = true ]; then
		echo_step "  Not configuring motors on virtual systems"
		echo_success
		return
	fi

	if [ "$DEVICE_MODALITY" = "CT" ]; then
		configure_ct_motors
	elif [ "$DEVICE_MODALITY" = "PET" ]; then
		if [ "$ISACQ" = true ]; then
			configure_petacq_motors
		fi
	elif [ "$DEVICE_MODALITY" = "SPECT" ]; then
		if [ "$ISACQ" = true ]; then
			configure_spectacq_motors
		fi
	fi
}

function setup_network_drives() {
	if [ "$DEVICE_MODALITY" = "CT" ]; then
		if [ "$ISXRAY" = false ]; then
			setup_ctacqrecon_network_drives
		fi
	elif [ "$DEVICE_MODALITY" = "PET" ]; then
		if [ "$ISACQ" = true ]; then
			setup_petacq_network_drives
		else
			setup_petrecon_network_drives
		fi
	elif [ "$DEVICE_MODALITY" = "SPECT" ]; then
		if [ "$ISACQ" = true ]; then
			setup_spectacq_network_drives
		else
			setup_spectrecon_network_drives
		fi
	elif [ "$DEVICE_MODALITY" = "REMI" ]; then
		setup_remi_network_drives
	fi
}

function program_motors() {
	if [ "$VIRTUAL" = true ]; then
		echo_step "  Not programming motors on virtual systems"
		echo_success
		return
	fi

	if [ "$ISACQ" = true ]; then
		echo_step "  Programming $DEVICE_MODALITY motors"
		cd
		CONFIGURE_FILE=$(find /home/dev/install/ -name "ConfigureMotors" -print0 | xargs -r -0 ls -1 -t | head -1)
		if [ -f $CONFIGURE_FILE ]; then
			sudo chmod 777 $CONFIGURE_FILE
			sudo ldconfig > /dev/null
			sudo $CONFIGURE_FILE $DEVICE_MODALITY
			echo_success
		else
			echo -e "Unable to program $DEVICE_MODALITY motors: Failed to find ConfigureMotors binary" >> "$FRESH_INSTALL_LOG" && echo_failure
		fi
	fi
}

################################################################################
# CT install functions
################################################################################

function configure_ct_motors() {
	echo_step "  Enabling CT motors"
	echo "# udevadm info --name=/dev/ttyUSB0 --attribute-walk
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"0403\", ATTRS{idProduct}==\"6001\", ATTRS{devpath}==\"3\", SYMLINK+=\"shuttermotor\"
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"0403\", ATTRS{idProduct}==\"6001\", ATTRS{devpath}==\"2\", SYMLINK+=\"gantrymotor\"
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"0403\", ATTRS{idProduct}==\"6001\", ATTRS{devpath}==\"1\", SYMLINK+=\"bedmotor\"
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"2341\", ATTRS{idProduct}==\"0042\", ATTRS{devpath}==\"6\", SYMLINK+=\"progressleds\"
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"2341\", ATTRS{idProduct}==\"0042\", ATTRS{devpath}==\"5\", SYMLINK+=\"monitoring\"
" | sudo tee /etc/udev/rules.d/99-usb-serial.rules > /dev/null
	sudo udevadm control --reload-rules
	sudo udevadm trigger
	sleep 1
	if [ ! -L  /dev/shuttermotor ]; then
		exit_with_message "Failed enable shuttermotor"
	elif  [ ! -L  /dev/gantrymotor ]; then
		exit_with_message "Failed enable gantrymotor"
	elif  [ ! -L  /dev/bedmotor ]; then
		exit_with_message "Failed enable bedmotor"
	elif  [ ! -L  /dev/progressleds ]; then
		exit_with_message "Failed enable progressleds"
	elif  [ ! -L  /dev/monitoring ]; then
		exit_with_message "Failed enable monitoring"
	fi
	echo_success
}

function setup_ctacqrecon_network_drives() {
	echo_step "  Setting up network drives"
	sudo mkdir -p /export/data || true
	sudo chmod 777 /export || true
	sudo chmod 777 /export/data || true

	DEFAULT_XRAYSERVER_IP_ADDRESS="10.0.0.2"
	if [ "$VIRTUAL" = true ]; then
		DEFAULT_XRAYSERVER_IP_ADDRESS="auto-test-xrayserver.in.molecubes.com"
	fi

	if ! grep -q "${DEFAULT_XRAYSERVER_IP_ADDRESS}:/data" /etc/auto.nfs; then
		echo -e "/mnt\t/etc/auto.nfs" | sudo tee -a /etc/auto.master > /dev/null
		echo -e "data\t-fstype=nfs4\t${DEFAULT_XRAYSERVER_IP_ADDRESS}:/data" | sudo tee -a /etc/auto.nfs > /dev/null
		sudo service autofs restart
	fi
	if ! grep -q "192.168.0.0/24" /etc/exports; then
		sudo cp /etc/exports /etc/exports.old
		ID=$(id molecubes | sed "s/^uid=\([0-9]*\)(.*$/\1/")
		# anonuid and anongid need to point to userid of user 'molecubes', check /etc/passwd
		echo -e "/export\t192.168.0.0/24(rw,fsid=0,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
/export/data\t192.168.0.0/24(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
" | sudo tee -a /etc/exports > /dev/null
	fi
	if [ "$VIRTUAL" = true ]; then
		if ! grep -q "auto-test-ycuberecon.in.molecubes.com" /etc/exports; then
			ID=$(id molecubes | sed "s/^uid=\([0-9]*\)(.*$/\1/")
			# anonuid and anongid need to point to userid of user 'molecubes', check /etc/passwd
			echo -e "/export\tauto-test-ycuberecon.in.molecubes.com(rw,fsid=0,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) auto-test-bcuberecon.in.molecubes.com(rw,fsid=0,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) auto-test-remi.in.molecubes.com(rw,fsid=0,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) auto-test-gui.in.molecubes.com(rw,fsid=0,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
/export/data\tauto-test-ycuberecon.in.molecubes.com(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) auto-test-bcuberecon.in.molecubes.com(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) auto-test-remi.in.molecubes.com(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) auto-test-gui.in.molecubes.com(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
" | sudo tee -a /etc/exports > /dev/null
		fi
	fi
	if ! grep -q "home/molecubes/data" /etc/fstab; then
		echo -e "/home/molecubes/data\t/export/data\tnone\tbind\t0\t0" | sudo tee -a /etc/fstab > /dev/null
		sudo mount -a
	fi
	sudo service nfs-kernel-server restart
	if [ -d "/export/data" ]; then
		echo_success
	else
		echo -e "Failed to create /export/data" >> "$FRESH_INSTALL_LOG"
		echo_failure
	fi
}

function setup_ctxray_network_drives() {
	echo_step "   Setting up network drives"
	sudo mkdir -p /export/data || true
	sudo chmod 777 /export || true
	sudo chmod 777 /export/data || true

	if ! grep -q "net.core.wmem_max = 10485760" /etc/sysctl.conf; then
		echo_step "  Setting up send buffer size"
		echo "net.core.wmem_max = 10485760" | sudo tee -a /etc/sysctl.conf > /dev/null
		echo "net.core.rmem_max = 10485760" | sudo tee -a /etc/sysctl.conf > /dev/null
		echo "net.ipv4.tcp_rmem = 10240 87380 12582912" | sudo tee -a /etc/sysctl.conf > /dev/null
		echo "net.ipv4.tcp_wmem = 10240 87380 12582912" | sudo tee -a /etc/sysctl.conf > /dev/null
		sudo sysctl -p
		sudo grep -q "net.core.wmem_max = 10485760" /etc/sysctl.conf && echo_success || ( echo -e "Failed to set send buffer size" >> "$FRESH_INSTALL_LOG" && echo_failure )
	fi
	if ! grep -q "10.0.0.0/2" /etc/exports; then
		sudo cp /etc/exports /etc/exports.old
		ID=$(id molecubes | sed "s/^uid=\([0-9]*\)(.*$/\1/")
		echo -e "/export\t10.0.0.0/24(rw,fsid=0,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
/export/data\t10.0.0.0/24(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
" | sudo tee -a /etc/exports > /dev/null
	fi
	if [ "$VIRTUAL" = true ]; then
		if ! grep -q "auto-test-xcubeacqrecon.in.molecubes.com" /etc/exports; then
			ID=$(id molecubes | sed "s/^uid=\([0-9]*\)(.*$/\1/")
			echo -e "/export\tauto-test-xcubeacqrecon.in.molecubes.com(rw,fsid=0,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
/export/data\tauto-test-xcubeacqrecon.in.molecubes.com(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
" | sudo tee -a /etc/exports > /dev/null
		fi
	fi
	if ! grep -q "home/molecubes/data" /etc/fstab; then
		echo -e "/home/molecubes/data\t/export/data\tnone\tbind\t0\t0" | sudo tee -a /etc/fstab > /dev/null
		sudo mount -a
	fi
	sudo service nfs-kernel-server restart
	if [ -d "/export/data" ]; then
		echo_success
	else
		echo -e "Failed to create /export/data" >> "$FRESH_INSTALL_LOG"
		echo_failure
	fi
}

function create_ctacq_files() {
	sudo hostnamectl set-hostname xcubeacqrecon$(echo $SERIAL | sed -e "s/\([C,P,S]\)[0-9][0-9]\([0-9][0-9]\)[0-9][0-9]/\1\2/")

	echo -e "
[global]
type = CT
version = 1
deviceSerialNumber = $SERIAL
port = 5000
logfile = acquisitionserver.log
logpath = /home/molecubes/
outputPath = /home/molecubes/data
patch = 0" | sudo tee /home/molecubes/acquisitionserver.ini > /dev/null

DEFAULT_IP_ADDRESS="192.168.0.170"
if [ "$VIRTUAL" = true ]; then
	DEFAULT_IP_ADDRESS="auto-test-xcubeacqrecon.in.molecubes.com"
fi

echo -e "
[network]
publicIPAddress = ${DEFAULT_IP_ADDRESS}" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null

XRAYSERVER_ADDRESS="10.0.0.2"
if [ "$VIRTUAL" = true ]; then
	XRAYSERVER_ADDRESS="auto-test-xrayserver.in.molecubes.com"
fi

echo -e "
[CT]
subsystemIPAddress = ${XRAYSERVER_ADDRESS}
subsystemPort = 5005
subsystemPortMonitor = 5006
resp_gating_window_width=60
resp_gating_window_delay=20
detectorVersion = 2
scout_hardware = true
hotpixelThreshold = 2.0
deadpixelThreshold = 0.2
num_brightmaps = 1
doseCalc_a = 0.0005
doseCalc_b = 0.1207
doseCalc_c = -3.4564" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null

echo -e "
[monitoring]
serialPort = /dev/monitoring
baudRate = 115200
Vref = 2.42
buffersize = 20
samplingRate = 666
breathingFilter = 1
breathingFilterSize = 1
heartrateFilter = 1
heartrateFilterSize = 1
maxPWM_basic_mouse = 80
maxPWM_monitoring_mouse = 100
maxPWM_basic_rat = 130
maxPWM_monitoring_rat = 150
maxPWM_basic_ratXL = 130
maxPWM_monitoring_ratXL = 150
maxPWM_basic_custom = 0
maxPWM_monitoring_custom = 0
maxPWM_basic_unknown = 0
maxPWM_monitoring_unknown = 0
maxPWM_basic_ratXL_hotel = 72
maxPWM_monitoring_ratXL_hotel = 72
maxPWM_basic_rat_hotel = 72
maxPWM_monitoring_rat_hotel = 72
mouse4hotel_uids = 
mouse3hotel_uids = " | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null
if [ "$VIRTUAL" = true ]; then
	echo -e "type = virtual" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null
fi

MOTORTYPE="CM10-1A"
if [ "$VIRTUAL" = true ]; then
	MOTORTYPE="virtual"
fi

echo -e "
[gantry]
serialPort = /dev/gantrymotor
motorType = ${MOTORTYPE}
homeVelocity = 12
startVelocity = 12
runVelocity = 12
accelerationTime = 0.1
decelerationTime = 0.1
distancePerRevolution = 112.5
motorResolution = 1000
gearA = 10
gearB = 1
hometyp = 8 " | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null

echo -e "
[bed]
serialPort = /dev/bedmotor
motorType = ${MOTORTYPE}
homeVelocity = 10
startVelocity = 10
runVelocity = 10
accelerationTime = 0.1
decelerationTime = 0.1
distancePerRevolution = 2.5
motorResolution = 1000
gearA = 1
gearB = 1
nrPositions_mouse = 10
nrPositions_rat = 12
nrPositions_QCphantom = 10
nrPositions_default = 10
startPosition_mouse = 123.4
length_mouse = 200
startPosition_rat = 132.4
length_rat = 250
startPostion_QCphantom = 132.4
length_QCphantom = 200
startPosition_default = 132.4
length_default = 200
maximum_position = 339
hometyp = 0" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null

echo -e "
[shutter]
serialPort = /dev/shuttermotor
baudRate = 115200
hometyp = 0
motorType = ${MOTORTYPE}
homeVelocity = 10
closingDistance = 115
minimumBedPosition_mouse = 110
minimumBedPosition_rat = 160
minimumBedPosition_QCphantom = 160
minimumBedPosition_default = 160" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null

echo -e "
[progressleds]
serialPort = /dev/progressleds
baudRate = 9600" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null
if [ "$VIRTUAL" = true ]; then
	echo -e "type = virtual" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null
fi

echo -e "
[capabilities]
gating_hardware=true
realtimeCTreconstruction=true" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/acquisitionserver.ini

	echo -e "# To get optimal use of the x-ray dose per projection, there should be no gap!
# Calculate (TIME / EXPOSURES) - 0.040, this should be equal to EXPOSURE/1000

[spiral high-throughput]
scan_type = continuous
exposures = 120
time = 15
# 9 degrees offset needed (empirically determined), because we rotate at 24 deg/sec! 9 deg is done in 375 msec!
angle_offset = -9.0
kVp = 50
muA = 150
muA_lowdose = 75
# 30
exposure = 85
FOV = 37.4
pitch = 1.4
binning = 1

[spiral high-resolution]
scan_type = continuous
exposures = 960
time = 120
angle_offset = 0.0
kVp = 50
muA = 350
muA_lowdose = 80
exposure = 32
FOV = 37.4
pitch = 1.4
binning = 1

[spiral general-purpose]
scan_type = continuous
exposures = 480
time = 60
angle_offset = 0.0
kVp = 50
muA = 75
muA_lowdose = 60
exposure = 85
FOV = 37.4
pitch = 1.4
binning = 1

[scout]
kVp = 50
# muA preferably 80 or something lower!
muA = 100
# not really used
muA_lowdose = 100
exposure = 10
FOV = 37.4
binning = 4" | sudo tee /home/molecubes/data/acquisitionParameters.ini > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/acquisitionParameters.ini

	sudo -u molecubes mkdir -p /home/molecubes/data/protocols
	echo -e "[respiratory gated]
scan_type = step
exposures = 960
time = 120
angle_offset = 0.0
kVp = 50
muA = 350
muA_lowdose = 80
exposure = 32
# minimum exposure 32 for 1x1, 10 for 2x2, 2.5 for 4x4
FOV = 37.4
pitch = 1.4
binning = 1
waiting_time = 100
# minimum 18 for 1x1, 7 for 2x2, 7 for 4x4
total_rotation = 360.0
# percentages
window_delay = 20
window_width = 60
gating_bins = 5" | sudo tee /home/molecubes/data/protocols/respiratorygating.par > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/protocols/respiratorygating.par

	echo -e "[cardiac gated]
scan_type = continuous
exposures = 11000
time = 270
angle_offset = 0.0
kVp = 50
muA = 500
muA_lowdose = 500
exposure = 10
FOV = 37.4
pitch = 1.4
binning = 2
total_rotation = 380.0

[cardiac gated rat]
scan_type = continuous
exposures = 11000
time = 270
angle_offset = 0.0
kVp = 50
muA = 500
muA_lowdose = 500
exposure = 10
FOV = 37.4
pitch = 1.4
binning = 2
total_rotation = 380.0

[cardiac gated mouse]
scan_type = continuous
exposures = 11000
time = 270
angle_offset = 0.0
kVp = 50
muA = 500
muA_lowdose = 500
exposure = 10
FOV = 37.4
pitch = 1.4
binning = 2
total_rotation = 380.0" | sudo tee /home/molecubes/data/protocols/cardiacgating.par > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/protocols/cardiacgating.par

	echo -e "[general_purpose_multi_rotation]
scan_type = continuous
exposures = 480
time = 60
angle_offset = 0.0
kVp = 50
muA = 85
muA_lowdose = 42
exposure = 85
FOV = 37.4
pitch = 1.4
binning = 1
gatingrotations = 4" | sudo tee /home/molecubes/data/protocols/general_purpose_multi_rotation.ini > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/protocols/general_purpose_multi_rotation.ini

	echo -e "[high_resolution_multi_rotation]
scan_type=step
angle_offset=0.0
exposures=720
time=120
kVp=50
muA = 225
muA_lowdose = 120
FOV=37.4
pitch=1.4
binning=1
exposure=32
gatingrotations=4
waiting_time=72" | sudo tee /home/molecubes/data/protocols/high_resolution_multi_rotation.ini > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/protocols/high_resolution_multi_rotation.ini

	sudo touch /home/molecubes/data/PostProcessing.py
	sudo chown molecubes:molecubes /home/molecubes/data/PostProcessing.py
	sudo chmod 755 /home/molecubes/data/PostProcessing.py

	create_ct_xml_files
}

function create_ctrecon_files() {

	DEFAULT_IP_ADDRESS="192.168.0.170"
	if [ "$VIRTUAL" = true ]; then
		DEFAULT_IP_ADDRESS="auto-test-xcubeacqrecon.in.molecubes.com"
	fi
	
	echo -e "[global]
type = CT
version = 1
port = 5001
logfile = reconstructionserver.log
logpath = /home/molecubes/
outputPath = /home/molecubes/data
deviceSerialNumber = $SERIAL

[CT]
FOVextension = 3
allowOutsideFOVCorrection = true
applyWaterCorrection = true
ringArtefactReduction = false
fixedHU_max = 64535
fixedHU_min = -1000

[internal]
localEthIPAddress = 127.0.0.1
localIPAddress = ${DEFAULT_IP_ADDRESS}
receiveDatasetPort = 6767
acquisitionServerIP = 10.0.0.2
acquisitionServerEthIP = 127.0.0.1

[dicom]
institutionName = Molecubes
institutionAddress = Infinity
institutionDepartmentName = Lab
deviceSerialNumber = $SERIAL
serveraddress = 192.168.2.1
serverport = 8042
username = molecubes
password = molecubes

[registration]
matrixPath = /home/molecubes/data/registration.matrix

[output]
cutoffROI = 1
filenameFormat = %d_%m_%g_%r
histogramRescale = 1" | sudo tee /home/molecubes/reconstructionserver.ini > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/reconstructionserver.ini
}

function create_ct_xml_files() {
	echo -e '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<!DOCTYPE boost_serialization>
<boost_serialization signature="serialization::archive" version="11">
<params class_id="0" tracking_level="0" version="0">
<_params class_id="1" tracking_level="0" version="0">
<count>19</count>
<item_version>0</item_version>
<item class_id="2" tracking_level="0" version="0">
<first>Geometry/pixels_x</first>
<second>1536</second>
</item>
<item>
<first>Geometry/pixels_y</first>
<second>864</second>
</item>
<item>
<first>Geometry/pixelsizeX</first>
<second>0.075</second>
</item>
<item>
<first>Geometry/pixelsizeY</first>
<second>0.075</second>
</item>
<item>
<first>Geometry/SDD</first>
<second>193.903</second>
</item>
<item>
<first>Geometry/M</first>
<second>1.72435</second>
</item>
<item>
<first>Geometry/detoffsetx</first>
<second>0.0</second>
</item>
<item>
<first>Geometry/detoffsety</first>
<second>0.0</second>
</item>
<item>
<first>Geometry/tilt</first>
<second>0.0</second>
</item>
<item>
<first>Geometry/skew</first>
<second>0.0</second>
</item>
<item>
<first>Geometry/slant</first>
<second>0.0</second>
</item>
<item>
<first>Geometry/bedoffsetx</first>
<second>0.00</second>
</item>
<item>
<first>Geometry/bedoffsety</first>
<second>0.0</second>
</item>
<item>
<first>Linearity/a</first>
<second>0.00000240631618404459</second>
</item>
<item>
<first>Linearity/b</first>
<second>0.997607529092091</second>
</item>
<item>
<first>Linearity/c</first>
<second>1.2344590025886</second>
</item>
<item>
<first>WaterCorrection/c</first>
<second>0.0138</second>
</item>
<item>
<first>WaterCorrection/b</first>
<second>0.932</second>
</item>
<item>
<first>WaterCorrection/a</first>
<second>0.119</second>
</item>
</_params>
<_sections class_id="3" tracking_level="0" version="0">
<count>4</count>
<item_version>0</item_version>
<item>Reconstruction</item>
<item>Geometry</item>
<item>Linearity</item>
<item>WaterCorrection</item>
</_sections>
</params>
</boost_serialization>' | sudo tee /home/molecubes/data/calibrationParameters.xml > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/calibrationParameters.xml

	echo -e '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<!DOCTYPE boost_serialization>
<boost_serialization signature="serialization::archive" version="11">
<params class_id="0" tracking_level="0" version="0">
<_params class_id="1" tracking_level="0" version="0">
<count>17</count>
<item_version>0</item_version>
<item class_id="2" tracking_level="0" version="0">
<first>Reconstruction/cudaDevice</first>
<second>0</second>
</item>
<item>
<first>Reconstruction/output_filename</first>
<second>resulti%03i.img</second>
</item>
<item>
<first>Reconstruction/suffix</first>
<second>ATTMAP</second>
</item>
<item>
<first>Reconstruction_mouse/recon_voxels_x</first>
<second>70</second>
</item>
<item>
<first>Reconstruction_mouse/recon_voxels_y</first>
<second>70</second>
</item>
<item>
<first>Reconstruction_mouse/recon_voxels_z</first>
<second>50</second>
</item>
<item>
<first>Reconstruction_rat/recon_voxels_x</first>
<second>70</second>
</item>
<item>
<first>Reconstruction_rat/recon_voxels_y</first>
<second>70</second>
</item>
<item>
<first>Reconstruction_rat/recon_voxels_z</first>
<second>50</second>
</item>
<item>
<first>Reconstruction/voxelsizeX</first>
<second>1.0</second>
</item>
<item>
<first>Reconstruction/voxelsizeY</first>
<second>1.0</second>
</item>
<item>
<first>Reconstruction/voxelsizeZ</first>
<second>1.0</second>
</item>
<item>
<first>Reconstruction/spectrum</first>
<second>data/poly_50kVp.spc</second>
</item>
<item>
<first>ISRA/waterValue</first>
<second>0.0335811</second>
</item>
<item>
<first>ISRA/airValue</first>
<second>0.000140093</second>
</item>
<item>
<first>FDK/waterValue</first>
<second>0.00236188</second>
</item>
<item>
<first>FDK/airValue</first>
<second>0.00000658754</second>
</item>
</_params>
<_sections class_id="3" tracking_level="0" version="0">
<count>5</count>
<item_version>0</item_version>
<item>Reconstruction</item>
<item>Reconstruction_mouse</item>
<item>Reconstruction_rat</item>
<item>ISRA</item>
<item>FDK</item>
</_sections>
</params>
</boost_serialization>' | sudo tee /home/molecubes/data/reconstructionParametersATTMAP.xml > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/reconstructionParametersATTMAP.xml

	echo -e '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<!DOCTYPE boost_serialization>
<boost_serialization signature="serialization::archive" version="11">
<params class_id="0" tracking_level="0" version="0">
<_params class_id="1" tracking_level="0" version="0">
<count>17</count>
<item_version>0</item_version>
<item class_id="2" tracking_level="0" version="0">
<first>Reconstruction/cudaDevice</first>
<second>0</second>
</item>
<item>
<first>Reconstruction/output_filename</first>
<second>resulti%03i.img</second>
</item>
<item>
<first>Reconstruction/suffix</first>
<second>HR</second>
</item>
<item>
<first>Reconstruction_mouse/recon_voxels_x</first>
<second>500</second>
</item>
<item>
<first>Reconstruction_mouse/recon_voxels_y</first>
<second>500</second>
</item>
<item>
<first>Reconstruction_mouse/recon_voxels_z</first>
<second>500</second>
</item>
<item>
<first>Reconstruction_rat/recon_voxels_x</first>
<second>700</second>
</item>
<item>
<first>Reconstruction_rat/recon_voxels_y</first>
<second>700</second>
</item>
<item>
<first>Reconstruction_rat/recon_voxels_z</first>
<second>350</second>
</item>
<item>
<first>Reconstruction/voxelsizeX</first>
<second>0.02</second>
</item>
<item>
<first>Reconstruction/voxelsizeY</first>
<second>0.02</second>
</item>
<item>
<first>Reconstruction/voxelsizeZ</first>
<second>0.02</second>
</item>
<item>
<first>Reconstruction/spectrum</first>
<second>data/poly_50kVp.spc</second>
</item>
<item>
<first>ISRA/waterValue</first>
<second>0.0310422</second>
</item>
<item>
<first>ISRA/airValue</first>
<second>0.00230207</second>
</item>
<item>
<first>FDK/waterValue</first>
<second>0.0022577</second>
</item>
<item>
<first>FDK/airValue</first>
<second>0.00020277</second>
</item>
</_params>
<_sections class_id="3" tracking_level="0" version="0">
<count>5</count>
<item_version>0</item_version>
<item>Reconstruction</item>
<item>Reconstruction_mouse</item>
<item>Reconstruction_rat</item>
<item>ISRA</item>
<item>FDK</item>
</_sections>
</params>
</boost_serialization>' | sudo tee /home/molecubes/data/reconstructionParametersBar.xml > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/reconstructionParametersBar.xml

	echo -e '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<!DOCTYPE boost_serialization>
<boost_serialization signature="serialization::archive" version="11">
<params class_id="0" tracking_level="0" version="0">
<_params class_id="1" tracking_level="0" version="0">
<count>17</count>
<item_version>0</item_version>
<item class_id="2" tracking_level="0" version="0">
<first>Reconstruction/cudaDevice</first>
<second>0</second>
</item>
<item>
<first>Reconstruction/output_filename</first>
<second>resulti%03i.img</second>
</item>
<item>
<first>Reconstruction/suffix</first>
<second>HR</second>
</item>
<item>
<first>Reconstruction_mouse/recon_voxels_x</first>
<second>400</second>
</item>
<item>
<first>Reconstruction_mouse/recon_voxels_y</first>
<second>400</second>
</item>
<item>
<first>Reconstruction_mouse/recon_voxels_z</first>
<second>400</second>
</item>
<item>
<first>Reconstruction_rat/recon_voxels_x</first>
<second>700</second>
</item>
<item>
<first>Reconstruction_rat/recon_voxels_y</first>
<second>700</second>
</item>
<item>
<first>Reconstruction_rat/recon_voxels_z</first>
<second>350</second>
</item>
<item>
<first>Reconstruction/voxelsizeX</first>
<second>0.1</second>
</item>
<item>
<first>Reconstruction/voxelsizeY</first>
<second>0.1</second>
</item>
<item>
<first>Reconstruction/voxelsizeZ</first>
<second>0.1</second>
</item>
<item>
<first>Reconstruction/spectrum</first>
<second>data/poly_50kVp.spc</second>
</item>
<item>
<first>ISRA/waterValue</first>
<second>0.0335811</second>
</item>
<item>
<first>ISRA/airValue</first>
<second>0.000140093</second>
</item>
<item>
<first>FDK/waterValue</first>
<second>0.00236188</second>
</item>
<item>
<first>FDK/airValue</first>
<second>0.00000658754</second>
</item>
</_params>
<_sections class_id="3" tracking_level="0" version="0">
<count>5</count>
<item_version>0</item_version>
<item>Reconstruction</item>
<item>Reconstruction_mouse</item>
<item>Reconstruction_rat</item>
<item>ISRA</item>
<item>FDK</item>
</_sections>
</params>
</boost_serialization>' | sudo tee /home/molecubes/data/reconstructionParametersHR.xml > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/reconstructionParametersHR.xml

	echo -e '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<!DOCTYPE boost_serialization>
<boost_serialization signature="serialization::archive" version="11">
<params class_id="0" tracking_level="0" version="0">
<_params class_id="1" tracking_level="0" version="0">
<count>17</count>
<item_version>0</item_version>
<item class_id="2" tracking_level="0" version="0">
<first>Reconstruction/cudaDevice</first>
<second>0</second>
</item>
<item>
<first>Reconstruction/output_filename</first>
<second>resulti%03i.img</second>
</item>
<item>
<first>Reconstruction/suffix</first>
<second>LR</second>
</item>
<item>
<first>Reconstruction_mouse/recon_voxels_x</first>
<second>200</second>
</item>
<item>
<first>Reconstruction_mouse/recon_voxels_y</first>
<second>200</second>
</item>
<item>
<first>Reconstruction_mouse/recon_voxels_z</first>
<second>200</second>
</item>
<item>
<first>Reconstruction_rat/recon_voxels_x</first>
<second>350</second>
</item>
<item>
<first>Reconstruction_rat/recon_voxels_y</first>
<second>350</second>
</item>
<item>
<first>Reconstruction_rat/recon_voxels_z</first>
<second>350</second>
</item>
<item>
<first>Reconstruction/voxelsizeX</first>
<second>0.2</second>
</item>
<item>
<first>Reconstruction/voxelsizeY</first>
<second>0.2</second>
</item>
<item>
<first>Reconstruction/voxelsizeZ</first>
<second>0.2</second>
</item>
<item>
<first>Reconstruction/spectrum</first>
<second>data/poly_50kVp.spc</second>
</item>
<item>
<first>ISRA/waterValue</first>
<second>0.0335811</second>
</item>
<item>
<first>ISRA/airValue</first>
<second>0.000140093</second>
</item>
<item>
<first>FDK/waterValue</first>
<second>0.00236188</second>
</item>
<item>
<first>FDK/airValue</first>
<second>0.00000658754</second>
</item>
</_params>
<_sections class_id="3" tracking_level="0" version="0">
<count>5</count>
<item_version>0</item_version>
<item>Reconstruction</item>
<item>Reconstruction_mouse</item>
<item>Reconstruction_rat</item>
<item>ISRA</item>
<item>FDK</item>
</_sections>
</params>
</boost_serialization>' | sudo tee /home/molecubes/data/reconstructionParametersLR.xml > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/reconstructionParametersLR.xml

	echo -e '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<!DOCTYPE boost_serialization>
<boost_serialization signature="serialization::archive" version="11">
<params class_id="0" tracking_level="0" version="0">
<_params class_id="1" tracking_level="0" version="0">
<count>17</count>
<item_version>0</item_version>
<item class_id="2" tracking_level="0" version="0">
<first>Reconstruction/cudaDevice</first>
<second>0</second>
</item>
<item>
<first>Reconstruction/output_filename</first>
<second>resulti%03i.img</second>
</item>
<item>
<first>Reconstruction/suffix</first>
<second>UHR</second>
</item>
<item>
<first>Reconstruction_mouse/recon_voxels_x</first>
<second>800</second>
</item>
<item>
<first>Reconstruction_mouse/recon_voxels_y</first>
<second>800</second>
</item>
<item>
<first>Reconstruction_mouse/recon_voxels_z</first>
<second>800</second>
</item>
<item>
<first>Reconstruction_rat/recon_voxels_x</first>
<second>7000</second>
</item>
<item>
<first>Reconstruction_rat/recon_voxels_y</first>
<second>7000</second>
</item>
<item>
<first>Reconstruction_rat/recon_voxels_z</first>
<second>10</second>
</item>
<item>
<first>Reconstruction/voxelsizeX</first>
<second>0.01</second>
</item>
<item>
<first>Reconstruction/voxelsizeY</first>
<second>0.01</second>
</item>
<item>
<first>Reconstruction/voxelsizeZ</first>
<second>0.01</second>
</item>
<item>
<first>Reconstruction/spectrum</first>
<second>data/poly_50kVp.spc</second>
</item>
<item>
<first>ISRA/waterValue</first>
<second>0.0310422</second>
</item>
<item>
<first>ISRA/airValue</first>
<second>0.00230207</second>
</item>
<item>
<first>FDK/waterValue</first>
<second>0.0022577</second>
</item>
<item>
<first>FDK/airValue</first>
<second>0.00020277</second>
</item>
</_params>
<_sections class_id="3" tracking_level="0" version="0">
<count>5</count>
<item_version>0</item_version>
<item>Reconstruction</item>
<item>Reconstruction_mouse</item>
<item>Reconstruction_rat</item>
<item>ISRA</item>
<item>FDK</item>
</_sections>
</params>
</boost_serialization>' | sudo tee /home/molecubes/data/reconstructionParametersQCMTF.xml > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/reconstructionParametersQCMTF.xml

	echo -e '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<!DOCTYPE boost_serialization>
<boost_serialization signature="serialization::archive" version="11">
<params class_id="0" tracking_level="0" version="0">
<_params class_id="1" tracking_level="0" version="0">
<count>17</count>
<item_version>0</item_version>
<item class_id="2" tracking_level="0" version="0">
<first>Reconstruction/cudaDevice</first>
<second>0</second>
</item>
<item>
<first>Reconstruction/output_filename</first>
<second>resulti%03i.img</second>
</item>
<item>
<first>Reconstruction/suffix</first>
<second>UHR</second>
</item>
<item>
<first>Reconstruction_mouse/recon_voxels_x</first>
<second>800</second>
</item>
<item>
<first>Reconstruction_mouse/recon_voxels_y</first>
<second>800</second>
</item>
<item>
<first>Reconstruction_mouse/recon_voxels_z</first>
<second>800</second>
</item>
<item>
<first>Reconstruction_rat/recon_voxels_x</first>
<second>1400</second>
</item>
<item>
<first>Reconstruction_rat/recon_voxels_y</first>
<second>1400</second>
</item>
<item>
<first>Reconstruction_rat/recon_voxels_z</first>
<second>1400</second>
</item>
<item>
<first>Reconstruction/voxelsizeX</first>
<second>0.05</second>
</item>
<item>
<first>Reconstruction/voxelsizeY</first>
<second>0.05</second>
</item>
<item>
<first>Reconstruction/voxelsizeZ</first>
<second>0.05</second>
</item>
<item>
<first>Reconstruction/spectrum</first>
<second>data/poly_50kVp.spc</second>
</item>
<item>
<first>ISRA/waterValue</first>
<second>0.0335811</second>
</item>
<item>
<first>ISRA/airValue</first>
<second>0.000140093</second>
</item>
<item>
<first>FDK/waterValue</first>
<second>0.00236188</second>
</item>
<item>
<first>FDK/airValue</first>
<second>0.00000658754</second>
</item>
</_params>
<_sections class_id="3" tracking_level="0" version="0">
<count>5</count>
<item_version>0</item_version>
<item>Reconstruction</item>
<item>Reconstruction_mouse</item>
<item>Reconstruction_rat</item>
<item>ISRA</item>
<item>FDK</item>
</_sections>
</params>
</boost_serialization>' | sudo tee /home/molecubes/data/reconstructionParametersUHR.xml > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/reconstructionParametersUHR.xml
}

function create_xray_files() {
	sudo hostnamectl set-hostname xrayserver$(echo $SERIAL | sed -e "s/\([C,P,S]\)[0-9][0-9]\([0-9][0-9]\)[0-9][0-9]/\1\2/")

	if [ "$VIRTUAL" = false ]; then
		echo_step "  Enabling Xray tube"
		echo "SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"0403\", ATTRS{idProduct}==\"6001\", SYMLINK+=\"xraytube\"" | sudo tee /etc/udev/rules.d/99-usb-serial.rules > /dev/null
		sudo udevadm control --reload-rules
		sudo udevadm trigger
		sleep 1
		if [ ! -L  /dev/xraytube ]; then
			exit_with_message "Failed to enable xraytube"
		fi
		echo_success
	fi
	echo_step "  Creating Xray files"
	echo -e "[Unit]
Description=Molecubes xrayserver
After=syslog.target network.target

[Service]
Type=simple
User=molecubes
Group=molecubes
# How to stop the service
KillSignal=SIGINT
ExecReload=/bin/kill -SIGHUP \$MAINPID
# restart for every return code except when clean exit code or signal
Restart=on-failure
# restart after 5 seconds wait
RestartSec=5
Environment=PUREGEV_ROOT=/opt/pleora/ebus_sdk/Ubuntu-x86_64
Environment=GENICAM_ROOT=/opt/pleora/ebus_sdk/Ubuntu-x86_64/lib/genicam
Environment=GENICAM_ROOT_V3_1=/opt/pleora/ebus_sdk/Ubuntu-x86_64/lib/genicam
Environment=GENICAM_LOG_CONFIG=/opt/pleora/ebus_sdk/Ubuntu-x86_64/lib/genicam/log/config/DefaultLogging.properties
Environment=GENICAM_LOG_CONFIG_V3_1=/opt/pleora/ebus_sdk/Ubuntu-x86_64/lib/genicam/log/config/DefaultLogging.properties
Environment=GENICAM_CACHE_V3_1=/home/molecubes/.config/Pleora/genicam_cache_v3_1
Environment=GENICAM_CACHE=/home/molecubes/.config/Pleora/genicam_cache_v3_1
WorkingDirectory=/home/molecubes/
ExecStartPre=/bin/sleep 30
ExecStart=/home/molecubes/serverloader /home/molecubes/xrayserver.mmf 50010 --config=/home/molecubes/xrayserver.ini

[Install]
WantedBy=multi-user.target" | sudo tee /lib/systemd/system/xrayserver.service > /dev/null
	sudo systemctl daemon-reload

	echo "PATH=\"/opt/pleora/ebus_sdk/Ubuntu-x86_64/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games\"
LD_LIBRARY_PATH=\"/opt/pleora/ebus_sdk/Ubuntu-x86_64/lib/genicam/bin/Linux64_x64:/opt/pleora/ebus_sdk/Ubuntu-x86_64/lib:\${LD_LIBRARY_PATH}\"" | sudo tee /etc/environment > /dev/null

	echo -e '#!/bin/bash
export PUREGEV_ROOT=/opt/pleora/ebus_sdk/Ubuntu-x86_64
export GENICAM_ROOT=/opt/pleora/ebus_sdk/Ubuntu-x86_64/lib/genicam
export GENICAM_ROOT_V3_1=/opt/pleora/ebus_sdk/Ubuntu-x86_64/lib/genicam
export GENICAM_LOG_CONFIG=/opt/pleora/ebus_sdk/Ubuntu-x86_64/lib/genicam/log/config/DefaultLogging.properties
export GENICAM_LOG_CONFIG_V3_1=/opt/pleora/ebus_sdk/Ubuntu-x86_64/lib/genicam/log/config/DefaultLogging.properties
export GENICAM_CACHE_V3_1=/home/molecubes/.config/Pleora/genicam_cache_v3_1
export GENICAM_CACHE=/home/molecubes/.config/Pleora/genicam_cache_v3_1' | sudo tee /home/molecubes/bin/env.sh > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/bin/env.sh
	sudo chmod +x /home/molecubes/bin/env.sh

	echo -e "[global]
port = 5005
port_monitor = 5006
logfile = xrayserver.log
logpath = /home/molecubes/
outputPath = /home/molecubes/data
deviceSerialNumber = $SERIAL

[tube]
serialPort = /dev/xraytube
model = virtual
minkvp = 50
maxkvp = 50

[detector]
min_exposure = 10
max_exposure = 500" | sudo tee /home/molecubes/xrayserver.ini > /dev/null
if [ "$VIRTUAL" = true ]; then
	echo -e "model = virtual" | sudo tee -a /home/molecubes/xrayserver.ini > /dev/null
fi

	sudo chown molecubes:molecubes /home/molecubes/xrayserver.ini

	echo -e "xrayserver.so
$PACKAGEVERSION
LDJD212" | sudo tee /home/molecubes/xrayserver.mmf > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/xrayserver.mmf

	sudo touch /home/molecubes/xrayserver.so

	if [ ! -f eBUS6024879.deb ]; then
		echo_step "  Adding eBus SDK"
		$FETCHER https://cdn.molecubes.com/builds/eBUS_SDK_Ubuntu-x86_64-6.0.2-4879.deb -O eBUS6024879.deb
		sudo dpkg -i eBUS6024879.deb
        sudo /opt/pleora/ebus_sdk/Ubuntu-x86_64/module/install_driver.sh --uninstall && echo_success || ( echo -e "Failed to add eBus SDK" >> "$FRESH_INSTALL_LOG" && echo_failure )
	fi

	if [ "$VIRTUAL" = false ]; then
		echo_step "Setting MAC address"
		sudo sed -i -e "s/\(macaddress: \).*$/\1$(ifconfig enp2s0 | grep ether | cut -d " " -f 10)/" /etc/netplan/01-netcfg.yaml && echo_success || ( echo -e "Failed to set MAC address" >> "$FRESH_INSTALL_LOG" && echo_failure )
	fi

	echo_success
}

################################################################################
# PET install functions
################################################################################

function configure_petacq_motors() {
	if [ "$VIRTUAL" = true ]; then
		return 0
	fi

	echo_step "  Enabling PET motors"
	if [ "$MOBO" == "D3434-S2" ]; then
		# Detected Kontron board
		echo "# udevadm info --name=/dev/ttyUSB0 --attribute-walk
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"0403\", ATTRS{idProduct}==\"6001\", ATTRS{devpath}==\"5\", SYMLINK+=\"bedmotor\"
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"2341\", ATTRS{idProduct}==\"0042\", ATTRS{devpath}==\"6\", SYMLINK+=\"progressleds\"
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"2341\", ATTRS{idProduct}==\"0042\", ATTRS{devpath}==\"2\", SYMLINK+=\"monitoring\"
" | sudo tee /etc/udev/rules.d/99-usb-serial.rules > /dev/null
	else
		echo "# udevadm info --name=/dev/ttyUSB0 --attribute-walk
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"0403\", ATTRS{idProduct}==\"6001\", ATTRS{devpath}==\"3\", SYMLINK+=\"bedmotor\"
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"2341\", ATTRS{idProduct}==\"0042\", ATTRS{devpath}==\"1\", SYMLINK+=\"progressleds\"
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"2341\", ATTRS{idProduct}==\"0042\", ATTRS{devpath}==\"2\", SYMLINK+=\"monitoring\"
" | sudo tee /etc/udev/rules.d/99-usb-serial.rules > /dev/null
	fi
	sudo udevadm control --reload-rules
	sudo udevadm trigger
	sleep 2
	if  [ ! -L  /dev/bedmotor ]; then
		exit_with_message "Failed enable bedmotor"
	elif  [ ! -L  /dev/progressleds ]; then
		exit_with_message "Failed enable progressleds"
	elif  [ ! -L  /dev/monitoring ]; then
		exit_with_message "Failed enable monitoring"
	fi
	if [ ! -f d3xx-linux-x86_64-0.5.21.tar.zip ]; then
		$FETCHER https://cdn.molecubes.com/install/d3xx-linux-x86_64-0.5.21.tar.zip -O d3xx-linux-x86_64-0.5.21.tar.zip
	fi
	if [ ! -f d3xx-linux-x86_64-0.5.21.tar.bz2 ]; then
		unzip d3xx-linux-x86_64-0.5.21.tar.zip
	fi
	if [ ! -f libftdi3xx ]; then
		tar jxvf d3xx-linux-x86_64-0.5.21.tar.bz2
		mv linux-x86_64 libftdi3xx
	fi
	if [ ! -f /etc/udev/rules.d/51-ftd3xx.rules ]; then
		sudo cp libftdi3xx/51-ftd3xx.rules /etc/udev/rules.d/
	fi
	sudo udevadm control --reload-rules
	sudo udevadm trigger
	echo_success
}

function setup_petacq_network_drives() {
	echo_step "  Setting up network drives"
	sudo mkdir -p /export/data || true
	sudo mkdir -p /export/conf || true
	sudo chmod 777 /export || true
	sudo chmod 777 /export/data || true
	sudo chmod 777 /export/conf || true
	if ! grep -q "192.168.0.0/24" /etc/exports; then
		sudo cp /etc/exports /etc/exports.old
		ID=$(id molecubes | sed "s/^uid=\([0-9]*\)(.*$/\1/")
		echo -e "
/export\t\t10.0.0.0/24(rw,fsid=0,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) 192.168.0.0/24(rw,fsid=0,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
/export/data\t10.0.0.0/24(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) 192.168.0.0/24(rw,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
/export/conf\t10.0.0.0/24(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) 192.168.0.0/24(rw,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
" | sudo tee -a /etc/exports > /dev/null
	fi
	if [ "$VIRTUAL" = true ]; then
		GUI_IP_ADDRESS="auto-test-gui.in.molecubes.com"
		REMI_IP_ADDRESS="auto-test-remi.in.molecubes.com"
		PETRECON_IP_ADDRESS="auto-test-bcuberecon.in.molecubes.com"
		ID=$(id molecubes | sed "s/^uid=\([0-9]*\)(.*$/\1/")
		if ! grep -q "${GUI_IP_ADDRESS}" /etc/exports; then
			echo -e "
/export\t\t${PETRECON_IP_ADDRESS}(rw,fsid=0,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) ${GUI_IP_ADDRESS}(rw,fsid=0,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) ${REMI_IP_ADDRESS}(rw,fsid=0,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
/export/data\t${PETRECON_IP_ADDRESS}(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) ${GUI_IP_ADDRESS}(rw,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) ${REMI_IP_ADDRESS}(rw,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
/export/conf\t${PETRECON_IP_ADDRESS}(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) ${GUI_IP_ADDRESS}(rw,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) ${REMI_IP_ADDRESS}(rw,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
" | sudo tee -a /etc/exports > /dev/null
		fi
	fi
	if ! grep -q "home/molecubes/data" /etc/fstab; then
		echo -e "/home/molecubes/data\t/export/data\tnone\tbind\t0\t0" | sudo tee -a /etc/fstab > /dev/null
		echo -e "/home/molecubes/conf\t/export/conf\tnone\tbind\t0\t0" | sudo tee -a /etc/fstab > /dev/null
		sudo mount -a
	fi
	sudo service nfs-kernel-server restart
	if [ -d "/export/data" ]; then
		echo_success
	else
		echo -e "Failed to create /export/data" >> "$FRESH_INSTALL_LOG"
		echo_failure
	fi
}

function setup_petrecon_network_drives() {
	PETACQ_MOUNT_IP_ADDRESS="10.0.0.1"
	CTRECON_MOUNT_IP_ADDRESS="192.168.0.170"
	if [ "$VIRTUAL" = true ]; then
		PETACQ_MOUNT_IP_ADDRESS="auto-test-bcubeacq.in.molecubes.com"
		CTRECON_MOUNT_IP_ADDRESS="auto-test-xcubeacqrecon.in.molecubes.com"
	fi

	echo_step "  Setting up network drives"
	sudo mkdir -p /export/dataRECON || true
	if ! grep -q "192.168.0.0/24" /etc/exports; then
		ID=$(id molecubes | sed "s/^uid=\([0-9]*\)(.*$/\1/")
		echo -e "
/export\t\t10.0.0.0/24(rw,fsid=0,insecure,no_subtree_check,async,sec=sys) 192.168.0.0/24(rw,fsid=0,insecure,no_subtree_check,async,sec=sys)
/export/dataRECON\t192.168.0.0/24(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
" | sudo tee -a /etc/exports > /dev/null
	fi
	if [ "$VIRTUAL" = true ]; then
		GUI_IP_ADDRESS="auto-test-gui.in.molecubes.com"
		REMI_IP_ADDRESS="auto-test-remi.in.molecubes.com"
		if ! grep -q "${GUI_IP_ADDRESS}" /etc/exports; then
			ID=$(id molecubes | sed "s/^uid=\([0-9]*\)(.*$/\1/")
			echo -e "
/export\t\t${GUI_IP_ADDRESS}(rw,fsid=0,insecure,no_subtree_check,async,sec=sys) ${REMI_IP_ADDRESS}(rw,fsid=0,insecure,no_subtree_check,async,sec=sys)
/export/dataRECON\t${GUI_IP_ADDRESS}(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) ${REMI_IP_ADDRESS}(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
" | sudo tee -a /etc/exports > /dev/null
		fi
	fi

	if ! grep -q "xcube" /etc/auto.nfs; then
		echo -e "/mnt\t/etc/auto.nfs" | sudo tee -a /etc/auto.master > /dev/null
		echo -e "data\t-fstype=nfs4\t${PETACQ_MOUNT_IP_ADDRESS}:/data" | sudo tee -a /etc/auto.nfs > /dev/null
		echo -e "conf\t-fstype=nfs4\t${PETACQ_MOUNT_IP_ADDRESS}:/conf" | sudo tee -a /etc/auto.nfs > /dev/null
		echo -e "xcube\t-fstype=nfs4\t${CTRECON_MOUNT_IP_ADDRESS}:/data" | sudo tee -a /etc/auto.nfs > /dev/null
		sudo service autofs restart
	fi
	if ! grep -q "home/molecubes/data" /etc/fstab; then
		echo -e "/home/molecubes/data\t/export/dataRECON\tnone\tbind\t0\t0" | sudo tee -a /etc/fstab > /dev/null
		sudo mount -a
	fi
	sudo service nfs-kernel-server restart
	if [ -d "/export/dataRECON" ]; then
		echo_success
	else
		echo -e "Failed to create /export/dataRECON" >> "$FRESH_INSTALL_LOG"
		echo_failure
	fi
}

function create_petacq_files() {
	sudo hostnamectl set-hostname bcubeacq$(echo $SERIAL | sed -e "s/\([C,P,S]\)[0-9][0-9]\([0-9][0-9]\)[0-9][0-9]/\1\2/")
	echo -e "[global]
type = PET
version = 1
port = 5000
deviceSerialNumber = $SERIAL
logfile = acquisitionserver.log
logpath = /home/molecubes/
outputPath = /home/molecubes/data/
patch = 0" | sudo tee /home/molecubes/acquisitionserver.ini > /dev/null

DEFAULT_IP_ADDRESS="192.168.0.120"
if [ "$VIRTUAL" = true ]; then
	DEFAULT_IP_ADDRESS="auto-test-bcubeacq.in.molecubes.com"
fi

echo -e "
[network]
publicIPAddress = ${DEFAULT_IP_ADDRESS}" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null

echo -e "
[PET]
calibrationDataPath = default" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null
if [ "$VIRTUAL" = true ]; then
	echo -e "systemType = virtual" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null
fi

echo -e "
[component]
bedPath = /dev/cu.usbserial-A101LRU6
#bedMotorType = CM10-3A
bedMotorType = virtual" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null

echo -e "
[detector]
configFolder=/home/molecubes/conf/
nr_blocks=4
block_size=41943040" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null

echo -e "
[monitoring]
serialPort = /dev/monitoring
baudRate = 115200
Vref = 2.42
buffersize = 20
samplingRate = 666
breathingFilter = 1
breathingFilterSize = 10
heartrateFilter = 1
heartrateFilterSize = 1
maxPWM_basic_mouse = 80
maxPWM_monitoring_mouse = 100
maxPWM_basic_rat = 130
maxPWM_monitoring_rat = 150
maxPWM_basic_ratXL = 130
maxPWM_monitoring_ratXL = 150
maxPWM_basic_custom = 0
maxPWM_monitoring_custom = 0
maxPWM_basic_unknown = 0
maxPWM_monitoring_unknown = 0
maxPWM_basic_ratXL_hotel = 72
maxPWM_monitoring_ratXL_hotel = 72
maxPWM_basic_rat_hotel = 72
maxPWM_monitoring_rat_hotel = 72
mouse4hotel_uids = 
mouse3hotel_uids = " | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null
if [ "$VIRTUAL" = true ]; then
	echo -e "type = virtual" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null
fi

echo -e "
[internal]
gpu_threads = 2048" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null

MOTORTYPE="CM10-1A"
if [ "$VIRTUAL" = true ]; then
	MOTORTYPE="virtual"
fi

echo -e "
[bed]
serialPort = /dev/bedmotor
baudRate = 115200
motorType = ${MOTORTYPE}
homeVelocity = 5
startVelocity = 2
runVelocity = 10
accelerationTime = 1
decelerationTime = 1
distancePerRevolution = 2.5
motorResolution = 1000
gearA = 1
gearB = 1
nrPositions_mouse = 10
nrPositions_rat = 12
nrPositions_custom = 12
nrPositions_default = 10
startPosition_mouse = 31.3
length_mouse = 200
startPosition_rat = 40.5
length_rat = 250
startPosition_custom = 37
length_custom = 250
startPosition_default = 40.5
length_default = 200
hometyp = 0
maximum_position = 210" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null

echo -e "
[progressleds]
serialPort=/dev/progressleds
baudRate=9600" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null
if [ "$VIRTUAL" = true ]; then
	echo -e "type = virtual" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null
fi

echo -e "
[positioning]
algorithm=MLNORMLAYDOI
nr_layers=1
nr_det=9
nr_channels=16
energy_res=0.30
pos_dimy=120
pos_dimx=120
det_dimx=128
det_dimy=128
pos_mask=/home/molecubes/Workspace/conf/calibration/position_probmap
det0=/home/molecubes/Workspace/conf/calibration/DET1/
det1=/home/molecubes/Workspace/conf/calibration/DET2/
det2=/home/molecubes/Workspace/conf/calibration/DET3/
det3=/home/molecubes/Workspace/conf/calibration/DET4/
det4=/home/molecubes/Workspace/conf/calibration/DET5/
det5=/home/molecubes/Workspace/conf/calibration/DET6/
det6=/home/molecubes/Workspace/conf/calibration/DET7/
det7=/home/molecubes/Workspace/conf/calibration/DET8/
det8=/home/molecubes/Workspace/conf/calibration/DET10/" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/acquisitionserver.ini

	echo -e "0.0
0.0
0.0
1.0
0.0
0.0
0.0
1.0
0.0
0.0
0.0
1.0" | sudo tee /home/molecubes/data/registration.matrix > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/registration.matrix

	sudo echo -e "acquisitionserver.so
$PACKAGEVERSION
9R3IR8" | sudo tee /home/molecubes/acquisitionserver.mmf > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/acquisitionserver.mmf

	echo -e "[GENERAL]
serial=$SERIAL
version=0x12
calib=/home/molecubes/conf/Calib/default
config_folder=/home/molecubes/conf/
main_lookup=0
int_time=300
temp=23

[MAINS]
nr_mains=5
main_0=MCMain0
main_1=MCMain1
main_2=MCMain2
main_3=MCMain3
main_4=MCMain4

[IO]
nr_blocks=8
block_size=335544320

[STAGE]
bdrate=9600
timeout=5

[POSITIONING]
algorithm=MLNORMLAYDOI
modality=PET
nr_layers=5
nr_doi_layers=8
nr_det=9
nr_main=5
nr_channels=16
energy_res=0.20
pos_dimy=63
pos_dimx=63
det_dimx=63
det_dimy=63
pos_area=25.2
pos_mask=/home/molecubes/Workspace/conf/calibration/position_probmap
calib_iter=1

[STATE]
state=0
info=System OK" | sudo tee /home/molecubes/conf/Systems/system.ini > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/conf/Systems/system.ini

	echo -e "[GENERAL]
config=/home/molecubes/conf/
calib=/home/molecubes/conf/Calib/default/

[IMAGE]
dimx=192    # should be multiple of 96!
dimy=192    # should be multiple of 96!
dimz=384    # should be multiple of 96!
vx=0.4
vy=0.4
vz=0.4

[SINO3]
dimr=128
dims=128
dima=140
dimb=140
vr=0.4
vs=0.4
va=1.0
vb=1.0

[FBP]
cutoff=20
xoffset=0
yoffset=0
zoffset=0

[SINO2]
dimr=192
dima=360
dims=1
vr=0.2
va=0.5
vs=1.0
ringdiff=10
det_size=24


[IO]
folder=
emiss_map=
atten_map=
#/home/molecubes/data/norm/coinc/1bed/15min/attmap
sens_map=
norm_map=1
norm_thresh=0.35
normsens_map=0


[PROJECTION]
tube_fwhm=0.6

[RECON]
gpu_block_nr_events=184320
gpu_block_dim=1024
nr_iter=30
nr_subsets=10
#subset_size=0
subset_size=20000000
save_iter=10
fov=65
bed_shift=55.0
#ax_fov=75
ax_fov=120
smooth_iter=5
reg_param=0.0
reg_thresh=0.05
reg_fwhm=1.0
reg_region=3
roll_off_thresh=25.6
roll_off_strength=2
border_cut=0
att_corr=1
rand_corr=1
deadtime_corr=1
sss_corr=1
doi=1
doi_layers=5
penalty_param=0.0
cuda_fast=1
subset_mode=1

[CALIBRATION]
norm_dimx=
norm_dimy=
norm_dimz=
pos_dimx=63
pos_dimy=63
pos_step=0.4
calib=/home/molecubes/conf/Calib/calibration/System/grid.ini
params=/home/molecubes/conf/Calib/calibration/det_param.ini
use_params=0
fminsearch_iter=100
nr_iter=10
flood_mask=
crt_hist_npix=4
norm_doi=1
qscale=1.0763

[QSCALE]
F-18 = 1.0763

[SENSITIVITY]
max_nr_events=2949120000
#max_nr_events=1474560000
#max_nr_events=737280000
nr_bed=1
thresh=0.1

[SCANNER]
nr_ring=5
nr_det_per_ring=9
min_det_diff=2
radius=38.87
det_dimx=25.4   # Transaxial plane (wide)
det_dimy=25.4   # Axial plane (height)
det_dimz=8.0    # Transaxial plane (depth)
det_axial_pitch=26.8
det_local_shiftx = 0.0
det_local_shiftz = 0.0
det_angle_offset = 100.0
det_eff = 1.0
nr_doi_layers=5
default_coinc_win=16
coinc_win=15
delay_offset=240

[SIMULATOR]
crystal_attenuation=0.087
scatter_density=0.04
energy_res=0.2

[SIMULATOR-SPHERE]
pointx=-1.03
pointy=-0.18
pointz=-4.59
radius=0.15

[SIMULATOR-CYLINDER]
radius=30.0
height=140.0

[SIMULATOR-ANNULUS]
inner_radius=13.5
outer_radius=14.5
height=25.0" | sudo tee /home/molecubes/conf/Recon/recon.ini > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/conf/Recon/recon.ini

	if [ ! -f /home/molecubes/conf/createSystem.sh ]; then
		echo_step "  Creating PET system"
		sudo -u molecubes $FETCHER https://cdn.molecubes.com/install/PET/createSystem.sh -O /home/molecubes/conf/createSystem.sh
		if [ -f /home/molecubes/conf/createSystem.sh ]; then
			NUM=$(echo $SERIAL | sed -e "s/[C,P,S][0-9][0-9]\([0-9][0-9]\)[0-9][0-9]/\1/")
			sudo bash /home/molecubes/conf/createSystem.sh $SERIAL $NUM && echo_success || ( echo -e "Failed to run create system script" >> "$FRESH_INSTALL_LOG" && echo_failure )
		else
			echo -e "Failed to download create system script" >> "$FRESH_INSTALL_LOG" && echo_failure
		fi
	fi

	sudo chown -R molecubes:molecubes /home/molecubes/conf/Calib/default/

	if [ ! -f /home/molecubes/conf/Calib/default/setMeans.sh ]; then
		echo_step "  Setup default calibration data"
		sudo -u molecubes $FETCHER https://cdn.molecubes.com/install/PET/setMeans.sh -O /home/molecubes/conf/Calib/default/setMeans.sh
		sudo -u molecubes $FETCHER https://cdn.molecubes.com/install/PET/means_interp_80x63x63.bin -O /home/molecubes/conf/Calib/default/means_interp_sim_80x63x63.bin
		sudo -u molecubes $FETCHER https://cdn.molecubes.com/install/PET/peaks_interp_63x63.bin -O /home/molecubes/conf/Calib/default/peaks_interp_sim_63x63.bin
		sudo -u molecubes $FETCHER https://cdn.molecubes.com/install/PET/norm_63x63x45.bin -O /home/molecubes/conf/Calib/default/normalisation/norm_63x63x45.bin
		sudo -u molecubes $FETCHER https://cdn.molecubes.com/install/PET/norm_63x63x225.bin -O /home/molecubes/conf/Calib/default/normalisation/norm_63x63x225.bin
		if [ -f /home/molecubes/conf/Calib/default/setMeans.sh ]; then
			cd /home/molecubes/conf/Calib/default/
			sudo bash /home/molecubes/conf/Calib/default/setMeans.sh
			cd /home/dev
		else
			echo -e "Failed to download create system script" >> "$FRESH_INSTALL_LOG" && echo_failure
		fi
	fi

	if [ ! -f  /home/molecubes/conf/Calib/default/sensitivity/sensitivity.hist ]; then
		echo_step "  Downloading sensitivity histogram"
		sudo -u molecubes $FETCHER https://cdn.molecubes.com/install/PET/sensitivity.hist -O /home/molecubes/conf/Calib/default/sensitivity/sensitivity.hist
		if [ ! -f /home/molecubes/conf/Calib/default/sensitivity/sensitivity.hist ]; then
			echo -e "Failed to download sensitivity.hist" >> "$FRESH_INSTALL_LOG" && echo_failure
		fi
	fi

	if [ ! -f  /home/molecubes/conf/Calib/default/nishina_511keV_181x1.bin ]; then
		echo_step "  Downloading nishina klein kernel"
		sudo -u molecubes $FETCHER https://cdn.molecubes.com/install/PET/nishina_511keV_181x1.bin -O /home/molecubes/conf/Calib/default/nishina_511keV_181x1.bin
		if [ ! -f /home/molecubes/conf/Calib/default/nishina_511keV_181x1.bin ]; then
			echo -e "Failed to download nishina_511keV_181x1.bin" >> "$FRESH_INSTALL_LOG" && echo_failure
		fi
	fi

	if [ ! "$(ls -A /home/molecubes/conf/Calib/Library/)" ]; then
		echo_step "  Downloading default calibration Library"
		sudo -u molecubes $FETCHER https://cdn.molecubes.com/install/PET/Calib.zip -O /home/molecubes/conf/Calib.zip
		if [ ! -f /home/molecubes/conf/Calib.zip ]; then
			echo -e "Failed to download default Library files" >> "$FRESH_INSTALL_LOG" && echo_failure
		else
			sudo unzip /home/molecubes/conf/Calib.zip -d /home/molecubes/conf/
			sudo chown -R molecubes:molecubes /home/molecubes/conf/
		fi
	fi

	if [ ! -f  /home/molecubes/bin/PETbiasCalib ]; then
		echo_step "  Downloading PETbiasCalib"
		sudo -u molecubes $FETCHER https://cdn.molecubes.com/install/PET/PETbiasCalib -O /home/molecubes/bin/PETbiasCalib
		if [ ! -f /home/molecubes/bin/PETbiasCalib ]; then
			echo -e "Failed to download PETbiasCalib" >> "$FRESH_INSTALL_LOG" && echo_failure
		fi
		sudo chmod +x /home/molecubes/bin/PETbiasCalib
		sudo -u molecubes ln -s /home/molecubes/libs/libfftw3.so.3 /home/molecubes/libs/libfftw3.so.3.5.7
	fi

	if [ ! -f /home/molecubes/bin/feature_PETcalib/PETflood ]; then
		echo_step "  Downloading PETflood for PETcalibration"
		sudo mkdir -p /home/molecubes/bin/feature_PETcalib/
		sudo chown -R molecubes:molecubes /home/molecubes/bin/feature_PETcalib/
		sudo -u molecubes $FETCHER https://cdn.molecubes.com/install/PET/PETflood -O /home/molecubes/bin/feature_PETcalib/PETflood
		if [ ! -f /home/molecubes/bin/feature_PETcalib/PETflood  ]; then
			echo -e "Failed to download PETflood" >> "$FRESH_INSTALL_LOG" && echo_failure
		fi
		sudo chmod +x /home/molecubes/bin/feature_PETcalib/PETflood
	fi

	if [ ! -f /home/molecubes/libs/libboost_filesystem.so.1.69.0 ]; then
		echo_step "  Downloading older libraries to use for PETflood"
		sudo -u molecubes $FETCHER https://cdn.molecubes.com/install/PET/v1.6_libraries.tar.gz -O /home/molecubes/bin/feature_PETcalib/v1.6_libraries.tar.gz
		if [ ! -f /home/molecubes/bin/feature_PETcalib/v1.6_libraries.tar.gz ]; then
			echo -e "Failed to download v1.6 libraries" >> "$FRESH_INSTALL_LOG" && echo_failure
		fi
		sudo -u molecubes tar zx --keep-newer-files -f /home/molecubes/bin/feature_PETcalib/v1.6_libraries.tar.gz -C /home/molecubes/libs/
	fi

	echo_step "  Setting permissions"
	cd /home/dev
	sudo chown -R molecubes:molecubes /home/molecubes/conf/* /home/molecubes/bin/* && echo_success || ( echo -e "Failed to set permissions" >> "$FRESH_INSTALL_LOG" && echo_failure )
}

function create_petrecon_files() {
	DEFAULT_IP_ADDRESS="192.168.0.120"
	if [ "$VIRTUAL" = true ]; then
		# We use the real IP of the PETrecon here, because in virtual testing it's not in an IP_Forwarding mode from on the acq server
		DEFAULT_IP_ADDRESS="auto-test-bcuberecon.in.molecubes.com"
	fi

	DEFAULT_CT_IP_ADDRESS="192.168.0.170"
	if [ "$VIRTUAL" = true ]; then
		DEFAULT_CT_IP_ADDRESS="auto-test-xcubeacqrecon.in.molecubes.com"
	fi

	DEFAULT_PET_ACQ_IP_ADDRESS_LOCAL="10.0.0.1"
	DEFAULT_PET_RECON_IP_ADDRESS_LOCAL="10.0.0.2"
	if [ "$VIRTUAL" = true ]; then
		DEFAULT_PET_ACQ_IP_ADDRESS_LOCAL="auto-test-bcubeacq.in.molecubes.com"
		DEFAULT_PET_RECON_IP_ADDRESS_LOCAL=${DEFAULT_IP_ADDRESS}
	fi

	sudo hostnamectl set-hostname bcuberecon$(echo $SERIAL | sed -e "s/\([C,P,S]\)[0-9][0-9]\([0-9][0-9]\)[0-9][0-9]/\1\2/")
	echo -e "[global]
type = PET
version = 1
port = 5001
logfile = reconstructionserver.log
logpath = /home/molecubes/
outputPath = /home/molecubes/data
deviceSerialNumber = $SERIAL

[PET]
calibPath = /mnt/conf/Calib/

[internal]
localEthIPAddress = ${DEFAULT_PET_RECON_IP_ADDRESS_LOCAL}
localIPAddress = ${DEFAULT_IP_ADDRESS}
#receiveDatasetPort = 6767
#acquisitionServerIP = 10.0.0.2
acquisitionServerEthIP = ${DEFAULT_PET_ACQ_IP_ADDRESS_LOCAL}

[dicom]
institutionName = Molecubes
institutionAddress = Infinity
institutionDepartmentName = Lab
deviceSerialNumber = $SERIAL
serveraddress = 192.168.2.1
serverport = 8042
username = molecubes
password = molecubes

[CT]
remoteIPaddress=${DEFAULT_CT_IP_ADDRESS}
reconstructionServerPort=5001
datapath=/mnt/xcube

[registration]
matrixPath = /home/molecubes/data/registration.matrix

[output]
histogramRescale=1
filenameFormat = %d_%m_%g_%r_frame%f_iter%i" | sudo tee /home/molecubes/reconstructionserver.ini > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/reconstructionserver.ini

	echo -e "reconstructionserver.so
$PACKAGEVERSION
9R3IR8" | sudo tee /home/molecubes/reconstructionserver.mmf > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/reconstructionserver.mmf

	echo -e "[GENERAL]
serial=P001900
version=0x12
calib=/home/molecubes/conf/Calib/default
config_folder=/home/molecubes/conf/
main_lookup=0
int_time=300
temp=23

[MAINS]
nr_mains=5
main_0=MCMain0
main_1=MCMain1
main_2=MCMain2
main_3=MCMain3
main_4=MCMain4

[IO]
nr_blocks=8
block_size=335544320

[STAGE]
bdrate=9600
timeout=5

[POSITIONING]
algorithm=MLNORMLAYDOI
modality=PET
nr_layers=5
nr_doi_layers=8
nr_det=9
nr_main=5
nr_channels=16
energy_res=0.20
pos_dimy=63
pos_dimx=63
det_dimx=63
det_dimy=63
pos_area=25.2
pos_mask=/home/molecubes/Workspace/conf/calibration/position_probmap
calib_iter=1

[STATE]
state=0
info=System OK" | sudo tee /home/molecubes/conf/Systems/system.ini > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/conf/Systems/system.ini

	echo -e "[GENERAL]
config=/home/molecubes/conf/
calib=/home/molecubes/conf/Calib/default/

[IMAGE]
dimx=192    # should be multiple of 96!
dimy=192    # should be multiple of 96!
dimz=384    # should be multiple of 96!
vx=0.4
vy=0.4
vz=0.4

[SINO3]
dimr=128
dims=128
dima=140
dimb=140
vr=0.4
vs=0.4
va=1.0
vb=1.0

[FBP]
cutoff=20
xoffset=0
yoffset=0
zoffset=0

[SINO2]
dimr=192
dima=360
dims=1
vr=0.2
va=0.5
vs=1.0
ringdiff=10
det_size=24


[IO]
folder=
emiss_map=
atten_map=
#/home/molecubes/data/norm/coinc/1bed/15min/attmap
sens_map=
norm_map=1
norm_thresh=0.35
normsens_map=0


[PROJECTION]
tube_fwhm=0.6

[RECON]
gpu_block_nr_events=184320
gpu_block_dim=1024
nr_iter=30
nr_subsets=10
#subset_size=0
subset_size=20000000
save_iter=10
fov=65
bed_shift=55.0
#ax_fov=75
ax_fov=120
smooth_iter=5
reg_param=0.0
reg_thresh=0.05
reg_fwhm=1.0
reg_region=3
roll_off_thresh=25.6
roll_off_strength=2
border_cut=0
att_corr=1
rand_corr=1
deadtime_corr=1
sss_corr=1
doi=1
doi_layers=5
penalty_param=0.0
cuda_fast=1
subset_mode=1

[CALIBRATION]
norm_dimx=
norm_dimy=
norm_dimz=
pos_dimx=63
pos_dimy=63
pos_step=0.4
calib=/home/molecubes/conf/Calib/calibration/System/grid.ini
params=/home/molecubes/conf/Calib/calibration/det_param.ini
use_params=0
fminsearch_iter=100
nr_iter=10
flood_mask=
crt_hist_npix=4
norm_doi=1
qscale=1.0763

[SENSITIVITY]
max_nr_events=2949120000
#max_nr_events=1474560000
#max_nr_events=737280000
nr_bed=1
thresh=0.1

[SCANNER]
nr_ring=5
nr_det_per_ring=9
min_det_diff=2
radius=38.87
det_dimx=25.4   # Transaxial plane (wide)
det_dimy=25.4   # Axial plane (height)
det_dimz=8.0    # Transaxial plane (depth)
det_axial_pitch=26.8
det_local_shiftx = 0.0
det_local_shiftz = 0.0
det_angle_offset = 100.0
det_eff = 1.0
nr_doi_layers=5
default_coinc_win=16
coinc_win=15
delay_offset=240

[SIMULATOR]
crystal_attenuation=0.087
scatter_density=0.04
energy_res=0.2

[SIMULATOR-SPHERE]
pointx=-1.03
pointy=-0.18
pointz=-4.59
radius=0.15

[SIMULATOR-CYLINDER]
radius=30.0
height=140.0

[SIMULATOR-ANNULUS]
inner_radius=13.5
outer_radius=14.5
height=25.0" | sudo tee /home/molecubes/conf/Recon/recon.ini > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/conf/Recon/recon.ini

	sudo touch /home/molecubes/data/PostProcessing.py
	sudo chown molecubes:molecubes /home/molecubes/data/PostProcessing.py
	sudo chmod 755 /home/molecubes/data/PostProcessing.py
}

################################################################################
# SPECT install functions
################################################################################

function configure_spectacq_motors() {
	if [ "$VIRTUAL" = true ]; then
		return 1
	fi

	echo_step "  Enabling SPECT motors"
	if [ "$MOBO" == "D3434-S2" ]; then
		# Detected Kontron board
		echo "# udevadm info --name=/dev/ttyUSB0 --attribute-walk
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"0403\", ATTRS{idProduct}==\"6001\", ATTRS{devpath}==\"4.7\", SYMLINK+=\"bedmotor\"
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"0403\", ATTRS{idProduct}==\"6001\", ATTRS{devpath}==\"4.6\", SYMLINK+=\"gantrymotor\"
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"2341\", ATTRS{idProduct}==\"0042\", ATTRS{devpath}==\"4.1\", SYMLINK+=\"progressleds\"
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"2341\", ATTRS{idProduct}==\"0042\", ATTRS{devpath}==\"4.5\", SYMLINK+=\"monitoring\"
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"0483\", ATTRS{idProduct}==\"5740\", ATTRS{serial}==\"Demo 1.000\", MODE=\"0666\", SYMLINK+=\"owis\"
" | sudo tee /etc/udev/rules.d/99-usb-serial.rules > /dev/null
	else
		echo "# udevadm info --name=/dev/ttyUSB0 --attribute-walk
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"0403\", ATTRS{idProduct}==\"6001\", ATTRS{devpath}==\"2.7\", SYMLINK+=\"bedmotor\"
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"0403\", ATTRS{idProduct}==\"6001\", ATTRS{devpath}==\"2.6\", SYMLINK+=\"gantrymotor\"
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"2341\", ATTRS{idProduct}==\"0042\", ATTRS{devpath}==\"2.1\", SYMLINK+=\"progressleds\"
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"2341\", ATTRS{idProduct}==\"0042\", ATTRS{devpath}==\"2.5\", SYMLINK+=\"monitoring\"
SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"0483\", ATTRS{idProduct}==\"5740\", ATTRS{serial}==\"Demo 1.000\", MODE=\"0666\", SYMLINK+=\"owis\"
" | sudo tee /etc/udev/rules.d/99-usb-serial.rules > /dev/null
	fi
	sudo udevadm control --reload-rules
	sudo udevadm trigger
	sleep 1
	if  [ ! -L  /dev/bedmotor ]; then
		exit_with_message "Failed enable bedmotor"
	elif  [ ! -L  /dev/gantrymotor ]; then
		exit_with_message "Failed enable gantrymotor"
	elif  [ ! -L  /dev/progressleds ]; then
		exit_with_message "Failed enable progressleds"
	elif  [ ! -L  /dev/monitoring ]; then
		exit_with_message "Failed enable monitoring"
	fi
	if [ ! -f d3xx-linux-x86_64-0.5.21.tar.zip ]; then
		$FETCHER https://cdn.molecubes.com/install/d3xx-linux-x86_64-0.5.21.tar.zip -O d3xx-linux-x86_64-0.5.21.tar.zip
		unzip d3xx-linux-x86_64-0.5.21.tar.zip
		tar jxvf d3xx-linux-x86_64-0.5.21.tar.bz2
		mv linux-x86_64 libftdi3xx
		sudo cp libftdi3xx/51-ftd3xx.rules /etc/udev/rules.d/
		sudo udevadm control --reload-rules
		sudo udevadm trigger
	fi
	echo_success
}

function setup_spectacq_network_drives() {
	echo_step "  Setting up network drives"
	sudo mkdir -p /export/data || true
	sudo mkdir -p /export/conf || true
	sudo chmod 777 /export || true
	sudo chmod 777 /export/data || true
	sudo chmod 777 /export/conf || true
	if ! grep -q "192.168.0.0/24" /etc/exports; then
		sudo cp /etc/exports /etc/exports.old
		ID=$(id molecubes | sed "s/^uid=\([0-9]*\)(.*$/\1/")
		echo -e "
/export\t\t10.0.0.0/24(rw,fsid=0,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) 192.168.0.0/24(rw,fsid=0,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
/export/data\t10.0.0.0/24(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) 192.168.0.0/24(rw,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
" | sudo tee -a /etc/exports > /dev/null
	fi
	if [ "$VIRTUAL" = true ]; then
		GUI_IP_ADDRESS="auto-test-gui.in.molecubes.com"
		REMI_IP_ADDRESS="auto-test-remi.in.molecubes.com"
		SPECTRECON_IP_ADDRESS="auto-test-ycuberecon.in.molecubes.com"
		if ! grep -q "${GUI_IP_ADDRESS}" /etc/exports; then
			ID=$(id molecubes | sed "s/^uid=\([0-9]*\)(.*$/\1/")
			echo -e "
/export\t\t${SPECTRECON_IP_ADDRESS}(rw,fsid=0,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) ${GUI_IP_ADDRESS}(rw,fsid=0,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) ${REMI_IP_ADDRESS}(rw,fsid=0,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
/export/data\t${SPECTRECON_IP_ADDRESS}(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) ${GUI_IP_ADDRESS}(rw,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) ${REMI_IP_ADDRESS}(rw,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
" | sudo tee -a /etc/exports > /dev/null
		fi
	fi
	if ! grep -q "home/molecubes/data" /etc/fstab; then
		echo -e "/home/molecubes/data\t/export/data\tnone\tbind\t0\t0" | sudo tee -a /etc/fstab > /dev/null
		echo -e "/home/molecubes/conf\t/export/conf\tnone\tbind\t0\t0" | sudo tee -a /etc/fstab > /dev/null
		sudo mount -a
	fi
	sudo service nfs-kernel-server restart
	if [ -d "/export/data" ]; then
		echo_success
	else
		echo -e "Failed to create /export/data" >> "$FRESH_INSTALL_LOG"
		echo_failure
	fi
}

function setup_spectrecon_network_drives() {
	SPECTACQ_MOUNT_IP_ADDRESS="10.0.0.1"
	CTRECON_MOUNT_IP_ADDRESS="192.168.0.170"
	if [ "$VIRTUAL" = true ]; then
		SPECTACQ_MOUNT_IP_ADDRESS="auto-test-ycubeacq.in.molecubes.com"
		CTRECON_MOUNT_IP_ADDRESS="auto-test-xcubeacqrecon.in.molecubes.com"
	fi

	echo_step "  Setting up network drives"
	sudo mkdir -p /export/dataRECON || true
	sudo chmod 777 /export/dataRECON || true
	sudo mkdir -p /export/calib || true
	sudo chmod 777 /export/calib || true
	if ! grep -q "192.168.0.0/24" /etc/exports; then
		ID=$(id molecubes | sed "s/^uid=\([0-9]*\)(.*$/\1/")
		echo -e "
/export\t\t10.0.0.0/24(rw,fsid=0,insecure,no_subtree_check,async,sec=sys) 192.168.0.0/24(rw,fsid=0,insecure,no_subtree_check,async,sec=sys)
/export/dataRECON\t192.168.0.0/24(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
/export/calib\t192.168.0.0/24(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
" | sudo tee -a /etc/exports > /dev/null
	fi
	if [ "$VIRTUAL" = true ]; then
		GUI_IP_ADDRESS="auto-test-gui.in.molecubes.com"
		REMI_IP_ADDRESS="auto-test-remi.in.molecubes.com"
		if ! grep -q "${GUI_IP_ADDRESS}" /etc/exports; then
			ID=$(id molecubes | sed "s/^uid=\([0-9]*\)(.*$/\1/")
			echo -e "
/export\t\t${GUI_IP_ADDRESS}(rw,fsid=0,insecure,no_subtree_check,async,sec=sys) ${REMI_IP_ADDRESS}(rw,fsid=0,insecure,no_subtree_check,async,sec=sys)
/export/dataRECON\t${GUI_IP_ADDRESS}(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID) ${REMI_IP_ADDRESS}(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
/export/calib\t${REMI_IP_ADDRESS}(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
" | sudo tee -a /etc/exports > /dev/null
		fi
	fi
	if ! grep -q "xcube" /etc/auto.nfs; then
		echo -e "/mnt\t/etc/auto.nfs" | sudo tee -a /etc/auto.master > /dev/null
		echo -e "data\t-fstype=nfs4\t${SPECTACQ_MOUNT_IP_ADDRESS}:/data" | sudo tee -a /etc/auto.nfs > /dev/null
		echo -e "xcube\t-fstype=nfs4\t${CTRECON_MOUNT_IP_ADDRESS}:/data" | sudo tee -a /etc/auto.nfs > /dev/null
		sudo service autofs restart
	fi
	if ! grep -q "home/molecubes/data" /etc/fstab; then
		echo -e "/home/molecubes/data\t/export/dataRECON\tnone\tbind\t0\t0" | sudo tee -a /etc/fstab > /dev/null
		sudo mount -a
	fi
	if ! grep -q "home/molecubes/calib" /etc/fstab; then
		echo -e "/home/molecubes/calib\t/export/calib\tnone\tbind\t0\t0" | sudo tee -a /etc/fstab > /dev/null
		sudo mount -a
	fi
	sudo service nfs-kernel-server restart
	if [ -d "/export/dataRECON" ] && [ -d "/export/calib" ]; then
		echo_success
	else
		echo -e "Failed to create /export/dataRECON" >> "$FRESH_INSTALL_LOG"
		echo_failure
	fi
}

function create_spectacq_files() {
	sudo hostnamectl set-hostname ycubeacq$(echo $SERIAL | sed -e "s/\([C,P,S]\)[0-9][0-9]\([0-9][0-9]\)[0-9][0-9]/\1\2/")
	echo -e "[global]
type = SPECT
version = 1
deviceSerialNumber = $SERIAL
port = 5000
logfile = acquisitionserver.log
logpath = /home/molecubes/
outputPath = /home/molecubes/data
patch = 0" | sudo tee /home/molecubes/acquisitionserver.ini > /dev/null

DEFAULT_IP_ADDRESS="192.168.0.150"
if [ "$VIRTUAL" = true ]; then
	DEFAULT_IP_ADDRESS="auto-test-ycubeacq.in.molecubes.com"
fi
DEFAULT_RECON_IP_ADDRESS="10.0.0.2"
DEFAULT_RECON_PORT="5001"
if [ "$VIRTUAL" = true ]; then
	DEFAULT_RECON_IP_ADDRESS="auto-test-ycuberecon.in.molecubes.com"
	DEFAULT_RECON_PORT="5001"
fi

echo -e "
[network]
publicIPAddress = ${DEFAULT_IP_ADDRESS}
reconDeamonIPAddress=${DEFAULT_RECON_IP_ADDRESS}
reconDeamonPort=${DEFAULT_RECON_PORT}" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null

echo -e "
[spect]
collimatorVersion = 1
safeHomeAngle = 9.0
collimatorChangeAngle = 28.5
disableDecayCorrection = true
qc_monthly_DetUnifMapPath = /home/molecubes/data/UnifMap_100x100x7.bin_%E
qc_monthly_SourcePositionCorrectionMapPath = /home/molecubes/data/SourcePosCorrection_100x100x7.bin_%E
qc_monthly_peakdeviation = 0.1
qc_monthly_peakfwhm = 0.15
qc_monthly_stdevdeviation = 0.05
qc_monthly_max_age = 30" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null
if [ "$VIRTUAL" = true ]; then
	echo -e "systemType = virtual" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null
fi

echo -e "
[monitoring]
serialPort = /dev/monitoring
baudRate = 115200
Vref = 2.42
buffersize = 20
samplingRate = 666
maxPWM_basic_mouse = 80
maxPWM_monitoring_mouse = 100
maxPWM_basic_rat = 130
maxPWM_monitoring_rat = 150
maxPWM_basic_ratXL = 130
maxPWM_monitoring_ratXL = 150
maxPWM_basic_custom = 0
maxPWM_monitoring_custom = 0
maxPWM_basic_unknown = 0
maxPWM_monitoring_unknown = 0
maxPWM_basic_ratXL_hotel = 72
maxPWM_monitoring_ratXL_hotel = 72
maxPWM_basic_rat_hotel = 72
maxPWM_monitoring_rat_hotel = 72
mouse4hotel_uids = 
mouse3hotel_uids = " | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null
if [ "$VIRTUAL" = true ]; then
	echo -e "type = virtual" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null
fi

MOTORTYPE="CM10-1A"
if [ "$VIRTUAL" = true ]; then
	MOTORTYPE="virtual"
fi

echo -e "
[gantry]
serialPort = /dev/gantrymotor
motorType = ${MOTORTYPE}
homeVelocity = 6
startVelocity = 6
runVelocity = 12
accelerationTime = 0.1
decelerationTime = 0.1
distancePerRevolution = 90
motorResolution = 1000
gearA = 10
gearB = 1
hometyp = 8" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null

echo -e "
[bed]
serialPort = /dev/bedmotor
motorType = ${MOTORTYPE}
homeVelocity = 10
startVelocity = 10
runVelocity = 10
accelerationTime = 0.1
decelerationTime = 0.1
distancePerRevolution = 2.5
motorResolution = 1000
gearA = 1
gearB = 1
nrPositions_mouse = 10
nrPositions_rat = 12
nrPositions_QCphantom = 10
nrPositions_default = 10
startPosition_mouse = 112.52
length_mouse = 200
startPosition_rat = 121.92
length_rat = 250
startPostion_QCphantom = 112.52
length_QCphantom = 200
startPosition_default = 121.92
length_default = 200
maximum_position = 321.73
hometyp = 0" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null

echo -e "
[progressleds]
serialPort = /dev/progressleds
baudRate = 9600" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null
if [ "$VIRTUAL" = true ]; then
	echo -e "type = virtual" | sudo tee -a /home/molecubes/acquisitionserver.ini > /dev/null
fi

	sudo chown molecubes:molecubes /home/molecubes/acquisitionserver.ini

	echo -e "acquisitionserver.so
$PACKAGEVERSION
FDKJFMQ" | sudo tee /home/molecubes/acquisitionserver.mmf > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/acquisitionserver.mmf

	sudo touch /home/molecubes/acquisitionserver.so

	echo -e "[GENERAL]
serial=$SERIAL
version=0x12
config_folder=/home/molecubes/conf
main_lookup=0
int_time=1000
temp=23
calib=/home/molecubes/conf/Calib


[STATE]
state=0
info=System OK

[MAINS]
nr_mains=1
nr_det_per_main=9
main_0=MCMainSPECT
main_1=
main_2=
main_3=
main_4=

[IO]
nr_blocks=4
#block_size=41943040
block_size=335544320

[STAGE]
bdrate=9600
timeout=5

[POSITIONING]
algorithm=SPECTLM_MNN
modality=SPECT
nr_layers=1
nr_doi_layers=1
nr_det=9
nr_main=1
nr_channels=16
energy_res=0.20
pos_dimy=100
pos_dimx=100
pos_area=50
det_dimx=100
det_dimy=100
pos_mask=/home/molecubes/Workspace/conf/calibration/position_probmap
calib_iter=1" | sudo tee /home/molecubes/conf/Systems/system.ini > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/conf/Systems/system.ini

	echo -e "0.0
0.0
0.0
1.0
0.0
0.0
0.0
1.0
0.0
0.0
0.0
1.0" | sudo tee /home/molecubes/data/gpmouse_registration.matrix > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/gpmouse_registration.matrix

	echo -e "0.0
0.0
0.0
1.0
0.0
0.0
0.0
1.0
0.0
0.0
0.0
1.0" | sudo tee /home/molecubes/data/gprat_registration.matrix > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/gprat_registration.matrix

	echo -e "0.0
0.0
0.0
1.0
0.0
0.0
0.0
1.0
0.0
0.0
0.0
1.0" | sudo tee /home/molecubes/data/hiemouse_registration.matrix > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/hiemouse_registration.matrix

		echo -e "0.0
0.0
0.0
1.0
0.0
0.0
0.0
1.0
0.0
0.0
0.0
1.0" | sudo tee /home/molecubes/data/hiesensmouse_registration.matrix > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/hiesensmouse_registration.matrix

	echo -e "0.0
0.0
0.0
1.0
0.0
0.0
0.0
1.0
0.0
0.0
0.0
1.0" | sudo tee /home/molecubes/data/hierat_registration.matrix > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/hierat_registration.matrix

	echo_step "  Downloading conf files"
	$FETCHER https://molecubes.ams3.digitaloceanspaces.com/install/SPECT/SPECTdefault.zip -O SPECTdefault.zip
	unzip SPECTdefault.zip
	cd SPECTdefault
	sudo -u molecubes cp -r conf/* /home/molecubes/conf/
	echo_success

	if [ ! -f /home/molecubes/AcqSPECT.sh ]; then
		echo_step "  Downloading AcqSPECT.sh"
		sudo -u molecubes $FETCHER https://molecubes.ams3.digitaloceanspaces.com/install/SPECT/AcqSPECT.sh -O /home/molecubes/AcqSPECT.sh
		if [ ! -f /home/molecubes/AcqSPECT.sh  ]; then
			echo -e "Failed to download AcqSPECT" >> "$FRESH_INSTALL_LOG" && echo_failure
		else
			echo_success
		fi
	fi

	sudo chown -R molecubes:molecubes /home/molecubes/*
}

function create_spectrecon_files() {
	sudo hostnamectl set-hostname ycuberecon$(echo $SERIAL | sed -e "s/\([C,P,S]\)[0-9][0-9]\([0-9][0-9]\)[0-9][0-9]/\1\2/")

	DEFAULT_IP_ADDRESS="192.168.0.150"
	if [ "$VIRTUAL" = true ]; then
		DEFAULT_IP_ADDRESS="auto-test-ycuberecon.in.molecubes.com"
	fi
	DEFAULT_CT_IP_ADDRESS="192.168.0.170"
	if [ "$VIRTUAL" = true ]; then
		DEFAULT_CT_IP_ADDRESS="auto-test-xcubeacqrecon.in.molecubes.com"
	fi
	DEFAULT_SPECT_ACQ_IP_ADDRESS_LOCAL="10.0.0.1"
	DEFAULT_SPECT_RECON_IP_ADDRESS_LOCAL="10.0.0.2"
	if [ "$VIRTUAL" = true ]; then
		DEFAULT_SPECT_ACQ_IP_ADDRESS_LOCAL="auto-test-ycubeacq.in.molecubes.com"
		DEFAULT_SPECT_RECON_IP_ADDRESS_LOCAL=${DEFAULT_IP_ADDRESS}
	fi

	echo -e "[global]
type = SPECT
version = 1
port = 5001
logfile = reconstructionserver.log
logpath = /home/molecubes/
outputPath = /home/molecubes/data
deviceSerialNumber = $SERIAL

[internal]
localEthIPAddress = ${DEFAULT_SPECT_RECON_IP_ADDRESS_LOCAL}
localIPAddress = ${DEFAULT_IP_ADDRESS}
receiveDatasetPort = 6767
acquisitionServerIP = 10.0.0.2
acquisitionServerEthIP = ${DEFAULT_SPECT_ACQ_IP_ADDRESS_LOCAL}

[dicom]
institutionName = Molecubes
institutionAddress = Infinity
institutionDepartmentName = Lab
deviceSerialNumber = $SERIAL
serveraddress = 192.168.2.1
serverport = 8042
username = molecubes
password = molecubes

[registration]
matrixPath = /home/molecubes/data/registration.matrix

[SPECT]
debugOutputFiles = true

[CT]
remoteIPaddress = ${DEFAULT_CT_IP_ADDRESS}
reconstructionServerPort = 5001
datapath = /mnt/xcube

[output]
histogramRescale=1
filenameFormat = %d_%m_%g_%r_iter%i" | sudo tee /home/molecubes/reconstructionserver.ini > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/reconstructionserver.ini

	echo -e "reconstructionserver.so
$PACKAGEVERSION
2394032" | sudo tee /home/molecubes/reconstructionserver.mmf > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/reconstructionserver.mmf

	sudo touch /home/molecubes/reconstructionserver.so

	echo -e "[GENERAL]
serial=$SERIAL
version=0x12
config_folder=/home/molecubes/conf
main_lookup=0
int_time=1000
temp=23
calib=/home/molecubes/conf/Calib


[STATE]
state=0
info=System OK

[MAINS]
nr_mains=1
nr_det_per_main=9
main_0=MCMainSPECT
main_1=
main_2=
main_3=
main_4=

[IO]
nr_blocks=4
#block_size=41943040
block_size=335544320

[STAGE]
bdrate=9600
timeout=5

[POSITIONING]
algorithm=SPECTLM_MNN
modality=SPECT
nr_layers=1
nr_doi_layers=1
nr_det=9
nr_main=1
nr_channels=16
energy_res=0.20
pos_dimy=100
pos_dimx=100
pos_area=50
det_dimx=100
det_dimy=100
pos_mask=/home/molecubes/Workspace/conf/calibration/position_probmap
calib_iter=1" | sudo tee /home/molecubes/conf/Systems/system.ini > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/conf/Systems/system.ini

	sudo touch /home/molecubes/data/PostProcessing.py
	sudo sudo chown molecubes:molecubes /home/molecubes/data/PostProcessing.py
	sudo chmod 755 /home/molecubes/data/PostProcessing.py

	echo "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\" ?>
<!DOCTYPE boost_serialization>
<boost_serialization signature=\"serialization::archive\" version=\"11\">
<params class_id=\"0\" tracking_level=\"0\" version=\"0\">
	<_params class_id=\"1\" tracking_level=\"0\" version=\"0\">
		<count>35</count>
		<item_version>0</item_version>
		<item class_id=\"2\" tracking_level=\"0\" version=\"0\">
			<first>Geometry/matrix_voxels_x</first>
			<second>141</second>
		</item>
		<item>
			<first>Geometry/matrix_voxels_y</first>
			<second>141</second>
		</item>
		<item>
			<first>Geometry/matrix_voxels_z</first>
			<second>81</second>
		</item>
		<item>
			<first>Geometry/numDetectors</first>
			<second>7</second>
		</item>
        <item>
            <first>Geometry/recon_voxels_x</first>
            <second>141</second>
        </item>
        <item>
            <first>Geometry/recon_voxels_y</first>
            <second>141</second>
        </item>
        <item>
            <first>Geometry/recon_voxels_z</first>
            <second>81</second>
        </item>
        <item>
            <first>Geometry/voxelsize</first>
            <second>0.250</second>
        </item>
		<item>
			<first>Geometry/pixels_x</first>
			<second>100</second>
		</item>
		<item>
			<first>Geometry/pixels_y</first>
			<second>100</second>
		</item>
        <item>
			<first>Geometry/rotation_axis_x</first>
			<second>0</second>
		</item>
		<item>
			<first>Geometry/rotation_axis_y</first>
			<second>0</second>
		</item>
		<item>
			<first>Geometry/pixelsize</first>
			<second>0.5</second>
		</item>
                <item>
                        <first>Geometry/axial_offset</first>
                        <second>0.0</second>
                </item>
        <item>
            <first>Reconstruction/iterations</first>
            <second>200</second>
        </item>
		<item>
			<first>Reconstruction/FOVradius</first>
			<second>18</second>
		</item>
		<item>
			<first>Reconstruction/cudaDevice</first>
			<second>0</second>
		</item>
		<item>
			<first>Reconstruction/mask_border</first>
			<second>2</second>
		</item>
        <item>
			<first>Reconstruction/systemmatrices</first>
			<second>2</second>
		</item>
		<item><first>Reconstruction/matrix_energies</first><second>140</second></item>
		<item>
			<first>Reconstruction/valid_axial_range</first>
			<second>1000</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSC_columns</first>
			<second>Ptrs_%i.csc_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSC_rows</first>
			<second>Rows_%i.csc_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSC_values</first>
			<second>Values_%i.csc_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSR_columns</first>
			<second>Columns_%i.csr_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSR_rows</first>
			<second>Ptrs_%i.csr_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSR_values</first>
			<second>Values_%i.csr_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_base_path</first>
			<second>/home/molecubes/calib/20201217_GPMouse_250um/</second>
		</item>
        <item>
            <first>Reconstruction/uniformity_path</first>
            <second>/home/molecubes/calib/20201217_GPMouse_250um/UnifMap_100x100x7.bin_%i</second>
        </item>
        <item>
            <first>Reconstruction/projection_weight</first>
            <second>/home/molecubes/calib/20201217_GPMouse_250um/CollMapSegmented_100x100x7_eroded.bin_%i</second>
        </item>
        <item>
            <first>Reconstruction/output_filename</first>
            <second>recon_i%03i.img</second>
        </item>
    <item>
        <first>Reconstruction/gpmouse_gaussianFWHM</first>
        <second>0</second>
    </item>
    <item>
        <first>Reconstruction/gprat_gaussianFWHM</first>
        <second>0</second>
    </item>
    <item>
        <first>Reconstruction/gpmouse_bedDiameter</first>
        <second>33</second>
    </item>
    <item>
        <first>Reconstruction/gprat_bedDiameter</first>
        <second>55</second>
    </item>
	</_params>
	<_sections class_id=\"3\" tracking_level=\"0\" version=\"0\">
		<count>2</count>
		<item_version>0</item_version>
		<item>Reconstruction</item>
		<item>Geometry</item>
	</_sections>
</params>
</boost_serialization>" | sudo tee /home/molecubes/data/gpmouse_calibrationParameters250.xml > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/gpmouse_calibrationParameters250.xml

	echo "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\" ?>
<!DOCTYPE boost_serialization>
<boost_serialization signature=\"serialization::archive\" version=\"11\">
<params class_id=\"0\" tracking_level=\"0\" version=\"0\">
	<_params class_id=\"1\" tracking_level=\"0\" version=\"0\">
		<count>35</count>
		<item_version>0</item_version>
		<item class_id=\"2\" tracking_level=\"0\" version=\"0\">
			<first>Geometry/matrix_voxels_x</first>
			<second>71</second>
		</item>
		<item>
			<first>Geometry/matrix_voxels_y</first>
			<second>71</second>
		</item>
		<item>
			<first>Geometry/matrix_voxels_z</first>
			<second>41</second>
		</item>
		<item>
			<first>Geometry/numDetectors</first>
			<second>7</second>
		</item>
        <item>
            <first>Geometry/recon_voxels_x</first>
            <second>71</second>
        </item>
        <item>
            <first>Geometry/recon_voxels_y</first>
            <second>71</second>
        </item>
        <item>
            <first>Geometry/recon_voxels_z</first>
            <second>41</second>
        </item>
        <item>
            <first>Geometry/voxelsize</first>
            <second>0.5</second>
        </item>
		<item>
			<first>Geometry/pixels_x</first>
			<second>100</second>
		</item>
		<item>
			<first>Geometry/pixels_y</first>
			<second>100</second>
		</item>
        <item>
			<first>Geometry/rotation_axis_x</first>
			<second>0</second>
		</item>
		<item>
			<first>Geometry/rotation_axis_y</first>
			<second>0</second>
		</item>
		<item>
			<first>Geometry/pixelsize</first>
			<second>0.5</second>
		</item>
		<item>
			<first>Geometry/axial_offset</first>
			<second>0.0</second>
		</item>
        <item>
            <first>Reconstruction/iterations</first>
            <second>200</second>
        </item>
		<item>
			<first>Reconstruction/FOVradius</first>
			<second>18</second>
		</item>
		<item>
			<first>Reconstruction/cudaDevice</first>
			<second>0</second>
		</item>
		<item>
			<first>Reconstruction/mask_border</first>
			<second>2</second>
		</item>
        <item>
			<first>Reconstruction/systemmatrices</first>
			<second>1</second>
		</item>
		<item><first>Reconstruction/matrix_energies</first><second>140</second></item>
		<item>
			<first>Reconstruction/valid_axial_range</first>
			<second>100</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSC_columns</first>
			<second>Ptrs_%i.csc_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSC_rows</first>
			<second>Rows_%i.csc_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSC_values</first>
			<second>Values_%i.csc_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSR_columns</first>
			<second>Columns_%i.csr_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSR_rows</first>
			<second>Ptrs_%i.csr_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSR_values</first>
			<second>Values_%i.csr_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_base_path</first>
			<second>/home/molecubes/calib/20201217_GPMouse_500um/</second>
		</item>
        <item>
            <first>Reconstruction/uniformity_path</first>
            <second>/home/molecubes/calib/20201217_GPMouse_500um/UnifMap_100x100x7.bin_%i</second>
        </item>
        <item>
            <first>Reconstruction/projection_weight</first>
            <second>/home/molecubes/calib/20201217_GPMouse_500um/CollMapSegmented_100x100x7_eroded.bin_%i</second>
        </item>
        <item>
            <first>Reconstruction/output_filename</first>
            <second>recon_i%03i.img</second>
        </item>
		<item>
			<first>Reconstruction/gpmouse_gaussianFWHM</first>
			<second>0</second>
		</item>
		<item>
			<first>Reconstruction/gprat_gaussianFWHM</first>
			<second>0</second>
		</item>
		<item>
			<first>Reconstruction/gpmouse_bedDiameter</first>
			<second>33</second>
		</item>
		<item>
			<first>Reconstruction/gprat_bedDiameter</first>
			<second>55</second>
		</item>
	</_params>
	<_sections class_id=\"3\" tracking_level=\"0\" version=\"0\">
		<count>2</count>
		<item_version>0</item_version>
		<item>Reconstruction</item>
		<item>Geometry</item>
	</_sections>
</params>
</boost_serialization>"  | sudo tee /home/molecubes/data/gpmouse_calibrationParameters500.xml > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/gpmouse_calibrationParameters500.xml

	echo "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\" ?>
<!DOCTYPE boost_serialization>
<boost_serialization signature=\"serialization::archive\" version=\"11\">
<params class_id=\"0\" tracking_level=\"0\" version=\"0\">
	<_params class_id=\"1\" tracking_level=\"0\" version=\"0\">
		<count>35</count>
		<item_version>0</item_version>
		<item class_id=\"2\" tracking_level=\"0\" version=\"0\">
			<first>Geometry/matrix_voxels_x</first>
			<second>125</second>
		</item>
		<item>
			<first>Geometry/matrix_voxels_y</first>
			<second>125</second>
		</item>
		<item>
			<first>Geometry/matrix_voxels_z</first>
			<second>61</second>
		</item>
		<item>
			<first>Geometry/numDetectors</first>
			<second>7</second>
		</item>
        <item>
            <first>Geometry/recon_voxels_x</first>
            <second>125</second>
        </item>
        <item>
            <first>Geometry/recon_voxels_y</first>
            <second>125</second>
        </item>
        <item>
            <first>Geometry/recon_voxels_z</first>
            <second>61</second>
        </item>
        <item>
            <first>Geometry/voxelsize</first>
            <second>0.5</second>
        </item>
		<item>
			<first>Geometry/pixels_x</first>
			<second>100</second>
		</item>
		<item>
			<first>Geometry/pixels_y</first>
			<second>100</second>
		</item>
        <item>
			<first>Geometry/rotation_axis_x</first>
			<second>0</second>
		</item>
		<item>
			<first>Geometry/rotation_axis_y</first>
			<second>0</second>
		</item>
		<item>
			<first>Geometry/pixelsize</first>
			<second>0.5</second>
		</item>
                <item>
                        <first>Geometry/axial_offset</first>
                        <second>2.19</second>
                </item>
        <item>
            <first>Reconstruction/iterations</first>
            <second>200</second>
        </item>
		<item>
			<first>Reconstruction/FOVradius</first>
			<second>30</second>
		</item>
		<item>
			<first>Reconstruction/cudaDevice</first>
			<second>0</second>
		</item>
		<item>
			<first>Reconstruction/mask_border</first>
			<second>2</second>
		</item>
        <item>
			<first>Reconstruction/systemmatrices</first>
			<second>1</second>
		</item>
		<item><first>Reconstruction/matrix_energies</first><second>140</second></item>
		<item>
			<first>Reconstruction/valid_axial_range</first>
			<second>1000</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSC_columns</first>
			<second>Ptrs_%i.csc_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSC_rows</first>
			<second>Rows_%i.csc_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSC_values</first>
			<second>Values_%i.csc_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSR_columns</first>
			<second>Columns_%i.csr_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSR_rows</first>
			<second>Ptrs_%i.csr_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSR_values</first>
			<second>Values_%i.csr_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_base_path</first>
			<second>/home/molecubes/calib/20201217_GPRat_500um/</second>
		</item>
        <item>
            <first>Reconstruction/uniformity_path</first>
            <second>/home/molecubes/calib/20201217_GPRat_500um/UnifMap_100x100x7.bin_%i</second>
        </item>
        <item>
            <first>Reconstruction/projection_weight</first>
            <second>/home/molecubes/calib/20201217_GPRat_500um/AllOnes100x100x7__DetBrdr1_10__DetBrdr2_5__Offset1_3__Offset2_0.bin_%i</second>
        </item>
        <item>
            <first>Reconstruction/output_filename</first>
            <second>recon_i%03i.img</second>
        </item>
		<item>
			<first>Reconstruction/gpmouse_gaussianFWHM</first>
			<second>0</second>
		</item>
		<item>
			<first>Reconstruction/gprat_gaussianFWHM</first>
			<second>0</second>
		</item>
		<item>
			<first>Reconstruction/gpmouse_bedDiameter</first>
			<second>33</second>
		</item>
		<item>
			<first>Reconstruction/gprat_bedDiameter</first>
			<second>55</second>
		</item>
	</_params>
	<_sections class_id=\"3\" tracking_level=\"0\" version=\"0\">
		<count>2</count>
		<item_version>0</item_version>
		<item>Reconstruction</item>
		<item>Geometry</item>
	</_sections>
</params>
</boost_serialization>" | sudo tee /home/molecubes/data/gprat_calibrationParameters500.xml > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/gprat_calibrationParameters500.xml

	echo "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\" ?>
<!DOCTYPE boost_serialization>
<boost_serialization signature=\"serialization::archive\" version=\"11\">
<params class_id=\"0\" tracking_level=\"0\" version=\"0\">
	<_params class_id=\"1\" tracking_level=\"0\" version=\"0\">
		<count>35</count>
		<item_version>0</item_version>
		<item class_id=\"2\" tracking_level=\"0\" version=\"0\">
			<first>Geometry/matrix_voxels_x</first>
			<second>125</second>
		</item>
		<item>
			<first>Geometry/matrix_voxels_y</first>
			<second>125</second>
		</item>
		<item>
			<first>Geometry/matrix_voxels_z</first>
			<second>61</second>
		</item>
		<item>
			<first>Geometry/numDetectors</first>
			<second>7</second>
		</item>
        <item>
            <first>Geometry/recon_voxels_x</first>
            <second>125</second>
        </item>
        <item>
            <first>Geometry/recon_voxels_y</first>
            <second>125</second>
        </item>
        <item>
            <first>Geometry/recon_voxels_z</first>
            <second>61</second>
        </item>
        <item>
            <first>Geometry/voxelsize</first>
            <second>0.5</second>
        </item>
		<item>
			<first>Geometry/pixels_x</first>
			<second>100</second>
		</item>
		<item>
			<first>Geometry/pixels_y</first>
			<second>100</second>
		</item>
        <item>
			<first>Geometry/rotation_axis_x</first>
			<second>0</second>
		</item>
		<item>
			<first>Geometry/rotation_axis_y</first>
			<second>0</second>
		</item>
		<item>
			<first>Geometry/pixelsize</first>
			<second>0.5</second>
		</item>
                <item>
                        <first>Geometry/axial_offset</first>
                        <second>2.19</second>
                </item>
        <item>
            <first>Reconstruction/iterations</first>
            <second>200</second>
        </item>
		<item>
			<first>Reconstruction/FOVradius</first>
			<second>30</second>
		</item>
		<item>
			<first>Reconstruction/cudaDevice</first>
			<second>0</second>
		</item>
		<item>
			<first>Reconstruction/mask_border</first>
			<second>2</second>
		</item>
        <item>
			<first>Reconstruction/systemmatrices</first>
			<second>1</second>
		</item>
		<item><first>Reconstruction/matrix_energies</first><second>140</second></item>
		<item>
			<first>Reconstruction/valid_axial_range</first>
			<second>1000</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSC_columns</first>
			<second>Ptrs_%i.csc_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSC_rows</first>
			<second>Rows_%i.csc_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSC_values</first>
			<second>Values_%i.csc_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSR_columns</first>
			<second>Columns_%i.csr_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSR_rows</first>
			<second>Ptrs_%i.csr_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_CSR_values</first>
			<second>Values_%i.csr_%i</second>
		</item>
		<item>
			<first>Reconstruction/systemmatrix_base_path</first>
			<second>/home/molecubes/calib/20201217_GPRat_500um/</second>
		</item>
        <item>
            <first>Reconstruction/uniformity_path</first>
            <second>/home/molecubes/calib/20201217_GPRat_500um/UnifMap_100x100x7.bin_%i</second>
        </item>
        <item>
            <first>Reconstruction/projection_weight</first>
            <second>/home/molecubes/calib/20201217_GPRat_500um/AllOnes100x100x7__DetBrdr1_10__DetBrdr2_5__Offset1_3__Offset2_0.bin_%i</second>
        </item>
        <item>
            <first>Reconstruction/output_filename</first>
            <second>recon_i%03i.img</second>
        </item>
		<item>
			<first>Reconstruction/gpmouse_gaussianFWHM</first>
			<second>0</second>
		</item>
		<item>
			<first>Reconstruction/gprat_gaussianFWHM</first>
			<second>0</second>
		</item>
		<item>
			<first>Reconstruction/gpmouse_bedDiameter</first>
			<second>33</second>
		</item>
		<item>
			<first>Reconstruction/gprat_bedDiameter</first>
			<second>55</second>
		</item>
	</_params>
	<_sections class_id=\"3\" tracking_level=\"0\" version=\"0\">
		<count>2</count>
		<item_version>0</item_version>
		<item>Reconstruction</item>
		<item>Geometry</item>
	</_sections>
</params>
</boost_serialization>"  | sudo tee /home/molecubes/data/gprat_calibrationParameters250.xml > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/data/gprat_calibrationParameters250.xml

	echo_step "  Downloading conf files"
	$FETCHER https://cdn.molecubes.com/install/SPECT/$SERIAL.ZIP -O $SERIAL.ZIP
	unzip $SERIAL.ZIP
	cd $SERIAL
	sudo -u molecubes cp -r conf/* /home/molecubes/conf/
	echo_success

	if [ ! -f /home/molecubes/RecSPECT.sh ]; then
		echo_step "  Downloading RecSPECT.sh"
		sudo -u molecubes $FETCHER https://cdn.molecubes.com/install/SPECT/RecSPECT.sh -O /home/molecubes/RecSPECT.sh
		if [ ! -f /home/molecubes/RecSPECT.sh  ]; then
			echo -e "Failed to download RecSPECT" >> "$FRESH_INSTALL_LOG" && echo_failure
		else
			echo_success
		fi
	fi

	sudo chown -R molecubes:molecubes /home/molecubes/*
}

################################################################################
# REMI install functions
################################################################################

function setup_remi_network_drives() {
	echo_step "  Setting up network drives"
	sudo mkdir -p /export/data || true
	sudo chmod 777 /export || true
	sudo chmod 777 /export/data || true
	if ! grep -q "/etc/auto.nfs" /etc/auto.master; then
		echo -e "/mnt\t/etc/auto.nfs" | sudo tee -a /etc/auto.master > /dev/null
		sudo touch /etc/auto.nfs
		sudo service autofs restart
	fi

	if [ "$VIRTUAL" = true ]; then
		VIRTUAL_PETACQ_IP_ADDRESS="auto-test-bcubeacq.in.molecubes.com"
		VIRTUAL_PETRECON_IP_ADDRESS="auto-test-bcuberecon.in.molecubes.com"
		VIRTUAL_SPECTACQ_IP_ADDRESS="auto-test-ycubeacq.in.molecubes.com"
		VIRTUAL_SPECTRECON_IP_ADDRESS="auto-test-ycuberecon.in.molecubes.com"
		VIRTUAL_CTACQRECON_IP_ADDRESS="auto-test-xcubeacqrecon.in.molecubes.com"
		if ! grep -q "${VIRTUAL_PETACQ_IP_ADDRESS}:/data" /etc/auto.nfs; then
			echo -e "dataP01ACQ\t-fstype=nfs4\t${VIRTUAL_PETACQ_IP_ADDRESS}:/data" | sudo tee -a /etc/auto.nfs > /dev/null
			echo -e "confP01\t-fstype=nfs4\t${VIRTUAL_PETACQ_IP_ADDRESS}:/conf" | sudo tee -a /etc/auto.nfs > /dev/null
		fi
		if ! grep -q "${VIRTUAL_PETRECON_IP_ADDRESS}:/data" /etc/auto.nfs; then
			echo -e "dataP01RECON\t-fstype=nfs4\t${VIRTUAL_PETRECON_IP_ADDRESS}:/data" | sudo tee -a /etc/auto.nfs > /dev/null
		fi
		if ! grep -q "${VIRTUAL_SPECTACQ_IP_ADDRESS}:/data" /etc/auto.nfs; then
			echo -e "dataS01ACQ\t-fstype=nfs4\t${VIRTUAL_SPECTACQ_IP_ADDRESS}:/data" | sudo tee -a /etc/auto.nfs > /dev/null
		fi
		if ! grep -q "${VIRTUAL_SPECTRECON_IP_ADDRESS}:/data" /etc/auto.nfs; then
			echo -e "dataS01RECON\t-fstype=nfs4\t${VIRTUAL_SPECTRECON_IP_ADDRESS}:/data" | sudo tee -a /etc/auto.nfs > /dev/null
			echo -e "calibS01\t-fstype=nfs4\t${VIRTUAL_SPECTRECON_IP_ADDRESS}:/calib" | sudo tee -a /etc/auto.nfs > /dev/null
		fi
		if ! grep -q "${VIRTUAL_CTACQRECON_IP_ADDRESS}:/data" /etc/auto.nfs; then
			echo -e "dataC01\t-fstype=nfs4\t${VIRTUAL_CTACQRECON_IP_ADDRESS}:/data" | sudo tee -a /etc/auto.nfs > /dev/null
		fi
		sudo service autofs restart
	fi
	if ! grep -q "192.168.0.0/24" /etc/exports; then
		sudo cp /etc/exports /etc/exports.old
		ID=$(id molecubes | sed "s/^uid=\([0-9]*\)(.*$/\1/")
		# anonuid and anongid need to point to userid of usser 'molecubes', check /etc/passwd
		echo -e "/export\t192.168.0.0/24(rw,fsid=0,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
/export/data\t192.168.0.0/24(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
" | sudo tee -a /etc/exports > /dev/null
	fi
	if [ "$VIRTUAL" = true ]; then
		sudo cp /etc/exports /etc/exports.old
		GUI_IP_ADDRESS="auto-test-gui.in.molecubes.com"
		if ! grep -q "{GUI_IP_ADDRESS}" /etc/exports; then
			ID=$(id molecubes | sed "s/^uid=\([0-9]*\)(.*$/\1/")
			# anonuid and anongid need to point to userid of usser 'molecubes', check /etc/passwd
			echo -e "/export\t${GUI_IP_ADDRESS}(rw,fsid=0,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
/export/data\t${GUI_IP_ADDRESS}(rw,nohide,insecure,no_subtree_check,async,sec=sys,all_squash,anonuid=$ID,anongid=$ID)
" | sudo tee -a /etc/exports > /dev/null
		fi
	fi
	if ! grep -q "home/molecubes/data" /etc/fstab; then
		echo -e "/home/molecubes/data\t/export/data\tnone\tbind\t0\t0" | sudo tee -a /etc/fstab > /dev/null
		sudo mount -a
	fi
	sudo service nfs-kernel-server restart
	if [ -d "/export/data" ]; then
		echo_success
	else
		echo -e "Failed to create /export/data" >> "$FRESH_INSTALL_LOG"
		echo_failure
	fi
}

function create_remi_files() {
	sudo hostnamectl set-hostname remi$(echo $SERIAL | sed -e "s/\([W,C,P,S]\)[0-9][0-9]\([0-9][0-9]\)[0-9][0-9]/\1\2/")

	DEFAULT_REMI_IP_ADDRESS="192.168.0.245"
	if [ "$VIRTUAL" = true ]; then
		DEFAULT_REMI_IP_ADDRESS="auto-test-remi.in.molecubes.com"
	fi

	echo -e "
[global]
type = WORKSTATION
version = 1
port = 5001
logfile = reconstructionserver.log
logpath = /home/molecubes/
outputPath = /home/molecubes/data
deviceSerialNumber = $SERIAL
#excludeGPU = GPU-3306791b-7660-4ec7-c8ad-365f52f30117
#type = REMI

[configurationchecker]
enabled = true

[internal]
localIPAddress = ${DEFAULT_REMI_IP_ADDRESS}
localEthIPAddress = ${DEFAULT_REMI_IP_ADDRESS}
receiveDatasetPort = 6767
acquisitionServerIP = 10.0.0.2
#acquisitionServerEthIP = 10.0.0.1

[dicom]
institutionName = Molecubes
institutionAddress = Infinity
institutionDepartmentName = lab
deviceSerialNumber = $SERIAL
serveraddress = 192.168.2.1
serverport = 8042
username = molecubes
password = molecubes

[registration]
matrixPath = /home/molecubes/data/registration.matrix

[output]
cutoffROI=1
filenameFormat = %d_%m_%g_%r
histogramRescale=1

[environment]
#acquisitionserver = <SERIAL>:<IP>:<PORT>
#reconstructionserver = <SERIAL>:<IP>:<PORT>" | sudo tee /home/molecubes/reconstructionserver.ini > /dev/null
	sudo chown molecubes:molecubes /home/molecubes/reconstructionserver.ini

	echo -e "[Unit]
Description=gunicorn socket

[Socket]
ListenStream=/run/gunicorn.sock

[Install]
WantedBy=sockets.target" | sudo tee /etc/systemd/system/gunicorn.socket > /dev/null

	echo -e "[Unit]
Description=gunicorn daemon
Requires=gunicorn.socket
After=network.target

[Service]
User=dev
Group=www-data
WorkingDirectory=/home/dev/workstation
ExecStart=/usr/local/bin/gunicorn \\
	--access-logfile - \\
	--workers 3 \\
	--bind unix:/run/gunicorn.sock \\
	workstation.wsgi:application

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/gunicorn.service > /dev/null
	sudo systemctl daemon-reload

echo -e "server {
    listen 80;
    server_name ${DEFAULT_REMI_IP_ADDRESS} 10.8.0.114;

    location = /favicon.ico { access_log off; log_not_found off; }
    location /static/ {
        root /home/dev/workstation/;
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:/run/gunicorn.sock;
    }
}" | sudo tee /etc/nginx/sites-available/workstation  > /dev/null

	sudo ln -s /etc/nginx/sites-available/workstation /etc/nginx/sites-enabled
	sudo nginx -t
	sudo systemctl restart nginx

	sudo touch /home/molecubes/data/PostProcessing.py
	sudo chown molecubes:molecubes /home/molecubes/data/PostProcessing.py
	sudo chmod 755 /home/molecubes/data/PostProcessing.py

	sudo systemctl enable gunicorn
	sudo systemctl enable nginx

	sudo -u postgres psql -c "CREATE DATABASE workstation"
	sudo -u postgres psql -c "CREATE USER molecubes WITH PASSWORD 'Molecubes47'"
	sudo -u postgres psql -c "CREATE USER dev WITH PASSWORD 'devMolecubes47'"
}

################################################################################
# main
################################################################################

set_install_log

current_username=$( id -un )
if [ "$current_username" != "dev" ]; then
  exit_with_failure "Run this script as dev user."
fi

SERIAL=""
VIRTUAL=false
OUTSIDE_DEFINED_PACKAGE=false
while getopts "x:s:v" opt; do
	case $opt in
	s)	SERIAL="$OPTARG"
		;;
	v)  VIRTUAL=true
		echo_warning "Running on a VIRTUAL system!"
		;;
	x)  OUTSIDE_DEFINED_PACKAGE=true
		INSTALLPACKAGE="$OPTARG"
		;;
	*)
		echo "Invalid option: -$OPTARG"
		usage 1
		;;
	esac
done

if [ "$SERIAL" = "" ]; then
	echo "Expected argument <SERIAL>"
	usage 1
elif [[ ! "$SERIAL" =~ ^[CPSW][0-9]{6} ]]; then
	exit_with_failure "Invalid SERIAL provided: $SERIAL"
fi

echo
echo
echo_title "Determining system type"

if [ "$VIRTUAL" = false ]; then
	echo_step "Trying to automatically determine the MOBO type"
	MOBO=$(sudo dmidecode -t 2 | grep "Product Name" | sed -e "s/^.*: \(.*\)$/\1/g")
	if [ "$MOBO" == "Default string" ]; then
			echo_warning
			MOBO=""
			while [ -z $MOBO ]; do
					echo_step "Failed to determine MOBO type. Please specify the MOBO type (1 - KONTRON MOBO, 2 - AIMB MOBO): "
					read CHOICE
					if [ $CHOICE -eq 1 ]; then
							MOBO="D3434-S2"
					elif [ $CHOICE -eq 2 ]; then
						break
					fi
			done
	else
			echo_success
	fi
else
	# some fake ID
	MOBO="D3434-S2"
fi

detect_system_type
detect_architecture
detect_ubuntu_version
if [ "$ARCHITECTURE" != "x86_64" ]; then
	exit_with_failure "Architecture $ARCHITECTURE is unsupported for now."
fi

echo_title "Configuring system"; echo

check_fetcher

if [ "$UBUNTU_VERSION" != "18.04" ]; then
	common_install
else
	common_ubuntu18_install
fi

$FETCHER https://cdn.molecubes.com/install_new_version.sh -O install_new_version.sh
sudo chmod 777 install_new_version.sh

# Make sure install_new_version installs the specific 'PRODUCTIONVERSION', which may not be equal to master or beta!
if [ "$VIRTUAL" = false ]; then
	bash install_new_version.sh -p
else
	if [ "$OUTSIDE_DEFINED_PACKAGE" = true ]; then
		# Order of parameters is important!
		bash install_new_version.sh -v -x ${INSTALLPACKAGE}
	else
		bash install_new_version.sh -v
	fi
fi

# Extra check to ensure all dependencies correct
sudo chown -R molecubes:molecubes /home/molecubes/*
sudo chmod 755 /home/molecubes/libs/*
sudo ldconfig > /dev/null

program_motors

if [ "$DEVICE_MODALITY" = "REMI" ]; then
	sudo chmod 755 /home/dev/
	sudo chmod 775 workstation/
	sudo chown dev:www-data /home/dev/workstation/
	sudo chown -R dev:www-data /home/dev/workstation/webserver
	sudo chown -R dev:www-data /home/dev/workstation/static
	sudo chmod -R 775 /home/dev/workstation/webserver/
	sudo chmod -R 775 /home/dev/workstation/static/

	python3 workstation/manage.py migrate --noinput
	DJANGO_SUPERUSER_USERNAME=molecubes DJANGO_SUPERUSER_PASSWORD=Molecubes47 python3 workstation/manage.py createsuperuser --email admin@admin.com --noinput

	if [ "$VIRTUAL" = false ]; then
		# Change password for default Thinkmate installation, only valid for non-virtual setups
		echo 'user:devMolecubes47' | sudo chpasswd
	fi
fi

echo
echo
exit 0