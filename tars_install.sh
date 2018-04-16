#!/usr/bin/env sh

work_dir=`pwd`/Tars
tars_app_dir='/usr/local/app/tars'

eth0_ip=`ip addr show | grep inet | awk '{print $2}' | awk -F'/' '{print $1}' | grep -v '127' | grep -v '172'`


read -e -p "Please Input Tars Tegistry IP ?  " -i $eth0_ip your_machine_ip
read -e -p "Drop Old Database And Config (Y/N) ?  " -i 'Y' drop_flag


###@@@ service setting
sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config
systemctl disable firewalld
systemctl stop firewalld


yum -y install wget git

yum -y install epel-release glibc-devel bison flex cmake mariadb-server mariadb-devel gcc gcc-c++

[[ -e mariadb-5.5.56-linux-x86_64.tar.gz ]] || wget -c https://downloads.mariadb.org/interstitial/mariadb-5.5.56/bintar-linux-x86_64/mariadb-5.5.56-linux-x86_64.tar.gz/from/http%3A//ftp.hosteurope.de/mirror/archive.mariadb.org/ -O mariadb-5.5.56-linux-x86_64.tar.gz 


[[ -e /usr/local/mysql ]] || tar zxf mariadb-5.5.56-linux-x86_64.tar.gz -C /usr/local
[[ -e /usr/local/mysql ]] || ln -s /usr/local/mariadb-5.5.56-linux-x86_64 /usr/local/mysql

[[ -e ${work_dir} ]] || git clone https://github.com/tistergit/Tars.git

cd ${work_dir}

cd ${work_dir}/cpp/thirdparty
chmod a+x thirdparty.sh
./thirdparty.sh


cd ${work_dir}/cpp/build/
chmod u+x build.sh
./build.sh all


./build.sh install


##setup mysql
if ! grep -q character-set-server /etc/my.cnf
then
sed -i '/\[mysqld\]/ a \
character-set-server = utf8
' /etc/my.cnf

sed -i '/\[client\]/ a \
default-character-set=utf8
' /etc/my.cnf.d/client.cnf

fi



systemctl enable mariadb
systemctl start mariadb


##
make framework-tar

make tarsstat-tar
make tarsnotify-tar
make tarsproperty-tar
make tarslog-tar
make tarsquerystat-tar
make tarsqueryproperty-tar



###
mkdir -p ${tars_app_dir}
tar xzf framework.tgz -C ${tars_app_dir}


##config
cd ${tars_app_dir}
sed -i "s/192.168.2.131/${your_machine_ip}/g" `grep 192.168.2.131 -rl ./*`
sed -i "s/db.tars.com/${your_machine_ip}/g" `grep db.tars.com -rl ./*`
sed -i "s/registry.tars.com/${your_machine_ip}/g" `grep registry.tars.com -rl ./*`
sed -i "s/web.tars.com/${your_machine_ip}/g" `grep web.tars.com -rl ./*`

mysql -e "grant all on *.* to 'tars'@'%' identified by 'tars2015' with grant option"




#sh ${work_dir}/cpp/framework/sql/exec-sql.sh

##config db
[[ "$drop_flag"="Y" ]] && mysql -uroot -e "DROP DATABASE IF EXISTS db_tars"
mysql -uroot -e "create database db_tars"
mysql -uroot -e "create database tars_stat"
mysql -uroot -e "create database tars_property"

### change db config
cd ${work_dir}/cpp/framework/sql/
sed -i "s/192.168.2.131/${your_machine_ip}/g" `grep 192.168.2.131 -rl ./*`
sed -i "s/db.tars.com/${your_machine_ip}/g" `grep db.tars.com -rl ./*`

mysql -uroot db_tars <  ${work_dir}/cpp/framework/sql/db_tars.sql

### tars core service and tarsnode setup
chmod a+x ${tars_app_dir}/*.sh
sh ${tars_app_dir}/tars_install.sh
sh ${tars_app_dir}/tarspatch/util/init.sh




##build java
cd ${work_dir}/java
mvn  install -s ../build/settings.xml
mvn  install -f core/client.pom.xml -s ../build/settings.xml
mvn  install -f core/server.pom.xml -s ../build/settings.xml


### web
cd ${work_dir}/web
[[ -e resin-4.0.55.tar.gz ]] || wget -c http://caucho.com/download/resin-4.0.55.tar.gz
[[ -e /usr/local/resin ]] || tar zxf resin-4.0.55.tar.gz -C /usr/local
[[ -e /usr/local/resin ]] || ln -s /usr/local/resin-4.0.55 /usr/local/resin

[[ -d /usr/local/app/patchs/tars.upload ]] || mkdir -p /usr/local/app/patchs/tars.upload/




if ! grep -q db.tars.com /etc/hosts 
then
    echo "${your_machine_ip} db.tars.com" >> /etc/hosts
fi

if ! grep -q registry1.tars.com /etc/hosts 
then
    echo "${your_machine_ip} registry1.tars.com" >> /etc/hosts
fi

if ! grep -q registry2.tars.com /etc/hosts 
then
    echo "${your_machine_ip} registry2.tars.com" >> /etc/hosts
fi

[[ -d /data/log/tars ]] || mkdir -p /data/log/tars

##build web
mvn  package -s ../build/settings.xml
cp ./target/tars.war /usr/local/resin/webapps/

##@@ web config
sed -i 's/webapps\/ROOT/webapps\/tars/g' /usr/local/resin/conf/resin.xml
sed -i '/<host-default>/a \
 <character-encoding>UTF-8<\/character-encoding> ' /usr/local/resin/conf/resin.xml

if [[ `netstat -lntp | grep 8080` ]] 
  then
    /usr/local/resin/bin/resin.sh restart
  else 
  	/usr/local/resin/bin/resin.sh start
fi


