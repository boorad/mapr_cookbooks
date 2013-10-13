#!/bin/bash
#
#  Script to open ports in a given EC2 security group to allow
#  access to the MapR services from outside the AWS environment
#	For port details, check out 
#		http://www.mapr.com/doc/display/MapR/Ports+Used+by+MapR 
#
# Assumptions:
#	ec2-run-instances tool is in the path
#	EC2 env variables set for target AWS account
#		EC2_HOME, EC2_CERT, and EC2_PRIVATE_KEY
#
# Script 
#

THIS_SCRIPT=$0

usage() {
  echo "
  Usage:
    $THIS_SCRIPT <sg_name_or_id>  [ --region <AMZ_REGION> [ <other AWS opts>] ] 
   "
  echo ""
  echo "EXAMPLES"
  echo "  $0 sg-24a7eb4e --region us-west-1" 
  echo "  $0 MySecGroup  --region us-east-1" 
}

if [ $# -lt 1 ] ; then
	usage
	exit 1
fi


# Try to be smart: "sg-<foo>" indicates group id; anything else is a name
secgroup=$1
shift       # save the res of the args
if [ ${secgroup#sg-} == $secgroup ] ; then
		# Grab description of running instances
	sgdesc=/tmp/sgroup_$$.desc
	ec2-describe-group "${@}" --filter="group-name=$secgroup" > $sgdesc 2>/dev/null
	if [ $? -ne 0 ] ; then
		echo "Error: Could not locate security group '$secgroup'"
		exit 1
	fi

	sg=`grep ^GROUP $sgdesc | awk '{print $2}'`
	rm -f $sgdesc
	if [ -z "${sg}" ] ; then
		echo "Error: Could not locate security group '$secgroup'"
		exit 1
	else
		secgroup=$sg
	fi
fi


echo "Current status of Security Group $secgroup"
ec2-describe-group $secgroup "$@"

echo ""
# For interactive shells, we'll ask to proceed 
if [ -t 0  -o  -S /dev/stdin ] ; then
	echo "Proceed {y/N} ? "
	read YoN
	if [ -z "${YoN:-}"  -o  -n "${YoN%[yY]*}" ] ; then
 		exit 1
	fi
fi

# Assemble our TCP port list
tcpPortList="22"
udpPortList=""

# Web Services and Ajaxterm/JobTracker ports
	tcpPortList="$tcpPortList 8080 8443"
	tcpPortList="$tcpPortList 7221"
	tcpPortList="$tcpPortList 9001 50030 50060"

# NFS ports
	tcpPortList="$tcpPortList 111 2049"
	udpPortList="$udpPortList 111"

if [ -n "$udpPortList" ] ; then 
	for port in $udpPortList
	do
		ec2-authorize $secgroup "$@" -P udp -p $port -s 0.0.0.0/0
	done
fi

for port in $tcpPortList
do
	ec2-authorize $secgroup "$@" -P tcp -p $port -s 0.0.0.0/0
done

# Lastly, allow 80 and 443 egress (otherwise you may not be able
# to talk http:// out to get useful stuff)
for port in 80 443
do
	ec2-authorize $secgroup "$@" --egress -P tcp -p $port -s 0.0.0.0/0
done

echo ""
echo "Final status of Security Group"
ec2-describe-group $secgroup "$@"

