# Mariadb Initialization
Experiments with initializing a Mariadb when Unix Socket Authentication is off

After an initial installation of Mariadb (ie apt install mariadb-server) there is no initial root password.\

If Unix Socket Authorisation was OFF and this time, there is no way to access the database unless mariadb is\
restarted with the Unix Socket Authorisation ON, as there is no existing root password.

Use /etc/my.cnf to turn Unix Socket Authorisation on or off.

Use test-reset.sh when you're testing the initial installation of mariadb\
-NOTE it deletes /var/lib/mysql

$ sudo ./test-reset.sh
$ sudo ./test-mariadb.sh

A password must be set within ./test-mariadb.sh

Jan 2024
