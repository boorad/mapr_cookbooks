The scripts in this directory are designed for use
with Amazon EC2.

Usage :
	launch-class-cluster.sh : creates EC2 instances and configures them
		for MapR based on the details in a list file (similar to the
		old maprinstall roles file).  The script leverages the
		launch-mapr-instance.sh and configure-mapr-instance.sh scripts.

	launch-mapr-instance.sh : prepare a random Amazon AMI for MapR
		installation.

	configure-mapr-instance.sh : install and configure MapR software
		on a node prepared via launch-mapr-instance.sh.  Metadata
		defining the installation is loaded from /home/mapr/mapr.parm.

	configureSG.sh : Open the proper ports for MapR traffic in to the
		specified security group.  launch-class-cluster will open
		port 8443 for MCS traffic, but nothing else.


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
	AWS_USER=
	AWS_ACCESS_KEY_ID=<go to AWS console to retrieve this>
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
