require 'rubygems'

# Load required gems
@required_software = Array.new
%w(activesupport ftools logging resolv ruby2ruby).each do |lib|
  begin
    require lib
  rescue Exception => e
    @required_software << lib
  end  
end

require "#{File.dirname(__FILE__)}/poolparty/helpers/nice_printer"

unless @required_software.empty?
  @np = NicePrinter.new(45)

  # error_initializing_message.txt
  @np.header
  @np.center("Error")
  @np.left("Missing required software")
  @required_software.map {|a| @np << "  #{a}" }  
  @np << "Please install the required software"
  @np << "and try again"
  @np.empty
  @np << "Try installing #{@required_software.size == 1 ? "it" : "them"} with"
  @required_software.map {|a| @np << "  gem install #{a}" }
  @np.empty
  @np.footer
  
  @np.print
  exit(0)
end

# Use active supports auto load mechanism
ActiveSupport::Dependencies.load_paths << File.dirname(__FILE__)

## Load PoolParty
require "#{File.dirname(__FILE__)}/poolparty/version"

%w(core modules exceptions dependency_resolutions aska monitors net).each do |dir|
  Dir[File.dirname(__FILE__) + "/poolparty/#{dir}/**.rb"].each do |file|
    require file
  end
end

Kernel.load_p File.dirname(__FILE__) + "/poolparty/poolparty"
Logging.init :debug, :info, :warn, :error, :fatal

module PoolParty
  include FileWriter
  
  def logger
    @logger ||= make_new_logger
  end
  
  class PoolParty
    def initialize(spec)
      Script.inflate(spec) if spec
    end
  end
  
  private
  #:nodoc:#
  def make_new_logger
    FileUtils.mkdir_p ::File.dirname(Base.pool_logger_location) unless ::File.directory?(::File.dirname(Base.pool_logger_location))
    Loggable.new
  end
end

class Object
  include PoolParty
  include PoolParty::Pool
  include PoolParty::Cloud
  
  include PoolParty::DefinableResource
end

class Class
  include PoolParty::PluginModel  
end

## Load PoolParty Plugins and package
module PoolParty
  %w(plugins base_packages).each do |dir|
    Dir[::File.dirname(__FILE__) + "/poolparty/#{dir}/*.rb"].each do |file|
      require file
    end
  end
end