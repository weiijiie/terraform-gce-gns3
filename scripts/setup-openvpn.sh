#!/bin/bash

# Idempotent startup script to configure the services in the GNS3 server instance

set -o errexit


function log {
  echo "=> $1"  >&2
}

function get_instance_metadata {
  curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/$1"
}

function mount_pd {
  log "Format/mount persistent disk if necessary"

  local pd_file="/dev/disk/by-id/google-gns3-storage"
  local fs
  fs="$(lsblk -no KNAME,FSTYPE "$(readlink -f ${pd_file})")"

  # Disk not formatted yet
  if [[ $(echo "${fs}" | wc -w) -eq 1 ]]; then
    # Format the disk as a ext4 fs
    mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard ${pd_file}

    # Copy current contents of /opt/gns3
    cp -r /opt/gns3/ /tmp/gns3

    # Mount persistent disk and move files back
    mount -o discard,defaults /dev/disk/by-id/google-gns3-storage /opt/gns3
    mv /tmp/gns3/* /opt/gns3

    chown -R gns3:gns3 /opt/gns3
  else 
    # Already formatted, just need to mount
    mount -o discard,defaults /dev/disk/by-id/google-gns3-storage /opt/gns3
  fi
}

function setup_openvpn {
  log "Running openvpn setup"
  log "Current IP address: ${MY_IP_ADDR}"

  log "Update motd"

  cat <<EOF > /etc/update-motd.d/70-openvpn
#!/bin/sh
echo ""
echo "_______________________________________________________________________________________________"
echo "Download the VPN configuration here:"
echo "http://${MY_IP_ADDR}:${OPENVPN_PROFILE_ENDPOINT_PORT}/profile/gns3-server.ovpn"
echo ""
echo "And add it to your openvpn client."
echo ""
echo "apt-get remove nginx-light to disable the HTTP server."
echo "And remove this file with rm /etc/update-motd.d/70-openvpn"
EOF

  chmod 755 /etc/update-motd.d/70-openvpn

  # Creates tun device for OpenVPN if absent
  [[ -d /dev/net ]] || mkdir -p /dev/net
  [[ -c /dev/net/tun ]] || mknod /dev/net/tun c 10 200

  mkdir -p /etc/openvpn/
  
  # Generates the PKI for OpenVPN if absent
  log "Create keys if missing"
  [[ -f ~/.rnd ]] || openssl rand -out ./.rnd -hex 256

  if [[ ! -f /etc/openvpn/ca.crt ]]; then
    openssl req -x509 \
      -nodes \
      -newkey ec:<(openssl ecparam -name secp384r1) \
      -keyout /etc/openvpn/ca.key \
      -out /etc/openvpn/ca.crt \
      -subj /CN=OpenVPN/ \
      -days 24855 \
      && chmod 600 /etc/openvpn/ca.key
  fi

  if [[ ! -f /etc/openvpn/key.pem ]]; then
    openssl ecparam -name secp384r1 -noout -genkey -out /etc/openvpn/key.pem \
      && chmod 600 /etc/openvpn/key.pem
  fi

  if [[ ! -f /etc/openvpn/csr.pem ]]; then 
    openssl req -new -key /etc/openvpn/key.pem -out /etc/openvpn/csr.pem -subj /CN=OpenVPN/
  fi

  if [[ ! -f /etc/openvpn/cert.pem ]]; then
    openssl x509 -req \
      -sha256 \
      -in /etc/openvpn/csr.pem \
      -out /etc/openvpn/cert.pem \
      -CA /etc/openvpn/ca.crt \
      -CAkey /etc/openvpn/ca.key \
      -CAcreateserial \
      -extfile <(printf "keyUsage=digitalSignature,keyEncipherment,keyAgreement\n\
                         extendedKeyUsage=serverAuth,clientAuth") \
      -days 24855
  fi

  # Creates/updates OpenVPN client/server config files
  # Even if the keys are the same, the server's IP address may need to be updated
  log "Create client and server configuration"
  cat <<EOF > /etc/openvpn/client.ovpn
client
remote ${MY_IP_ADDR}
proto udp
port ${OPENVPN_ACCESS_PORT}
dev tun

<key>
$(cat /etc/openvpn/key.pem)
</key>
<cert>
$(cat /etc/openvpn/cert.pem)
</cert>
<ca>
$(cat /etc/openvpn/ca.crt)
</ca>
ecdh-curve secp384r1

tls-client
nobind
EOF

  cat <<EOF > "/etc/openvpn/udp${OPENVPN_ACCESS_PORT}.conf"
server 172.16.253.0 255.255.255.0
proto udp
port ${OPENVPN_ACCESS_PORT}
dev tun${OPENVPN_ACCESS_PORT}

<key>
$(cat /etc/openvpn/key.pem)
</key>
<cert>
$(cat /etc/openvpn/cert.pem)
</cert>
<ca>
$(cat /etc/openvpn/ca.crt)
</ca>
dh none
ecdh-curve secp384r1

tls-server
verify-client-cert require
verb 3
duplicate-cn
keepalive 10 60
persist-key
persist-tun
status openvpn-status-${OPENVPN_ACCESS_PORT}.log
log-append /var/log/openvpn-udp${OPENVPN_ACCESS_PORT}.log
EOF

  log "Restart OpenVPN"

  # Restarts OpenVPN service
  sudo systemctl restart openvpn
  sudo systemctl enable openvpn@udp"${OPENVPN_ACCESS_PORT}"
  sudo systemctl start openvpn@udp"${OPENVPN_ACCESS_PORT}"
}

function setup_nginx {
  log "Running nginx setup"

  # Creates nginx directories and folders if absent
  if [[ ! -f /etc/nginx/sites-available/openvpn ]]; then
    echo "Setup HTTP server for serving client certificate"
    mkdir -p /usr/share/nginx/openvpn/profile
    touch /usr/share/nginx/openvpn/profile/index.html
    touch /usr/share/nginx/openvpn/index.html
  fi

  # Generates basic nginx config file to serve the OpenVPN client profile
  # If auth set to enabled, then also configures HTTP basic authentication
  if [[  "${AUTH_ENABLED}" == "true" ]]; then
    echo -n "${OPENVPN_PROFILE_ENDPOINT_USER}:" >> /etc/nginx/.htpasswd
    openssl passwd -apr1 "${OPENVPN_PROFILE_ENDPOINT_PASS}" >> /etc/nginx/.htpasswd

    cat <<EOF > /etc/nginx/sites-available/openvpn
server {
  listen ${OPENVPN_PROFILE_ENDPOINT_PORT};
    root /usr/share/nginx/openvpn;

    location / {
      auth_basic "Restricted Content";
      auth_basic_user_file /etc/nginx/.htpasswd;
    }
}
EOF

  else
    cat <<EOF > /etc/nginx/sites-available/openvpn
server {
  listen ${OPENVPN_PROFILE_ENDPOINT_PORT};
    root /usr/share/nginx/openvpn;
}
EOF
  fi

  if [[ ! -f /etc/nginx/sites-enabled/openvpn ]]; then
    ln -s /etc/nginx/sites-available/openvpn /etc/nginx/sites-enabled/
  fi

  # Copies the up-to-date OpenVPN client profile
  cp /etc/openvpn/client.ovpn /usr/share/nginx/openvpn/profile/gns3-server.ovpn
  sudo systemctl reload nginx
  log "Download http://${MY_IP_ADDR}:${OPENVPN_PROFILE_ENDPOINT_PORT}/profile/gns3-server.ovpn to setup your OpenVPN client."
}

function setup_gns3 {
  log "Running gns3 setup"

  # Creates/updates the GNS3 server configuration file
  cat <<EOF > /etc/gns3/gns3_server.conf
[Server]
host = ${GNS3_SERVER_IP}
port = ${GNS3_SERVER_PORT}
images_path = /opt/gns3/images
projects_path = /opt/gns3/projects
report_errors = True

[Qemu]
enable_kvm = True
require_kvm = True
EOF

  # Restarts GNS3
  sudo systemctl restart gns3
}

# Set environment from metadata server  
OPENVPN_ACCESS_PORT="$(get_instance_metadata attributes/ovpn_access_port)"
OPENVPN_PROFILE_ENDPOINT_PORT="$(get_instance_metadata attributes/ovpn_profile_endpoint_port)"
MY_IP_ADDR="$(get_instance_metadata network-interfaces/0/access-configs/0/external-ip)"

AUTH_ENABLED="$(get_instance_metadata attributes/ovpn_profile_endpoint_auth_enabled)"
OPENVPN_PROFILE_ENDPOINT_USER="$(get_instance_metadata attributes/ovpn_profile_endpoint_user)"
OPENVPN_PROFILE_ENDPOINT_PASS="$(get_instance_metadata attributes/ovpn_profile_endpoint_pass)"

GNS3_SERVER_IP="$(get_instance_metadata attributes/gns3_server_ip)"
GNS3_SERVER_PORT="$(get_instance_metadata attributes/gns3_server_port)"

# Perform setup
mount_pd
setup_openvpn
setup_nginx
setup_gns3
