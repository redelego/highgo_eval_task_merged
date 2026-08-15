#!/bin/bash -e

ETCDIR=$(dirname `realpath ${BASH_SOURCE[0]}`)
INSTDIR=${ETCDIR%/etc}

ln -s ${INSTDIR}/bin/proxy_ctl /usr/bin/proxy_ctl

cat > /usr/lib/systemd/system/hgproxy.service << EOF
[Unit]
Description=hgproxy
Requires=network.target local-fs.target
After=network.target local-fs.target

[Service]
Type=forking
User=root
ExecStart=/usr/bin/proxy_ctl start
ExecStop=/usr/bin/proxy_ctl stop
TimeoutSec=60

[Install]
WantedBy=multi-user.target graphical.target
EOF

systemctl enable hgproxy
systemctl daemon-reload