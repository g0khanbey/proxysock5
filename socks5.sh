#!/bin/bash
# Create swap space
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Prompt for SOCKS5 proxy credentials
echo "Please enter the username for the socks5 proxy:"
read username
echo "Please enter the password for the socks5 proxy:"
read -s password

# Update repositories
sudo apt update -y

# Install dante-server, Apache, and UFW
sudo apt install dante-server apache2 ufw -y

# Enable Apache proxy modules
sudo a2enmod proxy
sudo a2enmod proxy_http

# Create the Dante configuration file
sudo bash -c 'cat <<EOF > /etc/danted.conf
logoutput: /var/log/danted.log
internal: 0.0.0.0 port = 1080
external: ens160
method: username
user.privileged: root
user.notprivileged: nobody
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
EOF'

# Add user with password
sudo useradd --shell /usr/sbin/nologin $username
echo "$username:$password" | sudo chpasswd

# Check if UFW is active and open port 1080 if needed
if sudo ufw status | grep -q "Status: active"; then
    sudo ufw allow 1080/tcp
    sudo ufw allow 8081/tcp
fi

# Check if iptables is active and open port 1080 and 8081 if needed
if ! sudo iptables -L | grep -q "ACCEPT     tcp  --  anywhere             anywhere             tcp dpt:1080"; then
    sudo iptables -A INPUT -p tcp --dport 1080 -j ACCEPT
fi
if ! sudo iptables -L | grep -q "ACCEPT     tcp  --  anywhere             anywhere             tcp dpt:8081"; then
    sudo iptables -A INPUT -p tcp --dport 8081 -j ACCEPT
fi

# Restart dante-server
sudo systemctl restart danted

# Enable dante-server to start at boot
sudo systemctl enable danted

# Install Apache utils for htpasswd
sudo apt install apache2-utils -y

# Create .htpasswd file for Apache authentication
sudo htpasswd -b -c /etc/apache2/.htpasswd $username $password

# Create Apache configuration for SOCKS5 proxy
sudo bash -c 'cat <<EOF > /etc/apache2/sites-available/socks5-proxy.conf
<VirtualHost *:8081>
    ServerName yourdomain.com

    # Proxy settings
    ProxyRequests On
    ProxyVia On

    <Proxy *>
        AuthType Basic
        AuthName "Restricted Area"
        AuthUserFile /etc/apache2/.htpasswd
        Require valid-user
    </Proxy>

    ProxyPass /socks5 http://localhost:1080/
    ProxyPassReverse /socks5 http://localhost:1080/
</VirtualHost>
EOF'

# Disable default Apache site
sudo a2dissite 000-default.conf

# Enable the new site and restart Apache
sudo a2ensite socks5-proxy.conf

# Test Apache configuration
if apachectl configtest; then
    sudo systemctl stop apache2
    sudo systemctl start apache2
else
    echo "Apache configuration error. Please check the configuration."
fi

# Remove systemd-oomd if installed
if dpkg -l | grep -q systemd-oomd; then
    sudo apt remove systemd-oomd -y
fi
