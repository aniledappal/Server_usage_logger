#!/bin/sh
#  user_tracking.sh
#
#  Created by Anil 01/12/17.
#
STORAGE="/var/log/td-agent/user.log"
[ ! -w "$STORAGE" ] && \
return 0

my_array=( $(last |sed '/^$/d' | awk '{printf "%s\n", $1}' | sort -u -t' ' -k1,1 |egrep -v "reboot|root|wtmp|unknown" | tac ) )
leng=${#my_array[@]}
# use for loop read all nameservers
for (( i=0; i<${leng}; i++ ));
do

_date=`last -1 ${my_array[$i]}|grep \^${my_array[$i]}|awk '{print $4,$5,$6,$7}'`

_interface=`/sbin/route | grep '^default' | grep -o '[^ ]*$'`
_status=`cat /sys/class/net/$_interface/operstate`
if [ $? -eq 0 ]; then
#    echo Interface: $_interface
_mac=`cat /sys/class/net/$_interface/address`
#    echo Mac: $_mac
_ip=`ip -4 addr show $_interface | grep -oP "(?<=inet ).*(?=/)"`
#    echo IP: $_ip
else
_mac=N/A
_ip=N/A
fi

_dd=$(date "+%Z")a

#echo Time Zone: $_dd
_retlease=`cat /etc/*-release |tail -1`
#echo OS Release: $_retlease
_arc=`uname -i`
#echo Architecture: $_arc
_host=`hostname`
#echo Hostname: $_host
_cpu=`cat /proc/cpuinfo | \
awk -v FS=':' '                                       \
/^physical id/ { if(nb_cpu<$2)  { nb_cpu=$2 } }     \
/^cpu cores/   { if(nb_cores<$2){ nb_cores=$2 } }   \
/^processor/   { if(nb_units<$2){ nb_units=$2 } }   \
/^model name/  { model=$2 }                         \
\
END{                                                \
nb_cpu=(nb_cpu+1);                                 \
nb_units=(nb_units+1);                             \
\
print "CPU model:",model;                          \
}' `
#echo $_cpu
_kernel=`uname -r |awk -F"-" '{print $1}'`
#echo Kernal Version: $_kernel


# Send data to storage
printf -- ",DATE,$_date,HOST,$_host,DESTRO,$_retlease,ARCH,$_arc,CPU,$_cpu,KERNEL,$_kernel,TIME,$_dd,USERS,${my_array[$i]},IP,$_ip,MAC,$_mac\n" \
2>/dev/null >> $STORAGE
done
