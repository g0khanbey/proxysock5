#!/bin/bash

# Swap alanı oluşturma
echo "4 GB Swap alanı oluşturuluyor..."
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab

# Swap ayarları tamamlandı
echo "Swap alanı başarıyla oluşturuldu ve etkinleştirildi."

# Proxy için kullanıcı bilgilerini alma
echo -e "Lütfen socks5 proxy için bir kullanıcı adı girin:"
read username
echo -e "Lütfen socks5 proxy için bir şifre girin:"
read -s password

# Repositories güncelleme
sudo apt update -y

# Dante-server kurulumu
sudo apt install dante-server -y

# Konfigürasyon dosyasını oluşturma
sudo bash -c 'cat <<EOF > /etc/danted.conf
logoutput: /var/log/danted.log
internal: 0.0.0.0 port = 1080
external: ens160
method: username none
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

# Proxy için kullanıcı ve şifre oluşturma
sudo useradd --shell /usr/sbin/nologin $username
echo "$username:$password" | sudo chpasswd

# UFW kontrolü ve port açma
if sudo ufw status | grep -q "Status: active"; then
    sudo ufw allow 1080/tcp
    echo "UFW aktif, 1080 portu açıldı."
else
    echo "UFW devre dışı, port açılmadı."
fi

# iptables kontrolü ve port açma
if sudo iptables -L | grep -q "ACCEPT     tcp  --  anywhere             anywhere             tcp dpt:1080"; then
    echo "Port 1080 iptables'ta zaten açık."
else
    sudo iptables -A INPUT -p tcp --dport 1080 -j ACCEPT
    echo "iptables'ta 1080 portu açıldı."
fi

# Dante-server'ı yeniden başlatma
sudo systemctl restart danted

# Dante-server'ın başlatılmasını etkinleştirme
sudo systemctl enable danted

# systemd-oomd'yi kaldırma
sudo apt remove systemd-oomd -y

echo "Dante SOCKS5 Proxy kurulumu tamamlandı ve swap alanı başarıyla eklendi."
