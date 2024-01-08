#!/bin/bash

set -e
#set -euo pipefail

#This password is SET if it's an Initial Password.
#Or used as a test if a root password is already set.
DBROOTPW="secret"
DBACCESS="-uroot -p$DBROOTPW"

echo "Testing Mariadb access and carrying out 'mysql_secure_installation' alternative."

if [[ ${EUID} -ne 0 ]]; then
  printf "Must be run as root. Try 'sudo %s'\n", "$0"
  exit 1
fi

echo "Testing for MariaDB installation..."
if [[ $(which mariadbd) ]]; then
    echo "    SUCCESS: Mariadbd is found."
else
    echo "    FAIL: Mariadbd is not found."
    exit 1
fi

echo "Testing for a running MariaDB installation..."
if [[ $(pgrep mariadbd) ]]; then
    echo "    SUCCESS: Mariadbd is running"
else
    echo "    FAIL: Mariadbd is not running."
    exit 1
fi

function get_mysqlopts() {
  local MYSQLDOPTS1
  MYSQLDOPTS1=$(systemctl show-environment | grep "MYSQLD_OPTS" || echo "" )
  local MYSQLDOPTSX=${MYSQLDOPTS1#*=}
  echo "$MYSQLDOPTSX"
}
KEEPMYSQLDOPTS="$(get_mysqlopts)" 
printf "MYSQLD_OPTS is initially set to: <%s>\n" "$KEEPMYSQLDOPTS"

#EG: mariadb -sNe "SELECT COUNT(PLUGIN_STATUS) FROM information_schema.plugins WHERE PLUGIN_NAME='unix_socket' AND PLUGIN_STATUS='ACTIVE';"
echo "Testing for a MariaDB installation with UNIX Socket Authorisation..."
if [[ $(mariadb -sNe "SELECT COUNT(PLUGIN_STATUS) FROM information_schema.plugins WHERE PLUGIN_NAME='unix_socket' AND PLUGIN_STATUS='ACTIVE';" 2>/dev/null ) == 1  ]]; then
    #PLUGIN_STATUS='ACTIVE' returned with count of 1, and we're not using User and Password, therefore it must Enabled
    echo "    SUCCESS: Mariadbd is running with Unix Socket Auth"
    UNIXAUTH="ON"
else
    #We have been denied access, therefore Unix Socket Auth must be disabled.
    echo "    NOTICE: Mariadbd is not running with Unix Socket Auth."
    UNIXAUTH="OFF"
fi

if [[  $UNIXAUTH == "OFF" ]]; then
  echo "Processing with UNIX AUTH off..."
  echo "    Setting MYSQLD_OPTS to --no-defaults"
  systemctl set-environment MYSQLD_OPTS="--no-defaults"
  systemctl restart mariadb
  echo "    Mariadb has been restarted with: <$(get_mysqlopts)>"
  RET=$(mariadb -e "FLUSH PRIVILEGES;" 2>/dev/null || echo "Failure" ) 
  echo "    Mariadb has been sent FLUSH PRIVILEGES"
  if [[ "$RET" == "Failure" ]]; then
    echo "SYSTEM ERROR: Mariadb didn't restart with Unix Socket Auth turned on. Cannot continue."
    exit 1
  fi
  echo "    Checking root's password..."
  RET=$(mariadb -sNe "SELECT LENGTH(Password) from mysql.user WHERE User='root' AND Host='localhost';" 2>/dev/null )
  printf "    Does the root password have a length of '41'?: %s\n" "$RET"
  if [[ "$RET" == "41" ]]; then
    echo "    YES: Length is 41. Therefore a root password has already been set."
  else
    RET=$(mariadb -sNe "SELECT Password FROM mysql.user WHERE User='root' AND Host='localhost';")
    printf "    Is root password shown as 'invalid'?: %s" "<$RET>"
    if [[ "$RET" == 'invalid' ]]; then
        echo "YES: Since it is 'invalid', then no root password as been set previously. IE a new installation."
        mariadb  -e "SET PASSWORD = PASSWORD('$DBROOTPW');"
        RET=$(mariadb -sNe "SELECT Password FROM mysql.user WHERE User='root' AND Host='localhost';")
        printf "    Is root password STILL shown as 'invalid'?: %s\n" "<$RET>"
        RET=$(mariadb  -sNe "SELECT LENGTH(Password) from mysql.user where User='root' AND Host='localhost';" 2>/dev/null )
        printf "    Does the root password have a length of '41'?: %s\n" "$RET"
        if [[ "$RET" == "41" ]]; then
          echo "    YES: Therefore a root password has been set correctly."
        fi
    fi    
  fi

  echo "    Restoring MYSQLD_OPTS <$KEEPMYSQLDOPTS>"
  systemctl set-environment MYSQLD_OPTS="$KEEPMYSQLDOPTS"
  systemctl restart mariadb
  echo "    Mariadb restarted as it was previously"

  echo "    Checking that pasword works with UNIX AUTH off..."
  RET="$(mariadb $DBACCESS -sNe "SELECT COUNT(User) FROM mysql.user WHERE User='root' AND Host='localhost';" 2>/dev/null || echo 0 )"
  if [[ "$RET" == "1" ]]; then
    echo "    SUCCESS: The password is correct."
  else
    echo "    FAIL: The new password did not work. Cannot continue."
    exit 1
  fi
  CONTINUING="NOUNIXAUTH"
  DBACCESS="-uroot -p$DBROOTPW"
fi

if [[  $UNIXAUTH == "ON" ]]; then
  RET=$(mariadb  -sNe "SELECT LENGTH(Password) from mysql.user where User='root' AND Host='localhost';")
  printf "    Does the root password have a length of '41'?: %s\n" "<$RET>"
  if [[ "$RET" == "41" ]]; then
    echo "    YES: Length is 41. Therefore a root password has already been set."
  else
    echo "    NO: Therefore we set consider setting a password for root."
    RET=$(mariadb -sNe "SELECT Password FROM mysql.user WHERE User='root' AND Host='localhost';")
    printf "    Is root password shown as 'invalid'?: %s\n" "<$RET>"
    if [[ "$RET" == 'invalid' ]]; then
        echo "    Must be new installation, so set a password..."
        mariadb  -e "SET PASSWORD = PASSWORD('$DBROOTPW');"        
        RET=$(mariadb -sNe "SELECT Password FROM mysql.user WHERE User='root' AND Host='localhost';")
        printf "    Is root password STILL shown as 'invalid'?: %s\n" "<$RET>"
        RET=$(mariadb  -sNe "SELECT LENGTH(Password) from mysql.user where User='root' AND Host='localhost';")
        printf "    Does the root password have a length of '41'?: %s\n" "<$RET>"
        if [[ "$RET" == "41" ]]; then
          echo "    YES: Therefore a root password has been set correctly."
        fi
    fi
  fi
  CONTINUING="NORMAL"
  DBACCESS=""
fi

echo "Continuing testing ..."

echo "    Removing anonymous users..."
if RET=$(mariadb   $DBACCESS   -sNe "SELECT COUNT(User) from mysql.user WHERE User='';"); then
  echo "         <$RET> Anonymous Users found"
  if [[ "$RET" != "0" ]]; then
    if RET=$(mariadb  $DBACCESS   -sNe "DELETE FROM mysql.global_priv WHERE User='';"); then
      echo "         Command run successfully!"
    else
      echo "         Command Failed! Not critical, keep moving..."
    fi
  fi
fi

echo "    Removing remote root accounts..."
if RET=$(mariadb $DBACCESS -sNe "SELECT COUNT(User) from mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"); then
  echo "         <$RET> Remote Root accounts found"
  if [[ "$RET" != "0" ]]; then
    if RET=$(mariadb $DBACCESS -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"); then
      echo "         Command run successfully!"
    else
      echo "         Command Failed! Not critical, keep moving..."
    fi
  fi
fi  

echo "    Removing test database..."
if RET=$(mariadb $DBACCESS  -sNe "SHOW DATABASES LIKE 'test';"); then
  if [[ "$RET" == "test" ]]; then
    echo "         <$RET> Database found found"
    if RET=$(mariadb $DBACCESS -sNe "DROP DATABASE IF EXISTS test;"); then
      echo "         Command run successfully!"
    else
      echo "         Command Failed! Not critical, keep moving..."
    fi
    else
      echo "         Test database not found."  
  fi
fi  

echo "    Removing privileges on test database, if existed..."
if RET=$(mariadb $DBACCESS -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%'"); then
  echo "         Command run successfully!"
else
  echo "         Command Failed! Not critical, keep moving..."
fi

echo "Flushing Privileges..."
mariadb $DBACCESS -e "FLUSH PRIVILEGES;"
echo "Restoring MYSQLD_OPTS... <$KEEPMYSQLDOPTS>"
systemctl set-environment MYSQLD_OPTS="$KEEPMYSQLDOPTS"
#systemctl unset-environment MYSQLD_OPTS
sleep 5
systemctl restart mariadb
echo "Testing Complete."
exit 0
