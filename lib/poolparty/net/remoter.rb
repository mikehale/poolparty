=begin rdoc
  This module is included by the remote module and defines the remoting methods
  that the clouds can use to rsync or run remote commands
=end
require File.dirname(__FILE__) + "/../helpers/provisioner_base"

module PoolParty
  module Remote
    module Remoter
      def rsync_storage_files_to_command(remote_instance)        
        "#{rsync_command} #{Base.storage_directory}/ #{remote_instance.ip}:#{Base.remote_storage_path}" if remote_instance
      end
      def run_command_on_command(cmd="ls -l", remote_instance=nil)
        vputs "Running #{cmd} on #{remote_instance.name == %x[hostname].chomp ? "self (master)" : "#{remote_instance.name}"}"
        remote_instance.name == %x[hostname].chomp ? %x[#{cmd}] : "#{ssh_command(remote_instance)} '#{cmd}'"
      end
      def ssh_command(remote_instance)
        "#{ssh_string} #{remote_instance.ip}"
      end
      # Generic commandable strings
      def ssh_string
        (["ssh"] << ssh_array).join(" ")
      end
      # Array of ssh options
      # Includes StrictHostKeyChecking to no
      # Ssh with the user in Base
      # And including the keypair_path
      def ssh_array
        ["-o StrictHostKeyChecking=no", "-l '#{Base.user}'", '-i "'+full_keypair_path+'"']
      end
      def rsync_command
        "rsync -azP --exclude cache -e '#{ssh_string}'"
      end
      def remote_ssh_array
        ["-o StrictHostKeyChecking=no", "-l '#{Base.user}'", '-i "'+remote_keypair_path+'"']
      end
      def remote_ssh_string
        (["ssh"] << remote_ssh_array).join(" ")
      end
      def remote_rsync_command
        "rsync -azP --exclude cache -e '#{remote_ssh_string}'"
      end
      # Get the names of the nodes. Mainly used for puppet templating
      def list_of_node_names(options={})
        list_of_running_instances.collect {|ri| ri.name }
      end
      # An array of node ips. Mainly used for puppet templating
      def list_of_node_ips(options={})
        list_of_running_instances.collect {|ri| ri.ip }
      end

      # Get the instance first instance file that exists on the system from the expected places
      # denoted in the local_instances_list_file_locations
      def get_working_listing_file
        local_instances_list_file_locations.reject {|f| f unless File.file?(f) }.first
      end
      # Expected places for the instances.list to be located at on the machine
      def local_instances_list_file_locations
        [
          "#{Base.storage_directory}/#{name}-instances.list",
          "#{Base.base_config_directory}/#{name}-instances.list",
          "~/.#{name}-instances.list",
          "~/#{name}-instances.list",          
          "#{name}-instances.list"
        ]
      end
      
      # List calculation methods
      # 
      # Are the minimum number of instances running?
      def minimum_number_of_instances_are_running?
        list_of_running_instances.size >= minimum_instances.to_i
      end
      # Can we shutdown an instance?
      def can_shutdown_an_instance?
        list_of_running_instances.size > minimum_instances.to_i
      end
      # Request to launch a number of instances
      def request_launch_new_instances(num=1)
        out = []
        num.times {out << launch_new_instance!}
        out
      end
      def request_launch_master_instance
        @inst = launch_new_instance!
        wait "5.seconds"
        when_no_pending_instances do
          vputs "Master has launched"
          reset!
          after_launch_master(@inst)
        end
      end
      def after_launch_master(inst=nil)
        vputs "After launch master in remoter"
      end
      # Let's terminate an instance that is not the master instance
      def request_termination_of_non_master_instance
        inst = nonmaster_nonterminated_instances.last
        terminate_instance!(inst.instance_id) if inst
      end
      # Can we start a new instance?
      def can_start_a_new_instance?
        maximum_number_of_instances_are_not_running? && list_of_pending_instances.size == 0
      end
      # Are the maximum number of instances not running?
      def maximum_number_of_instances_are_not_running?
        list_of_running_instances.size < maximum_instances.to_i
      end
      # Are the maximum number of instances running?
      def maximum_number_of_instances_are_running?
        list_of_running_instances.size >= maximum_instances.to_i
      end
      # Launch new instance while waiting for the number of pending instances
      #  to be zero before actually launching. This ensures that we only
      #  launch one instance at a time
      def request_launch_one_instance_at_a_time
        when_no_pending_instances { launch_new_instance! }
      end
      # A convenience method for waiting until there are no more
      # pending instances and then running the block
      def when_no_pending_instances(&block)
        reset!        
        if list_of_pending_instances.size == 0
          block.call if block
        else
          vprint "."
          wait "5.seconds"
          when_no_pending_instances(&block)
        end
      end
      # A convenience method for waiting until all the instances have an ip
      # assigned to them. This is useful when shifting the ip addresses
      # around on the instances
      def when_all_assigned_ips(&block)
        reset!
        if list_of_nonterminated_instances.select {|a| a.ip == "not.assigned" }.empty?          
          block.call if block
        else
          vprint "."
          wait "5.seconds"
          when_all_assigned_ips(&block)
        end
      end
      
      # This will launch the minimum_instances if the minimum number of instances are not running
      # If the minimum number of instances are not running and if we can start a new instance
      def launch_minimum_number_of_instances        
        if can_start_a_new_instance? && !minimum_number_of_instances_are_running?         
          list_of_pending_instances.size == 0 ? request_launch_one_instance_at_a_time : wait("5.seconds")
          reset!
          launch_minimum_number_of_instances
          provision_slaves_from_n(minimum_instances.to_i)
          after_launched
        end
      end
      
      def provision_slaves_from_n(num=1)
        vputs "In provision_slaves_from_n: #{num}"
        reset!
        when_no_pending_instances do
          vputs "Waiting for 10 seconds"
          wait "10.seconds" # Give some time for ssh to startup          
          @num_instances = list_of_running_instances.size
          vputs "(@num_instances - (num))..(@num_instances): #{(@num_instances - (num))..(@num_instances)}"
          last_instances = nonmaster_nonterminated_instances[(@num_instances - (num))..(@num_instances)]
          last_instances.each do |inst|
            vputs "Provision slave: #{inst}"
            hide_output {PoolParty::Provisioner.process_clean_reconfigure_for!(inst, self)}
            PoolParty::Provisioner.provision_slave(inst, self, false) unless inst.master? rescue vputs "Error"
            hide_output {PoolParty::Provisioner.process_clean_reconfigure_for!(inst, self)}
            # cmd = ". /etc/profile && cloud-provision -i #{inst.name.gsub(/node/, '')} &"
            # vputs "Provision slave with command #{cmd}"
          end
          PoolParty::Provisioner.reconfigure_master(self)
        end
      end
      # Launch the master and let the master handle the starting of the cloud
      # We should only launch an instance if there are no pending instances, in the case 
      # that the master has launched, but is still pending
      # and if the master is not running AND we can start a new instance
      # Then wait for the master to launch
      def launch_and_configure_master!(testing=false)
        vputs "Requesting to launch new instance"
        logger.debug "Launching master"
        request_launch_master_instance if list_of_pending_instances.size.zero? && can_start_a_new_instance? && !is_master_running? && !testing
        reset!
        unless testing
          vputs ""
          vputs "Waiting for there to be no pending instances..."
          when_no_pending_instances do
            when_all_assigned_ips {wait "20.seconds"}
            vputs ""
            vputs "Provisioning master..."
            # cleanup_storage_directory
            verbose ? Provisioner.provision_master(self, testing) : hide_output { Provisioner.provision_master(self, testing) }
            verbose ? Provisioner.clear_master_ssl_certs(self, testing) : hide_output { Provisioner.clear_master_ssl_certs(self, testing) }
          
            after_launched
          end
        end
      end
      def is_master_running?
        !list_of_running_instances.select {|a| a.name == "master"}.first.nil?
      end
      # Stub method for the time being to handle expansion of the cloud
      def should_expand_cloud?(force=false)
        valid_rules?(:expand_when) || force || false
      end
      # Stub method for the time being to handle the contraction of the cloud
      def should_contract_cloud?(force=false)
        valid_rules?(:contract_when) || force || false
      end
      # Expand the cloud
      # If we can start a new instance and the load requires us to expand
      # the cloud, then we should request_launch_new_instances
      # Wait for the instance to boot up and when it does come back
      # online, then provision it as a slave, this way, it is ready for action from the
      # get go
      def expand_cloud_if_necessary(force=false)
        if can_start_a_new_instance? && should_expand_cloud?(force)
          vputs "Expanding the cloud based on load"
          @num = 1
          @num.times do |i|
            list_of_pending_instances.size == 0 ? request_launch_one_instance_at_a_time : wait("5.seconds")          
            reset!
            vputs "request_launch_new_instances: #{@num}"
            provision_slaves_from_n(@num)
            after_launched
          end
        end
      end
      # Contract the cloud
      # If we can shutdown an instnace and the load allows us to contract
      # the cloud, then we should request_termination_of_non_master_instance
      def contract_cloud_if_necessary(force=false)
        if can_shutdown_an_instance?          
          if should_contract_cloud?(force)
            vputs "Shrinking the cloud by 1"
            before_shutdown
            request_termination_of_non_master_instance
          end
        end
      end
      
      # Callbacks
      
      # After launch callback
      # This is called after a new instance is launched
      def after_launched(force=false)        
      end
      
      # Before shutdown callback
      # This is called before the cloud is contracted
      def before_shutdown
      end
      
      # Rsync command to the instance
      def rsync_storage_files_to(instance=nil)
        hide_output {Kernel.system "#{rsync_storage_files_to_command(instance)}" if instance}
      end
      # Take the rsync command and execute it on the system
      # if there is an instance given
      def run_command_on(cmd, instance=nil)        
        Kernel.system "#{run_command_on_command(cmd, instance)}" if instance
      end
      
      # Ssh into the instance given
      def ssh_into(instance=nil)
        Kernel.system "#{ssh_command(instance)}" if instance
      end
      # Find the instance by the number given
      # and then ssh into the instance
      def ssh_into_instance_number(num=0)
        ssh_into( get_instance_by_number( num || 0 ) )
      end
      
      # Run command on the instance by the number
      def run_command_on_instance_number(cmd="ls -l", num=0)
        run_command_on(cmd, get_instance_by_number( num || 0 ) )
      end
      
      # Prepare reconfiguration on the master
      # TODO: Curious about the puppet/ssl problems...
      # puppetd --test --no-daemonize 2>&1 &
      # rm -rf /etc/puppet/ssl/*; 
      def prepare_reconfiguration
        unless @prepared
          # cmd = "/etc/init.d/puppetmaster restart"
          # run_command_on(cmd, master)
          @prepared = true
        end
      end

      def self.included(receiver)
        receiver.extend self
      end
    end
  end
end