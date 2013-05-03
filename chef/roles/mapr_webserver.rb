name "mapr_webserver"
description "MapR WebServer (Management Console) Role"
run_list(
  "role[mapr_base]",
  "recipe[mapr::webserver]"
)
default_attributes(

)
