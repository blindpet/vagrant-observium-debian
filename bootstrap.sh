#!/usr/bin/env bash
mysqlpass="passw0rd"
observiumsqluser="observiumsqluser"
observiumsqlpass="observiumsqlpass"
observiumsqldb="observiumsqldatabase"
observiumuilogin="admin"
observiumuipass="admin"

showip=$(ifconfig eth0 | awk -F"[: ]+" '/inet addr:/ {print $4}')

apt-get update

apt-get install -y libapache2-mod-php5 php5-cli php5-mysql vim php5-gd php5-snmp php5-mcrypt php-pear snmp graphviz subversion debconf rrdtool fping imagemagick whois mtr-tiny nmap ipmitool python-mysqldb

#mysql
apt-get install debconf -y
echo "mysql-server-5.5 mysql-server/root_password password $mysqlpass" | debconf-set-selections
echo "mysql-server-5.5 mysql-server/root_password_again password $mysqlpass" | debconf-set-selections
debconf-apt-progress -- apt-get -y install mysql-client mysql-server

if [ ! -f "/opt/observium" ]; then
  mkdir /opt/observium
else
  rm -rf /opt/observium/*
fi

cd /var/tmp
wget http://www.observium.org/observium-community-latest.tar.gz
tar zxvf observium-community-latest.tar.gz
cp -r observium /opt/
mkdir /opt/observium/logs
mkdir /opt/observium-rrd
chown www-data:www-data /opt/observium-rrd
chmod -R 777 /opt/observium-rrd
cp /opt/observium/config.php.default /opt/observium/config.php

# Mysql Stuff
# Create database
mysql -u root -p$mysqlpass -e "CREATE USER $observiumsqluser@localhost IDENTIFIED BY '$observiumsqlpass';"
mysql -u root -p$mysqlpass -e "CREATE DATABASE $observiumsqldb;"
mysql -u root -p$mysqlpass -e "GRANT ALL PRIVILEGES ON $observiumsqldb.* TO $observiumsqluser@localhost IDENTIFIED BY '$observiumsqlpass';"
mysql -u root -p$mysqlpass -e "FLUSH PRIVILEGES;"

#cat config.php.default | sed s/PASSWORD//g | sed s/USERNAME/root/g > config.php
#echo "\$config['rrd_dir']       = \"/opt/observium-rrd\";">>config.php

# Modify config file
sed -i "/\$config\['db_user'\] = 'USERNAME';/c\$config['db_user'] = '$observiumsqluser';" /opt/observium/config.php
sed -i "/\$config\['db_pass'\] = 'PASSWORD';/c\$config['db_pass'] = '$observiumsqlpass';" /opt/observium/config.php
sed -i "/\$config\['db_name'\] = 'observium';/c\$config['db_name'] = '$observiumsqldb';" /opt/observium/config.php
echo "\$config['rrd_dir']       = \"/opt/observium-rrd\";">>/opt/observium/config.php

#create sql schema and admin user
cd /opt/observium
php includes/update/update.php
php adduser.php admin admin 10

# create graphs stuff
mkdir graphs logs
chown www-data:www-data graphs
chmod -R 777 graphs

#Make the rrd folder and give right permissions so graphs can be drawn
mkdir /opt/observium-rrd
chown www-data:www-data /opt/observium-rrd
chmod -R 777 /opt/observium-rrd

#Finish Apache configuration
rm /etc/apache2/sites-available/default
cat > /etc/apache2/sites-available/observium << EOF
<VirtualHost *:80>
  DocumentRoot /opt/observium/html/
  ServerName  observium.domain.com
  CustomLog /var/log/apache2/observium_access_log combined
  ErrorLog /var/log/apache2/observium_error_log
  <Directory "/opt/observium/html/">
    AllowOverride All
    Options FollowSymLinks MultiViews
  </Directory>
</VirtualHost>
EOF
a2enmod rewrite
php5enmod mcrypt
a2dissite default
a2ensite observium
apache2ctl restart
service apache2 restart

# add snmp stuff
echo "mibdirs /opt/observium/mibs">/etc/snmp/snmp.conf

#add cronjobs

crontab -l | { cat; echo "33 */6 * * * /opt/observium/discovery.php -h all >> /dev/null 2>&1"; } | crontab -
crontab -l | { cat; echo "*/5 * * * * /opt/observium/discovery.php -h new >> /dev/null 2>&1"; } | crontab -   
crontab -l | { cat; echo "*/5 * * * * /opt/observium/poller-wrapper.py 2 >> /dev/null 2>&1"; } | crontab -   

echo Observium running on $showip with username and password admin
