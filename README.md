#mapr deployments


This repository contains a few different options for deploying MapR Hadoop clusters.  The one furthest along is orchestrated by Fabric, and uses Chef on each node to execute the deployment.

##Assumptions

* A user on each node, allowing ssh and sudo
* Berkshelf Ruby gem installed on packaging machine
  * In base folder of this repo, touch a file called 'DEV' to activate development mode, or remove file to deactivate development mode

##Process

###Prepare

    ./package
Copy the tarball somewhere, and expand it.

###Edit

In the packaged folder (from the tarball above), edit cluster.json to suit your cluster.

###Execute

    ./install

## TODO

* delete everything from this chef repo that fabric doesn't move over
* generate new certificates each run
* .bashrc for install user and mapr user, not just root
* json parse check on cluster.json before executing anything fabric or manifests.py related.
* start zk, wait for success, then start cldb (warden), wait for success, then start warden on other nodes
* add 'fc' permissions to mapr user
* install clush on installer node, with proper groups & sudo
* passwd on mapr user (only webserver?  or all nodes?)
* sshd_config ... add mapr to AllowGroups
* one zk setup * should be single and not stand-alone, for easier migrations to multiple zks... but not an even number.
* Metrics setup
* finish off local package repository functionality * installer or other node holds all packages for other nodes to pull * bandwidth saver
* disksetup * make idempotent
* add nodes to existing cluster
* Web UI
