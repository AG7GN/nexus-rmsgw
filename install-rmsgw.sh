#!/usr/bin/env bash

VERSION="2.0.4"

# This script installs the prerequisites as well as the libax25, ax25-tools,
# apps and the rmsgw software.  It also installs Hamlib and Direwolf.
#

function AptError () {
   echo
   echo
   echo
   echo >&2 "ERROR while running '$1'."
   echo
   echo >&2 "This is likely problem with a repository somewhere on the Internet.  Run this script again to retry."
   echo
   echo
   exit 1
}


function CheckDepInstalled() {
	# Checks the installation status of a list of packages. Installs them if they are not
	# installed.
	# Takes 1 argument: a string containing the apps to check with apps separated by space
	#MISSING=$(dpkg --get-selections $1 2>&1 | grep -v 'install$' | awk '{ print $6 }')
	#MISSING=$(dpkg-query -W -f='${Package} ${Status}\n' $1 2>&1 | grep 'not-installed$' | awk '{ print $1 }')
	MISSING=""
   for P in $1
   do
      if apt-cache policy $P | grep -q "Installed: (none)"
      then
         MISSING+="$P "
      fi
   done
	if [[ ! -z $MISSING ]]
	then
		sudo apt-get -y install $MISSING || AptError "$MISSING"
	fi
}


function InstalledPkgVersion() {

	# Checks if a deb package is installed and returns version if it is
	# arg1: Name of package
	# Returns version of installed package or empty string if package is
	# not installed
	
	INSTALLED_="$(dpkg -l "$1" 2>/dev/null | grep "$1" | tr -s ' ')"
	[[ $INSTALLED_ =~ ^ii ]] && echo "$INSTALLED_" | cut -d ' ' -f3 || echo ""
}


function DebPkgVersion() {
	# Checks the version of a .deb package file.
	# Returns version of the .deb package or empty string if .deb file can't be read
	# arg1: path to .deb file
	VERSION_="$(dpkg-deb -I "$1" 2>/dev/null | grep "^ Version:" | tr -d ' ' | cut -d: -f2)"
	[[ -z $VERSION_ ]] && echo "" || echo "$VERSION_"

}

declare -r TRUE=0
declare -r FALSE=1
cd $SRC_DIR/nexus-rmsgw

#sudo apt-get update || aptError "sudo apt-get update"
CheckDepInstalled "build-essential autoconf libtool git gcc g++ make cmake psmisc net-tools zlib1g zlib1g-dev libncurses5-dev libncursesw5-dev xutils-dev libxml2 libxml2-dev python-requests mariadb-client libmariadbclient-dev texinfo libasound2-dev libudev-dev unzip gpsd libgps-dev yad iptables-persistent"

for F in *.deb
do
	INSTALLED_VERSION="$(InstalledPkgVersion ${F%%_*})"
	REPO_VERSION="$(DebPkgVersion $F)"
	if [[ $INSTALLED_VERSION == $REPO_VERSION && ! -z $REPO_VERSION ]]
	then
		echo >&2 "${F%%_*} already installed and up to date"
	else
		echo "Prevent the standard ${F%%_*} package from overwriting our version"
		sudo apt-mark hold ${F%%_*}
		echo "Install $F"
		sudo dpkg --force-overwrite --install $F
		[[ $? == 0 ]] || { echo >&2 "FAILED.  Aborting installation."; exit 1; }
		echo "Done."
	fi
done

#echo "Prevent the standard ax25-apps package from overwriting our version"
#sudo apt-mark hold ax25-apps
#echo "Install ax25-apps"
#sudo dpkg --install ax25-apps_2.0.1-1_armhf.deb
#[[ $? == 0 ]] || { echo >&2 "FAILED.  Aborting installation."; exit 1; }
#echo "Done."

#echo "Prevent the standard ax25-tools package from overwriting our version"
#sudo apt-mark hold ax25-tools
#echo "Install ax25-tools"
#sudo dpkg --install ax25-tools_1.0.5-1_armhf.deb
#[[ $? == 0 ]] || { echo >&2 "FAILED.  Aborting installation."; exit 1; }
#echo "Done."

echo "Add rmsgw user"
sudo useradd -c 'Linux RMS Gateway' -d /etc/rmsgw -s /bin/false rmsgw
echo "Done."

#echo "Prevent the standard hamlib package from overwriting our version"
#sudo apt-get -y remove libhamlib2
#sudo apt-mark hold libhamlib2 libhamlib-dev
#echo "Install hamlib"
#sudo dpkg --install hamlib_4.0-1_armhf.deb
#[[ $? == 0 ]] || { echo >&2 "FAILED.  Aborting installation."; exit 1; }
#echo "Set up symlink for apps that still need access to hamlib via libhamlib.so.2"
#for F in libhamlib libhamlib++
#do
#   if ! [ -L /usr/lib/${F}.so.2 ]
#   then # There's no symlink.  Make one.
#      [ -f /usr/lib/${F}.so.2 ] && sudo mv /usr/lib/${F}.so.2 /usr/lib/${F}.so.2.old
#      sudo ln -s /usr/local/lib/${F}.so.4.0.0 /usr/lib/${F}.so.2
#   fi
#done
sudo ldconfig
#echo "Done."

