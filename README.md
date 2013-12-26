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
