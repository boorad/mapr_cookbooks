#!/bin/bash

# install omnibus-chef
curl -L https://www.opscode.com/chef/install.sh | sudo bash

# add omnibus-chef to the path
echo 'export PATH="/opt/chef/embedded/bin:$PATH"' >> ~/.bash_profile && source ~/.bash_profile

# missing from ubuntu
sudo apt-get install gcc git make

# install berkshelf
sudo gem install berkshelf --no-rdoc --no-ri

# create chef directory
mkdir -p ~/chef

# grab chef bits
## manual scp from host to this node

# grab manifest
## manual scp from host to this node

# move cookbooks folder because berkshelf is destructive
mv ~/chef/cookbooks ~/chef/cookbooks_mapr

# run berkshelf
cd ~/chef/cookbooks_mapr/mapr
berks install --path ~/chef/cookbooks

# move mapr cookbook in place
cd ~/chef
mv ~/chef/cookbooks_mapr/mapr ~/chef/cookbooks
rm -rf ~/chef/cookbooks_mapr

# TODO: ubuntu enforces gpg authentication
# so add back the --allow-unauthenticated into chef recipes (debian,ubuntu) only.

# run chef-solo
sudo chef-solo -c solo.rb -j i2_manifest.json
