#!/bin/bash

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or use sudo"
  exit
fi

# Update and upgrade the system
echo "Updating and upgrading the system..."
apt update && apt upgrade -y

# Install necessary packages for kiosk mode
echo "Installing X11, Openbox, and Chromium..."
apt install --no-install-recommends xorg openbox chromium-browser ufw unattended-upgrades -y

# Create kiosk user and set up environment
KIOSK_USER="kioskuser"
KIOSK_HOME="/home/$KIOSK_USER"

if id "$KIOSK_USER" &>/dev/null; then
  echo "User $KIOSK_USER already exists. Skipping user creation."
else
  echo "Creating user $KIOSK_USER..."
  adduser --disabled-password --gecos "" $KIOSK_USER
  usermod -aG sudo $KIOSK_USER
fi

# Create the kiosk script for launching Chromium in kiosk mode
echo "Creating kiosk script..."
cat << 'EOF' > $KIOSK_HOME/kiosk.sh
#!/bin/bash
xset -dpms      # Disable DPMS (Energy Star) features.
xset s off      # Disable screen saver.
xset s noblank  # Disable screen blanking.
openbox-session &
chromium-browser --no-sandbox --kiosk --disable-infobars --disable-session-crashed-bubble --disable-features=TranslateUI --app=https://myhr.peoplestrong.com
EOF

# Make the kiosk script executable
chmod +x $KIOSK_HOME/kiosk.sh
chown $KIOSK_USER:$KIOSK_USER $KIOSK_HOME/kiosk.sh

# Enable auto-login for kiosk user
echo "Setting up auto-login for kiosk user..."
mkdir -p /etc/systemd/system/getty@tty1.service.d/
cat << EOF > /etc/systemd/system/getty@tty1.service.d/override.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
Type=idle
EOF

# Configure .bash_profile to start X server and kiosk script
echo "Configuring .bash_profile to start X and kiosk script..."
cat << 'EOF' > $KIOSK_HOME/.bash_profile
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    startx /etc/X11/Xsession $HOME/kiosk.sh
fi
EOF

chown $KIOSK_USER:$KIOSK_USER $KIOSK_HOME/.bash_profile

# Disable ICMP (ping) responses to prevent DOS attacks
echo "Disabling ICMP responses..."
echo "net.ipv4.icmp_echo_ignore_all = 1" > /etc/sysctl.d/99-disable-icmp.conf
sysctl -p /etc/sysctl.d/99-disable-icmp.conf

# Disable SSH and other unnecessary services
echo "Disabling unnecessary services..."
systemctl stop ssh
systemctl disable ssh
apt remove --purge openssh-server -y

# Set up UFW (Uncomplicated Firewall) to block all incoming traffic
echo "Configuring UFW to block all incoming traffic..."
ufw default deny incoming
ufw default allow outgoing
ufw enable

# Enable automatic security updates
echo "Enabling automatic security updates..."
dpkg-reconfigure --priority=low unattended-upgrades

# Harden GRUB to prevent console access
echo "Hardening GRUB to disable console switching..."
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash console=tty3"/' /etc/default/grub
update-grub

# Disable USB storage if not needed
echo "Disabling USB storage..."
echo "blacklist usb-storage" > /etc/modprobe.d/usb-storage.conf
update-initramfs -u

echo "Kiosk setup and security hardening complete. Please reboot the system to apply all changes."