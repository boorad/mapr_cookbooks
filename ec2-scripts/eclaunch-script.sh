#
# Simple script to launch an EC2 instance passing in a script
# to be run as the node spins up.
#
#	LIMITATIONS: the shell script can be no more than 16K in size !!!
#
# This script is used to test our "launch-mapr-instance.sh" script with
# different AMI's.
#
# In the AMI's listed below, only those with "cloud-init" features 
# will support running the script as the instance is launched.
#

# Known x86_64 AMI's for us-east-1
#   ami-cc5af9a5    RedHat 6.3  ebs (login ec2-user)
#   ami-f95cf390    CentOS 6.3 (cloud-init) ebs (login root) 0 ext drives
#   ami-f1be3998    CentOS 6.3 (minimal)  ebs (login ec2-user) 1 ext drive
#	ami-888815e1	CentOS 6.3 ebs	(login ec2-user)	2 ext drives
#   ami-3d4ff254    Ubuntu 12.04 (cloud guest) ebs		1 ext drive

# Known x86_64 AMI's for us-west-1
#	ami-51c3e614
#	ami-2862436d	CentOS 6.3 (minimal) ebs (login ec2-user)
#	ami-89ddf3cc
#	ami-89ddf3cc	Ubuntu 12.04 from MapR training (no disks)
#
# Known x86_64 AMI's for us-west-2
#   ami-8a25a9ba    RedHat 6.3  ebs  (NOT cloud-init)
#   ami-123ab122    RedHat 6.3  ebs  (NOT cloud-init)
#	ami-3a79f30a	CentOS 6.3  ebs   (NOT cloud-init)
#   ami-ccaf20fc    CentOS 6.3 (cloud-init)  ebs
#   ami-72ce4642    CentOS 6.3 (minimal)  ebs
#   ami-800d86b0    CentOS 6.3 instance-store boot (client login is root)
#   ami-aa06939a    CentOS 6.4 (for instance types requiring HVM)
#   ami-8e109ebe    Ubuntu 12.04 (cloud guest) ebs
#   ami-4ac9437a    Ubuntu 12.04 (works with m3 and m2 instance types)
#   ami-f0109ec0    Ubuntu 12.04 (for instance types requiring HVM)
#	ami-feb931ce 	Ubuntu 12.04 with Java already installed 
#						(DANGER ... /mnt in use by agentcontroller.sh, so it
#						 cannot be unmountef for use by MFS)
#
#	ami-6d29b85d 	VPC-NAT AMI ... specific support for NAT within VPC
#
# Known x86_64 AMI's for eu-west-1
#	ami-a93133dd	CentOS 6.3 {minimal} (su login: ec2-user)
#   ami-e1e8d395    Ubuntu 12.04 (cloud guest) ebs
#


THIS_SCRIPT=$0

MAPR_LAUNCH_SCRIPT=launch-mapr-instance.sh

machinetype=m1.large
region=eu-west-1
ec2keypair=tucker-se
# ec2keypair=students07172012			# training@maprtech.com AWS account

# group=${group:-"sg-61031a0d"}			# Default VPC for AWSENG, if we need it

usage() {
  echo "
  Usage:
    $THIS_SCRIPT
       --region <ec2-region>
       --image <AMI name>
       --instance-type <instance-type>
       --key-name <ec2-key>
       [ --group ec2-security-group ]
   "
  echo ""
  echo "EXAMPLES"
  echo "  $0 --region us-west-2 --key-name my-ec2-key --image ami-72ce4642 --instance-type m1.large"
  echo ""
  echo "  $0 --region eu-west-1 --key-name my-ec2-key --image ami-a93133dd --instance-type m1.large"
}


# Parse and validate command line args 
while [ $# -gt 0 ]
do
  case $1 in
  --instance-type) instancetype=$2  ;;
  --image)        image=$2 ;;
  --key-name)     ec2keypair=$2  ;;
  --region)       region=$2  ;;
  --group)        group=$2 ;;
  --help)
     usage
     exit 0  ;;
  *)
     echo "**** Bad argument: " $1
     usage
     exit 1 ;;
  esac
  shift 2
done


if [ -z "${image}" ] ; then
	echo "No Amazon image specified"
	exit 1
fi

if [ -z "${region}" ] ; then
	echo "No region specified"
	exit 1
fi

# If there is a group and a subnet passed on the command line,
# pass them in to our create instance operation.  We need a subnet
# for all VPC groups, so grab one if we see a VPC group specified.
if [ -n "${group}" ] ; then
	SG_ARG="--group $group"

			# If a subnet was not specified explicitly, 
			# list all subnets for the group and grab the first one
	ec2-describe-group --region $region $group | grep ^GROUP | grep -q -e "vpc-"
	isVPC=$? 
	if [ -z "${subnet}" -a  $isVPC ] ; then 
		subnets=`ec2-describe-subnets --region $region | grep ^SUBNET | grep available | awk '{print $2}'`
		for snet in $subnets
		do
			subnet=$snet
		done
	fi
	[ -n "${subnet}" ] && SG_ARG="$SG_ARG --subnet $subnet"
fi

if [ -n "${MAPR_LAUNCH_SCRIPT}" ] ; then
	if [ -f "${MAPR_LAUNCH_SCRIPT}" ] ; then
		UD_ARG="--user-data-file $MAPR_LAUNCH_SCRIPT"
	fi
fi


RI_OUT=eri_$$.out
rm -f $RI_OUT
ec2-run-instances \
	$image \
	--key $ec2keypair \
	${UD_ARG:-} \
	--instance-type $machinetype \
	${SG_ARG:-} \
	--region $region \
	--availability-zone ${region}b | tee $RI_OUT

if [ $? -ne 0 ] ; then
	echo ""
	echo "*** ec2-run-instances failed ***"
	exit 1
else 
	echo ""
fi

my_instance=`grep ^INSTANCE $RI_OUT | awk '{print $2}'`

echo "Wait a bit, then check for the IP assigned to $my_instance"
sleep 10

DI_OUT=edi_$$.out
rm -f $DI_OUT
ec2-describe-instances --region $region $my_instance | \
  awk '/^INSTANCE/ {print $4" "$5" "$8" "$14" "$15}' > $DI_OUT

read pub_name priv_name ami_index pub_ip priv_ip < $DI_OUT

echo "Instance $my_instance launched; "
echo "	public dns is $pub_name"

rm $RI_OUT $DI_OUT

