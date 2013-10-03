name "base"
description "base role"
run_list(
  "recipe[mapr::user_root]",
  "recipe[emacs]"
)
