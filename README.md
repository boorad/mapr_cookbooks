private-mapr-deployments
========================

Prep Each Node
==============

1. At shell, type:

    > sudo groupadd -g 2222 mapr
    > sudo useradd -g mapr -m -u 2222 mapr
    > sudo passwd mapr
    (set password)

2. Copy ssh public key contents to /home/mapr/.ssh/authorized_keys
