#!/bin/bash
#
# Designed to handle the "remote" configuration of a MapR cluster
# within a VPC.   This script and the ancillary cluster details
# must be uploaded to the gateway node, and then executed.
#
# Infrastructure Assumptions
#	This script will ONLY work if the instances have NAT'ed access
#	to the internet.
#
# Assumptions
#	Script is launced as the 'image_su' user ... with sudo privileges
#	Cluster configuration in $HOME/mapr-roles.lst	(gateway node is "0")
#	MAPR_PARAM_FILE is in $HOME as well
#	MAPR_CONFIG_SCRIPT is in $HOME as well
#	$HOME/edi.out contains instance description information (private_ip)
#	$HOME/vpc_private_key contains private key for remote execution
#		on the other cluster nodes.
#

# Most of these variables should MATCH what's in launch-se-cluster.sh
# (so as to make the actual shell functions match that logic more closely)
#
MAPR_USER=mapr
ec2user=`id -un`

NODE_NAME_ROOT=node
configFile=$HOME/mapr_roles.lst
licenseFile=/tmp/.MapRLicense.txt	# dest location if copied in from outside
MAPR_PARAM_FILE=mapr_class.parm
MAPR_CONFIG_SCRIPT=configure-mapr-instance.sh
CLUSTER_SSH_KEY=$HOME/.ssh/vpc_private_key
DESC_INSTANCE_OUT=$HOME/edi.out

# Several approaches
#	- External NAT (Hard-code the address or pass in as meta-data)
#	- Use node0 of the cluster as the NAT (after running AWS configure-pat.sh)
# 
#	NAT_IP=10.0.0.106
NAT_IP=`hostname -i`
IGW_IP=`netstat -rn | grep "^0.0.0.0" | awk '{print $2}'`

THIS_HOST=`hostname`

MY_SSH_OPTS="-i $CLUSTER_SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes"


# Nodes that have no public address MUST be configured
# with a route to the NAT server before they can complete
# the launch-mapr-instance.sh script (not to mention executing
# the configure-mapr-instance.sh script later).
# 
# It LOOKS like the nodes only need that access at the
# during initial setup, and not afterwards.  Let's hope.
#
add_NAT_route() {
	echo "Configuring NAT route on all VPC nodes" 

	while read ami_index pub_name priv_name pub_ip priv_ip
	do
		if [ $pub_name != "${pub_name#unknown_}" ] ; then
			if [ $ec2user = "root" ] ; then
				ssh $MY_SSH_OPTS ${ec2user}@${priv_name} \
					-n "/sbin/route add default gw $NAT_IP ; /sbin/route del default gw $IGW_IP "
			else
				ssh $MY_SSH_OPTS ${ec2user}@${priv_name} \
					-n "sudo /sbin/route add default gw $NAT_IP ; sudo /sbin/route del default gw $IGW_IP "
			fi
		fi
	done < edi.out
}

delete_NAT_route() {
	echo "De-configuring NAT route on all VPC nodes" 

	while read ami_index pub_name priv_name pub_ip priv_ip
	do
		if [ $pub_name != "${pub_name#unknown_}" ] ; then
			if [ $ec2user = "root" ] ; then
				ssh $MY_SSH_OPTS ${ec2user}@${priv_name} \
					-n "route add default gw $IGW_IP ; route del default gw $NAT_IP "
			else
				ssh $MY_SSH_OPTS ${ec2user}@${priv_name} \
					-n "sudo route add default gw $IGW_IP ; sudo route del default gw $NAT_IP "
			fi
		fi
	done < edi.out
}


# Within the VPC, we'll wait for the PRIVATE IP's to come on-line
# with the MapR user.  We need to do this before trying to run
# configure-mapr-instance.sh on those nodes.
#
# Remember, the "public" nodes (those that could be seen from
# outside the VPC) have already reached that stage ... so no
# need to test them.
#
wait_for_launch_complete() {
	echo "Waiting for mapr user to become configured on all VPC nodes" 

	PTIME=10
	PWAIT=900		# wait no more than 15 minutes

	nvpchosts=0
	while read ami_index pub_name priv_name pub_ip priv_ip
	do
		if [ $pub_name != "${pub_name#unknown_}" ] ; then
			vpc_hosts="${vpc_hosts:-} $priv_name"
			nvpchosts=$[nvpchosts + 1]
		fi
	done < edi.out

	mapr_user_found=0
	while [ $mapr_user_found -ne $nvpchosts ] ; do
		echo "$mapr_user_found systems found with MAPR_USER; waiting for $nvpchosts"
		sleep $PTIME
		mapr_user_found=0
		for node in $vpc_hosts
		do
			ssh $MY_SSH_OPTS $MAPR_USER@${node} \
				-n "ls ~${MAPR_USER}/${MAPR_LAUNCH_SCRIPT}" 2> /dev/null
			[ $? -ne 0 ] && break
			mapr_user_found=$[mapr_user_found+1]
		done
	done
}


# Simple function to walk through the list of nodes passed in
# in edi.out and call configure-mapr-instance.sh on all of them.
#
configure_private_cluster() {
	while read ami_index pub_name priv_name pub_ip priv_ip
	do
		hn=${priv_name%%.*}
		host_param_file=/tmp/mapr_${hn}.parm
		hpkgs=`grep "^${NODE_NAME_ROOT}${ami_index}:" $configFile | cut -f2 -d:`
		sed "s/^MAPR_PACKAGES=.*$/MAPR_PACKAGES=${hpkgs}/" $MAPR_PARAM_FILE \
			> $host_param_file
	
			# No need to do the work if this is our gateway server;
			# it already has the information it needs.
		[ $priv_name = $THIS_HOST ] && continue
		[ $priv_name = $hn ] && continue

			# For VPC clusters, use the first node as the gateway
			# and indirectly do the same thing we do everywhere else
		scp $MY_SSH_OPTS $MAPR_CONFIG_SCRIPT ${MAPR_USER}@${priv_name}:
		scp $MY_SSH_OPTS $host_param_file ${MAPR_USER}@${priv_name}:mapr.parm
		if [ -f "${licenseFile:-}" ] ; then
  			scp $MY_SSH_OPTS $licenseFile ${MAPR_USER}@${priv_name}:/tmp/.MapRLicense.txt
		fi
	done < $DESC_INSTANCE_OUT

		# Split the operations appart to better handle errors
		# and ensure that the configuration is REASONABLY well
		# aligned.
	while read ami_index pub_name priv_name pub_ip priv_ip
	do
		echo "Time to run $MAPR_CONFIG_SCRIPT"
		if [ $ec2user = "root" ] ; then
			ssh $MY_SSH_OPTS ${ec2user}@${priv_name} \
				-n "~${MAPR_USER}/$MAPR_CONFIG_SCRIPT" &
		else
			ssh $MY_SSH_OPTS ${ec2user}@${priv_name} \
				-n "sudo ~${MAPR_USER}/$MAPR_CONFIG_SCRIPT" &
		fi

	done < $DESC_INSTANCE_OUT
	wait
}


main() {
	add_NAT_route
	wait_for_launch_complete
	configure_private_cluster

		# Clean up so that the privat key is not left around
	rm -f $CLUSTER_SSH_KEY
}


main

