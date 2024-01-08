#!/bin/bash

apt -y purge mariadb-server
apt -y autoremove
rm -rf /var/lib/mysql
apt -y install mariadb-server
systemctl set-environment MYSQLD_OPTS=""
exit 0
