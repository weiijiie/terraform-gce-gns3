#!/bin/bash

set -o errexit
set -x


function log {
  echo "=> $1"  >&2
}

export DEBIAN_FRONTEND="noninteractive"
UBUNTU_CODENAME="$(lsb_release -c -s)"

cat <<EOF  >> /etc/apt/sources.list
###### Ubuntu Main Repos
deb http://archive.ubuntu.com/ubuntu/ ${UBUNTU_CODENAME} main universe multiverse 
deb-src http://archive.ubuntu.com/ubuntu/ ${UBUNTU_CODENAME} main universe multiverse 
###### Ubuntu Update Repos
deb http://archive.ubuntu.com/ubuntu/ ${UBUNTU_CODENAME}-security main universe multiverse 
deb http://archive.ubuntu.com/ubuntu/ ${UBUNTU_CODENAME}-updates main universe multiverse 
deb-src http://archive.ubuntu.com/ubuntu/ ${UBUNTU_CODENAME}-security main universe multiverse 
deb-src http://archive.ubuntu.com/ubuntu/ ${UBUNTU_CODENAME}-updates main universe multiverse 
EOF

add-apt-repository ppa:gns3/ppa
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys A2E3EF7B

log "Update system packages"
apt-get update

log "Upgrade packages"
apt-get upgrade --yes \
    --allow-downgrades \
    --allow-remove-essential \
    --allow-change-held-packages \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"

log "Install GNS3 dependencies"
apt-get install -y \
    vpcs \
    ubridge \
    qemu-system-x86 \
    qemu-kvm \
    qemu-utils \
    cpulimit \
    libvirt-bin \
    libc6 \
    libexpat1 \
    zlib1g \
    dynamips \
    x11vnc \
    xvfb

log " Install GNS3 Server"
apt-get install -y python3-setuptools python3-dev gcc
wget -qO - "https://github.com/GNS3/gns3-server/archive/${GNS3_VERSION}.tar.gz" | tar -xz
cd "gns3-server-${GNS3_VERSION/v/}"
python3 setup.py install

log "Create user GNS3 with /opt/gns3 as home directory"
useradd -d /opt/gns3/ -m gns3

log "Add GNS3 to the ubridge group"
usermod -aG ubridge gns3

log "Install docker"
curl -sSL https://get.docker.com | bash

log "Add GNS3 to the docker group"
usermod -aG docker gns3

log "IOU setup" 
dpkg --add-architecture i386
apt-get update

apt-get install -y gns3-iou

# Force hostid for IOU
dd if=/dev/zero bs=4 count=1 of=/etc/hostid

# Block iou call. The server is down
echo "127.0.0.254 xml.cisco.com" | tee --append /etc/hosts

log "Add gns3 to the kvm group"
usermod -aG kvm gns3

log "Setup GNS3 server"

mkdir -p /etc/gns3
cat <<EOF > /etc/gns3/gns3_server.conf
[Server]
host = 0.0.0.0
port = 3080 
images_path = /opt/gns3/images
projects_path = /opt/gns3/projects
appliances_path = /opt/gns3/appliances
configs_path = /opt/gns3/configs
report_errors = True

[Qemu]
enable_kvm = True
require_kvm = True
EOF

chown -R gns3:gns3 /etc/gns3
chmod -R 700 /etc/gns3

# Install systemd service
cp init/gns3.service.systemd /lib/systemd/system/gns3.service

chmod 644 /lib/systemd/system/gns3.service
chown root:root /lib/systemd/system/gns3.service

log "Enable GNS3 service"
systemctl enable gns3

log "GNS3 installed and enabled"

log "Installing openvpn and nginx-light"
sudo apt-get install -y openvpn nginx-light unzip
