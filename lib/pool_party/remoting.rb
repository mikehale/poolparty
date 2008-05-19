module PoolParty
  extend self
  
  class Remoting
    include PoolParty
    include Ec2Wrapper
    include Scheduler
                
    # == GENERAL METHODS    
    # == LISTING
    # List all the running instances associated with this account
    def list_of_running_instances
      get_instances_description.select {|a| a[:status] =~ /running/}
    end
    # Get a list of the pending instances
    def list_of_pending_instances
      get_instances_description.select {|a| a[:status] =~ /pending/}
    end
    # list of shutting down instances
    def list_of_terminating_instances
      get_instances_description.select {|a| a[:status] =~ /shutting/}
    end
    # Get number of pending instances
    def number_of_pending_instances
      list_of_pending_instances.size
    end
    def number_of_running_instances
      list_of_running_instances.size
    end
    def number_of_pending_and_running_instances
      number_of_running_instances + number_of_pending_instances
    end
    # == LAUNCHING
    # Request to launch a new instance
    # Will only luanch if the last_startup_time has been cleared
    # Clear the last_startup_time if instance does launch
    def request_launch_new_instance
      if can_start_a_new_instance?
        update_startup_time
        request_launch_one_instance_at_a_time
        return true
      else
        return false
      end
    end
    def can_start_a_new_instance?
      eval(Application.interval_wait_time).ago >= startup_time && maximum_number_of_instances_are_not_running?
    end
    def maximum_number_of_instances_are_not_running?
      list_of_running_instances.size < Application.maximum_instances
    end
    def update_startup_time
      @last_startup_time = Time.now
    end
    def startup_time
      @last_startup_time ||= Time.now
    end
    # Request to launch a number of instances
    def request_launch_new_instances(num=1)
      out = []
      num.times {out << request_launch_one_instance_at_a_time}
      out
    end
    # Launch one instance at a time
    def request_launch_one_instance_at_a_time
      while !number_of_pending_instances.zero?
        wait "5.seconds"
      end
      return launch_new_instance!
    end
    # == SHUTDOWN
    # Terminate all running instances
    def request_termination_of_running_instances
      list_of_running_instances.each {|a| terminate_instance!(a[:instance_id])}
    end
    def request_termination_of_all_instances
      get_instances_description.each {|a| terminate_instance!(a[:instance_id])}
    end
    # Terminate instance by id
    def request_termination_of_instance(id)
      if can_shutdown_an_instance?
        update_shutdown_time
        terminate_instance! id
        return true
      else
        return false
      end
    end
    def can_shutdown_an_instance?
      eval(Application.interval_wait_time).ago >= shutdown_time && minimum_number_of_instances_are_running?
    end
    def minimum_number_of_instances_are_running?
      list_of_running_instances.size > Application.minimum_instances
    end
    def update_shutdown_time 
      @last_shutdown_time = Time.now
    end
    def shutdown_time
      @last_shutdown_time ||= Time.now
    end
    
    def running_instances
      @running_instances ||= update_instance_values
    end
    
    def update_instance_values
      @running_instances = list_of_running_instances.collect {|a| RemoteInstance.new(a) }.sort
    end
    
    def exec_remote(ri,opts={})
      hash = {
        :cmd => "scp", 
        :src => "None",
        :dest => "None",
        :switches => "",
        :user => "root",
        :silent => verbose?,        
        :cred => Application.credentials}.merge(opts)
      
      hash[:switches] += "-i #{hash[:cred]}"
      
      f = case hash[:cmd]
        when "scp"
          "scp #{hash[:switches]} #{hash[:src]} #{hash[:user]}@#{ri.ip}:#{hash[:dest]}"
        else
          "ssh #{hash[:switches]} #{hash[:user]}@#{ri.ip} '#{hash[:cmd]}'"
        end
      
      message("executing #{f}")
      `#{f}`
    end
        
  end
    
end