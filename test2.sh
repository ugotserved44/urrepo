#!/bin/bash

# This script
# - creates a user (named below)
# - sets up a union (aufs) filesystem on top of the users immutable home
# - creates a cleanup script (/usr/local/bin/cleanup.sh) that empties the aufs
#   layer on login/logout/boot
# - replaces the lightdm config
# - replaces rc.local to run the script
#
# After running the script, the aufs is not mounted, yet. So you can log in
# as the user and set everything up as you like. Only after a reboot the aufs
# is mounted and the user home becomes immutable.
#
# If you ever need to change anything, log in as a different (admin) user
# and unmount the aufs before you log in again as the kiosk user.

# The username to protect
USERNAME="kiosk"

# Define the URL to load in the kiosk mode
KIOSK_URL="https://myhr.peoplestrong.com"  # <- Your desired URL here

# Disable hardlink restrictions
echo "kernel.yama.protected_nonaccess_hardlinks=0" | sudo tee /etc/sysctl.d/60-hardlink-restrictions-disabled.conf
sudo sysctl -p /etc/sysctl.d/60-hardlink-restrictions-disabled.conf

# Install whois which is needed for mkpasswd, and Chromium for the kiosk browser
sudo dnf install -y whois chromium

# Set up the user
sudo useradd -m $USERNAME   # create user with home directory
sudo usermod -aG wheel,adm,dialout,cdrom,plugdev,fuse $USERNAME # adds user to groups
echo "$USERNAME:$(mkpasswd '')" | sudo chpasswd -e             # sets empty password
sudo passwd -n 100000 $USERNAME                                # prevents user from changing password

# Create directory to store aufs data in
sudo install -d -o $USERNAME -g $USERNAME /home/.${USERNAME}_rw
# Set up the mount
echo "none /home/${USERNAME} aufs br:/home/.${USERNAME}_rw:/home/${USERNAME} 0 0" | sudo tee -a /etc/fstab

# Create LightDM settings to run our cleanup script, disable guests and enable manual
# login (for uids < 1000). Just change the admin's uid to 999 to make him disappear in LightDM.
sudo tee /etc/lightdm/lightdm.conf > /dev/null <<-EOFA
	[Seat:*]
	user-session=openbox
	greeter-session=lightdm-gtk-greeter
	allow-guest=false
	greeter-show-manual-login=true
	greeter-setup-script=/usr/local/bin/cleanup.sh login
	session-cleanup-script=/usr/local/bin/cleanup.sh logout
EOFA

# Change rc.local to run cleanup script
sudo tee /etc/rc.d/rc.local > /dev/null <<-EOFB
	#!/bin/sh -e
	/usr/local/bin/cleanup.sh \$0
	exit 0
EOFB

# Make rc.local executable
sudo chmod +x /etc/rc.d/rc.local

# Cleanup script to clear aufs filesystem
sudo tee /usr/local/bin/cleanup.sh > /dev/null <<-'EOFC'
	#!/bin/sh
	# Only run when aufs is mounted
	test -n `mount -l -t aufs` || exit 0;
	# Delete function to clear out aufs with exceptions
	delete (){
	  # Find arguments to exclude aufs objects
	  no_aufs="! -name '.wh*'"
	  # Extra find arguments
	  more="$1"
	  # Securely delete
	  cd /home/.kiosk_rw && find . -maxdepth 1 -mindepth 1 $no_aufs $more -print0 | xargs -0 rm -rf
	}
	case "$1" in
	  login)
	    test $LOGNAME = "kiosk" && delete "! -name .pulse"
	    ;;
	  logout)
	    # Delete with delay
	    test $LOGNAME = "kiosk" && (sleep 3; delete "! -name .pulse") &
	    ;;
	  /etc/rc.d/rc.local)
	    delete
	    ;;
	  *)
	    ;;
	esac
	exit 0
EOFC

# Set correct username in cleanup.sh
sudo sed -i "s/kiosk/$USERNAME/g" /usr/local/bin/cleanup.sh
sudo chmod 754 /usr/local/bin/cleanup.sh

# Add commands to start Chromium in kiosk mode to .bash_profile of kiosk user
sudo tee /home/$USERNAME/.bash_profile > /dev/null <<-EOF
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
    startx /usr/bin/chromium-browser --kiosk --no-first-run --disable-restore-session-state --disable-session-crashed-bubble $KIOSK_URL
fi
EOF

sudo chown $USERNAME:$USERNAME /home/$USERNAME/.bash_profile
sudo chmod 644 /home/$USERNAME/.bash_profile