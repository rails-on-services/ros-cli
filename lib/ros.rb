# frozen_string_literal: true

require 'ros/version'
require 'pry'
require 'config'

Config.setup do |config|
  config.use_env = true
  config.env_prefix = 'ROS'
  config.env_separator = '__'
end

module Ros
  # Copied from ActiveSupport::StringInquirer
  class StringInquirer < String
    def method_missing(method_name, *arguments)
      if method_name[-1] == '?'
        self == method_name[0..-2]
      else
        super
      end
    end
  end

  class << self
    def preflight_check(fix: false)
      options = {}
      ros_repo = Dir.exists?(Ros.ros_root)
      env_config = File.exists?("#{environments_dir}/#{Ros.env}.yml")
      deploy_config = Dir.exists?("tmp/deployments/#{Ros.env}")
      if fix
        %x(git clone git@github.com:rails-on-services/ros.git) unless ros_repo
        generate_env([Ros.env]) unless env_config
        Ros.ops_action(:core, :setup, options) unless deploy_config
        Ros.ops_action(:platform, :setup, options) unless deploy_config
      else
        puts "ros repo: #{ros_repo ? 'ok' : 'missing'}"
        puts "environment configuration: #{env_config ? 'ok' : 'missing'}"
        puts "deployment configuration: #{deploy_config ? 'ok' : 'missing'}"
      end
    end

    def generate_service(args, options = {}, behavior = nil)
      require 'ros/generators/service/service_generator'
      # require_relative "ros/generators/service/service_generator.rb"
      args.push(File.basename(Ros.root)) unless args[1]
      generator = Ros::Generators::ServiceGenerator.new(args, options)
      # generator.options = options
      generator.behavior = behavior if behavior
      generator.destination_root = Ros.root
      generator.invoke_all
    end

    def generate_env(args, options = {}, behavior = nil)
      require_relative "ros/generators/env/env_generator.rb"
      args.push('http://localhost:3000') unless args[1]
      args.push(File.basename(Ros.root)) unless args[2]
      args.push('')
      generator = Ros::Generators::EnvGenerator.new(args)
      generator.options = options
      generator.behavior = behavior if behavior
      generator.destination_root = Ros.root
      generator.invoke_all
    end

    # def ops_action(stack_component, action, options = Config::Options.new)
    def generate(options = {}, *stack)
      require 'ros/generators/stack'
      # require "ros/generators/be/#{stack.last(2).first}"
      require 'ros/generators/be/cluster'
      require 'ros/generators/be/application'
      require "ros/generators/#{stack.join('/')}/#{stack.last}_generator"
      g_string = "Ros::Generators::#{stack.map{ |s| s.capitalize }.join('::')}::#{stack.last.capitalize}Generator"
      generator = Object.const_get(g_string).new
      # TODO: invoke as an option and pass that option when invoking from the CLI
      generator.options = options
      generator.behavior = options[:behavior] || :invoke
      generator.destination_root = Ros.root
      generator.invoke_all
    end

    def ops(options = {}, *stack)
      require 'ros/generators/stack'
      # require "ros/generators/be/gt
      what = Settings.components.be.components.cluster.config.type.eql?('kubernetes') ? 'kubernetes' : 'instance'
      require "ros/ops/#{what}"
      g_string = "Ros::Ops::#{what.capitalize}::#{stack.last.capitalize}"
      generator = Object.const_get(g_string).new
      generator.invoke
      # binding.pry
    end

    def x_ops_action(type, action, options = Config::Options.new)
      infra_type = Settings.infra.config.type
      require "ros/ops/#{infra_type}"
      obj = Object.const_get("Ros::Ops::#{infra_type.capitalize}::#{type.to_s.capitalize}").new(options)
      obj.switch!
      obj.send(action)
    end

    # load deployments/env and environments/env
    # If the environment has a '-' in it and an environment is defined before the '-' then use it as a base
    def load_env(env = nil)
      Ros.env = env if env
      files = []
      %w(deployment environment).each do |type|
        files.append("#{Ros.root}/config/#{type}.yml")
        files.append("#{Ros.root}/config/#{type}s/#{Ros.env}.yml")
        if ENV['ROS_PROFILE']
          profile_file = "#{Ros.root}/config/#{type}s/#{Ros.env}-#{ENV['ROS_PROFILE']}.yml"
          files.append(profile_file) if File.exists?(profile_file)
        end
      end
      Config.load_and_set_settings(files)
    end

    # Underscored representation of a Config hash
    def format_envs(key, value, ary = [])
      if value.is_a?(Config::Options)
        value.each_pair do |skey, value|
          format_envs("#{key}#{key.empty? ? '' : '__'}#{skey}", value, ary)
        end
      else
        ary.append("#{key.upcase}=#{value}")
      end
      ary
    end

    # def platform; @platform ||= Ros::Platform.descendants.first end
    def env; @env ||= StringInquirer.new(ENV['ROS_ENV'] || default_env) end
    def env=(env); @env = StringInquirer.new(env) end
    def default_env; @default_env ||= 'development' end

    def root
      @root ||= (cwd = Dir.pwd
        while not cwd.eql?('/')
          break Pathname.new(cwd) if File.exists?("#{cwd}/config/deployment.yml")
          cwd = File.expand_path('..', cwd)
        end)
    end

    # NOTE: uri and api_hostname are implemented in deployment.rb
    # this file is not namespace aware so
    # def uri; URI("#{Settings.infra.config.endpoints.api.scheme}://#{api_hostname}") end

    # def api_hostname
    #   @api_hostname ||= "#{Settings.infra.config.endpoints.api.host}.#{Settings.infra.config.dns.subdomain}.#{Settings.infra.config.dns.domain}"
    # end

    # def api_hostname
    #   @api_hostname ||=
    #     if Settings.infra.branch_deployments and not branch_name.eql?(infra.api_branch)
    #       "#{Settins.infra.endpoints.api.host}-#{branch_name}"
    #     else
    #       Settings.infra.endpoints.api.host
    #     end + ".#{Settings.infra.dns.subdomain}.#{Settings.infra.dns.domain}"
    # end

    def service_names_enabled; Settings.platform.services.reject{|s| s.last.enabled.eql? false }.map{ |s| s.first } end
    def service_names; Settings.platform.services.keys end

    def tf_root; root.join('devops/terraform') end
    def ansible_root; root.join('devops/ansible') end
    def helm_root; root.join('devops/helm') end
    def k8s_root; root.join('devops/k8s') end

    def config_dir; "#{Ros.root}/config" end
    def environments_dir; "#{config_dir}/environments" end
    def deployments_dir; "#{config_dir}/deployments" end

    def ros_root; is_ros? ? root : root.join('ros') end

    def has_ros?; not is_ros? and Dir.exists?(ros_root) end

    # TODO: This is a hack in order to differentiate for purpose of templating files
    def is_ros?
      false
      # Settings.platform.config.image_registry.eql?('railsonservices') and Settings.platform.environment.platform.partition_name.eql?('ros')
    end
  end
end

Ros.load_env unless Ros.root.nil?
