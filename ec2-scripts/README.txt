The scripts in this directory are designed for use with
Amazon EC2.  The directory is part of the MapR Mercurial GCE package
	ssh://mapr@10.250.1.5/gce

See the Overview section below for a description of what happens during
the launching of a cluster.

A list of Amazon AMI's known to work with these scripts is given below.
In theory, any cloud-init AMI will work (though you must know the
login user with sudo privileges)

Contents : 
	launch-class-cluster.sh : 
		Wrapper script to create EC2 instances and configures them
		for MapR based on the details in a list file (similar to the 
		old maprinstall roles file).  The script leverages the 
		launch-mapr-instance.sh and configure-mapr-instance.sh scripts.

		The deployment is targeted for MapR training classes, where 
		all nodes have a public IP address.

		The comments in this script include excellent examples for 
		launching clusters.

	[ IN DEVELOPMENT } launch-se-cluster.sh : 
		An analog of the launch-class-cluster script
		that supports launching a cluster within an Amazon VPC

	launch-mapr-instance.sh : 
		Prepare a random Amazon AMI for MapR installation.  

	configure-mapr-instance.sh : 
		Install and configure MapR software on a node prepared by
		the launch-mapr-instance.sh script.  Metadata 
		defining the installation is loaded from /home/mapr/mapr.parm.

	configureSG.sh : Open the proper ports for MapR traffic in to the 
		specified security group.  launch-class-cluster will open
		port 8443 for MCS traffic, but nothing else.


Extras : 
	class/*.lst : sample configuration files
	
	eclaunch-script.sh : launch a single EC2 instance with a
		startup script (no larger than 16KB)
		
Prerequisites:
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


MetaData available during launch:
	The Amazon framework provides several key details via a REST 
	interface during instance spin-up.   One's we've used include:

		murl_top=http://169.254.169.254/latest/meta-data
		murl_attr="${murl_top}/attributes"

		THIS_FQDN=$(curl -f $murl_top/hostname)
		THIS_HOST=${THIS_FQDN%%.*}

		AMI_IMAGE=$(curl -f $murl_top/ami-id)
		AMI_LAUNCH_INDEX=$(curl -f $murl_top/ami-launch-index) 


Working AMI's with ebs boot volumes

	us-east-1 region
		ami-888815e1	CentOS 6.3 (su login: ec2-user)
		ami-fa68f393	CentOS 6.3 (su login: ec2-user)
		ami-f1be3998	CentOS 6.3 {minimal} (su login: ec2-user)
		ami-3d4ff254	Ubuntu 12.04 (su login: ubuntu)

	us-west-1 region
		ami-2862436d	CentOS 6.3 {minimal} (su login: ec2-user)

	us-west-2 region
		ami-72ce4642	CentOS 6.3 (minimal) (su login: ec2-user)
		ami-8e109ebe	Ubuntu 12.04 (su login: ubuntu)

			HVM support (m2/m3 instance types)
		ami-aa06939a	CentOS 6.4 su login: ec2-user)
		ami-4ac9437a	Ubuntu 12.04 (su login ubuntu)

	eu-west-1 region
		ami-a93133dd	CentOS 6.3 {minimal} (su login: ec2-user)


Overview
	Goal : 
		Deploy a MapR cluster within Amazon EC2 based on
		a roles-file configuration.

	Logical Flow :
		- Identify the AWS account you will use
			- Save the AWS credentials into your environment
			- Establish a public/private SSH keypair to use for
			  access to the cluster.   The scripts assume that
			  the basename for the file is the same as the
			  label given to the key in AWS ... and that the
			  key-file is in $HOME/.ssh for the user launching
			  the cluster.
		- Create a roles file defining the MapR packages to be deployed.
			This MUST be a consistent cluster (no error checking is
			done to ensure, for example, that there is a CLDB node
			and an odd number of zookeepers).
		- Run the launch-*-cluster.sh script with the proper arguments
			The script performs the following operations
				1. Create <n> EC2 instances, based on the number of
				   entries in the roles file
				2. Pass the launch-mapr-instance.sh script into each
				   node as an initial setup
				3. Watch for the existence of the MapR user and the
				   presence of the launch-mapr.log file (indicating
				   that the launch-mapr-instance.sh script has 
				   completed successfully.
				4. Generate the necessary cluster configuration information
				   based on the roles file and the private IP addresses
				   of the newly spawned nodes.
				5. Copy a parameter file (mapr.parm) to each node with 
				   the correct configuration details and the desired
				   MapR software packages.
				6. Execute the congfigure-mapr-instance.sh script to
				   install all MapR software and start up the cluster.
				7. Extra steps
					a. Copy ssh keys to facilitate MCS usage and 
					   clush administration.
					b. Create a "host mapping file" for use on the client
					   to properly map private host names of the cluster
					   node to public IP addresses.

Known Issues:
	The launch-mapr-instance.sh script is limited to 16K.

