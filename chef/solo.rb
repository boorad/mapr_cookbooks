require 'ohai'
current_dir = File.expand_path(File.dirname(__FILE__))
node_name "solo"
file_cache_path "#{current_dir}/cache"
file_backup_path "#{current_dir}/backup"
cookbook_path "#{current_dir}/cookbooks"
data_bag_path "#{current_dir}/data_bags"
role_path "#{current_dir}/roles"
cache_type "BasicFile"
cache_options({ :path => "#{current_dir}/checksums", :skip_expires => true })

# Proxy settings
http_proxy "#{ENV['http_proxy']}" if ENV['http_proxy']
https_proxy "#{ENV['https_proxy']}" if ENV['https_proxy']
http_proxy_user "#{ENV['http_proxy_user']}" if ENV['http_proxy_user']
http_proxy_pass "#{ENV['http_proxy_pass']}" if ENV['http_proxy_pass']

# Ohai plugins
Ohai::Config[:plugin_path] << "#{current_dir}/ohai_plugins"