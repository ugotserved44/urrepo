useradd -m kiosk
passwd -d kiosk
 
yum -y install gnome-kiosk-script-session
 
cat > /etc/gdm/custom.conf << EOF
# GDM configuration storage
 
[daemon]
# Uncomment the line below to force the login screen to use Xorg
#WaylandEnable=false
AutomaticLoginEnable=True
AutomaticLogin=kiosk
 
[security]
 
[xdmcp]
 
[chooser]
 
[debug]
# Uncomment the line below to turn on debugging
#Enable=true
EOF
 
mkdir -p /home/kiosk/.local/bin /home/kiosk/.config
cat > /home/kiosk/.local/bin/gnome-kiosk-script << EOF
#!/bin/sh
firefox -kiosk https://myhr.peoplestrong.com/
sleep 1.0
exec "$0" "$@"
EOF
 
chmod +x /home/kiosk/.local/bin/gnome-kiosk-script
 
cat > /var/lib/AccountsService/users/kiosk << EOF
[User]
Session=gnome-kiosk-script
SystemAccount=false
EOF