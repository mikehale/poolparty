pool :app do
  
  plugin_directory "plugins"
  
  instances 2..10
  
  cloud :app do
    apache do
      enable_php
    end
  end
  
end