echo "Install/update Direwolf"
if ! command -v direwolf >/dev/null 2>&1
then
	/usr/local/sbin/nexus-updater.sh direwolf
else # direwolf already installed
   echo "direwolf already installed"
fi

echo "Install/update pat"
if ! command -v pat >/dev/null 2>&1
then # Install pat
	/usr/local/sbin/nexus-updater.sh pat
else # pat already installed
   echo "pat already installed"
fi

echo "Install/update patmail.sh"
wget -q -O patmail.sh https://raw.githubusercontent.com/AG7GN/nexus-utilities/master/patmail.sh
[[ $? == 0 ]] || { echo >&2 "FAILED.  Could not download patmail.sh."; exit 1; }
chmod +x patmail.sh
sudo mv patmail.sh /usr/local/bin/
echo "Done."

echo "Retrieve the latest rmsgw software"
sudo mkdir -p /etc/rmsgw
[ -d /usr/local/etc/rmsgw ] && sudo rm -rf /usr/local/etc/rmsgw
sudo ln -s /etc/rmsgw /usr/local/etc/rmsgw
URL="https://github.com/nwdigitalradio/rmsgw"
DIR_="$SRC_DIR/nexus-rmsgw/rmsgw"
UP_TO_DATE=$FALSE
if ! [[ -s $DIR_/.git/HEAD ]]
then
	git clone $URL || { echo >&2 "======= git clone $URL failed ========"; exit 1; }
else  # See if local repo is up to date
	cd $DIR_
	if git pull | tee /dev/stderr | grep -q "^Already"
	then
		echo "============= $REQUEST up to date ============="
		UP_TO_DATE=$TRUE
	fi
fi
if [[ $UP_TO_DATE == $FALSE ]]
then
	echo "Install rmsgw"
	cd $DIR_
	./autogen.sh
	./configure
	make && sudo make install
	[[ $? == 0 ]] || { echo >&2 "FAILED.  Aborting installation."; exit 1; }
	sudo chown -R rmsgw:rmsgw /etc/rmsgw/*
fi

cd $SRC_DIR/nexus-rmsgw
echo "Get the pitnc_setparams and pitnc_getparams software"
wget -q -O pitnc9K6params.zip http://www.tnc-x.com/pitnc9K6params.zip
if [[ $? == 0 ]]
then 
   unzip -o pitnc9K6params.zip
   chmod +x pitnc_*
   sudo cp -f pitnc_* /usr/local/bin/
   echo "Done."
else
   echo >&2 "WARNING: Could not download pitnc software."
fi

echo "Install/update nexus-iptables"
/usr/local/sbin/nexus-updater.sh nexus-iptables
echo "Done."

sudo rm -f /usr/local/share/applications/configure-rmsgw.desktop
sudo rm -f /usr/local/share/applications/rmsgw_monitor.desktop

echo "Make 'RMS Gateway Manager' menu item for the 'Ham Radio' menu"
cat > /tmp/rmsgw_config_monitor.desktop << EOF
[Desktop Entry]
Name=RMS Gateway Manager
GenericName=RMS Gateway Manager
Comment=RMS Gateway Manager
Exec=bash -c /usr/local/bin/rmsgw_manager.sh
Icon=/usr/share/raspberrypi-artwork/raspitr.png
Terminal=false
Type=Application
Categories=HamRadio;
Comment[en_US]=RMS Gateway Manager
EOF
sudo mv -f /tmp/rmsgw_config_monitor.desktop /usr/local/share/applications/

echo "Done."

echo "Installing scripts, firewall rules and logrotate files."
sudo cp -f $SRC_DIR/nexus-rmsgw/usr/local/bin/rmschanstat.local /usr/local/bin/
sudo cp -f $SRC_DIR/nexus-rmsgw/usr/local/bin/rmsgw_manager.sh /usr/local/bin/
sudo cp -f $SRC_DIR/nexus-rmsgw/etc/ax25/ax25-* /etc/ax25/
sudo cp -f $SRC_DIR/nexus-rmsgw/etc/logrotate.d/* /etc/logrotate.d/
sudo cp -f $SRC_DIR/nexus-rmsgw/etc/rsyslog.d/* /etc/rsyslog.d/
sudo systemctl restart rsyslog
sudo cp -f $SRC_DIR/nexus-rmsgw/rmsgw-activity.sh /usr/local/bin/
echo "Done."

echo
echo
echo "Installation complete."
echo
echo "Select 'Configure RMS Gateway' from the Ham Radio Raspberry"
echo "Pi menu to configure and activate the RMS Gateway."
echo
echo "Select 'RMS Gateway Monitor' to monitor the relevant log files"
echo "and to start/stop the RMS Gateway service (ax25.service)."
echo
exit 0

