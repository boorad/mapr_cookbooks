The scripts in this directory are designed for use with
Amazon EC2.  The directory is part of the MapR Deployment Packages
repository at 
	github.com/mapr/mapr-deployments

Start with OVERVIEW.txt to understand what these scripts do to
launch a cluster in the Amazon EC2 environment.

EXAMPLES :
	Simple deployment, public network with ephemeral disks
		./launch-se-cluster.sh \
			--cluster MapR_Pub \
			--mapr-version 3.0.1 \
			--config-file class/5node.lst \
			--region us-west-2
			--key-file <your_ec2_ssh_key> \
			--image ami-72ce4642 \
			--image-su ec2-user  \
			--instance-type m1.large 
	
	Critical arguments
		SSH Key Options:
			--key-file <ec2_ssh_key>
				The script logic will look for <key> and <key>.pem in 
				the current directory and $HOME/.ssh.   The base name
				of the key file must match the KeyPair name in the
				Amazon account.

				WARNING: be sure the permissions on your key-file
				are set to 600 to ensure proper behavior of ssh

		Storage Options (applied equally to all nodes):
			--data-disks <n>			: allocate <n> ephemeral disks (max 4)
			--persistent-disks <n>x<m>	: allocate <n> EBS volumes of size <m>

			NOTE: only the last option of "data-disks" and
			"persistent-disks" will be used.

	Helpful arguments
		Naming features
			By default, an EC2 tag will be applied to each instance
			in the form of "<cluster>-node<n>".  The optional "--nametag"
			option allows you to specify an additional string to 
			further identify the cluster.   When present, the tag will
			be restructured to
				<nametag>-<cluster>-node<n>

	VPC deployment
		The advantage of the VPC is that the private IP addresses of 
		the nodes will remain consistent across reboots, which means
		the cluster configuration can be maintained.   You can use 
		ephemeral disks (which will NOT maintain cluster data across
		shutdowns) or EBS disks.

		Process :
			Use AWS console to create a VPC with 1 subnet and 
			DNS resolution (these are the default options for 
			VPC Wizard as of 01-Oct-2013)
				Note the newly created security group (sg-<id>)

			Use configureSG.sh to open the necessary ports on sg-<id>

			Run the configuration as above, adding the 
			"-sgroup sg-<id>" setting.

		WARNING :
			Some CentOS AMI's are left with incorrect data in 
			/etc/sysconfig/network.   You'll want to check that 
			file to make sure its HOSTNAME setting  matches the 
			actual private IP of the node.
				TBD : have the launch-*-cluster.sh scripts check for
				and resolve this problem


PREREQUISITES:
	Install the Amazon EC2 utility package :
		http://aws.amazon.com/developertools/351
	Your environment should have the $TOOLS/bin directory in your path
	Establish/retrieve your AWS credentials 
		AWS_USER, AWS_ACCESS_KEY_ID, and AWS_SECRET_ACCESS_KEY

The scripts assume that the EC2 environment is set 
(these are examples from my Mac OSX environment)
	JAVA_HOME=/System/Library/Frameworks/JavaVM.framework/Home
	EC2_HOME=$HOME/utils/ec2-api-tools-1.6.8.0
	AWS_USER=awsse@maprtech.com
	AWS_ACCESS_KEY_ID=AKIAI3YUDKTFJDGJ25NA
	AWS_SECRET_ACCESS_KEY=<go to AWS console to retrieve this>


DETAILS :
	See CONTENTS.txt for a list of files in this package.
	See OVERVIEW.txt a functional description of the launch process.   
	See the launch-*-cluster.sh scripts themselves for examples or
		run the scripts for on-line help

	A list of Amazon AMI's known to work with these scripts is given below.
	In theory, any cloud-init AMI will work (though you must know the
	login user with sudo privileges).  Always test a new AMI with 
	eclaunch-script.sh to ensure proper functionality and confirm the 
	login user's sudo privileges.

	All nodes will be configured with a "mapr" user in addition to
	the default AMI user.   The password for mapr is defined in the 
	launch-mapr-instance.sh script (see the MAPR_PASSWD variable).
	You'll want to use that login to access the MapR Control System
	console once the cluster is launched.


WORKING AMI's with ebs boot volumes

	us-east-1 region
		ami-35792c5c    Amazon Linux 2013.09 EBS (su login: ec2-user)
		ami-888815e1	CentOS 6.3 (su login: ec2-user)
		ami-fa68f393	CentOS 6.3 (su login: ec2-user)
		ami-f1be3998	CentOS 6.3 {minimal} (su login: ec2-user)
		ami-3d4ff254	Ubuntu 12.04 (su login: ubuntu)

	us-west-1 region
		ami-687b4f2d	Amazon Linux 2013.09 EBS (su login: ec2-user)
		ami-2862436d	CentOS 6.3 {minimal} (su login: ec2-user)

	us-west-2 region
		ami-d03ea1e0    Amazon Linux 2013.09 EBS (su login: ec2-user)
		ami-72ce4642	CentOS 6.3 (minimal) (su login: ec2-user)
		ami-ec30a5dc	CentOS 6.4 + cloud-init (su login: ec2-user) (no EBS)
		ami-1064f120	CentOS 6.4 + cloud-init (su login: ec2-user)
		ami-8e109ebe	Ubuntu 12.04 (su login: ubuntu)

			HVM support (m2/m3 instance types)
		ami-aa06939a	CentOS 6.4 su login: ec2-user)
		ami-4ac9437a	Ubuntu 12.04 (su login ubuntu)

	eu-west-1 region
		ami-149f7863    Amazon Linux 2013.09 EBS (su login: ec2-user)
		ami-a93133dd	CentOS 6.3 {minimal} (su login: ec2-user)


	NOTE: 
		The minimal CentOS images can take a VERY long time to
		install ... more than 30 minutes due to the plethora of
		operating system packages needed for a MapR deployment.

		The Amazon Linux images are the fastest to spin up, but
		they have incomplete support for CentOS bundles (eg sdparm,
		which is key for MapR).   Workarounds have been implemented
		to support these images for MapR 2.1 and 3.0 releases.

