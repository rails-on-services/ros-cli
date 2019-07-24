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

  def self.gem_root
    File.expand_path '../..', __FILE__
  end

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
    def generate_project(args)
      name = args[0]
      # host = URI(args[1] || 'http://localhost:3000')
      # args.push(:nil, :nil, :nil)
      require 'ros/generators/stack/project/project_generator.rb'
      generator = Ros::Generators::ProjectGenerator.new(args)
      generator.destination_root = name
      generator.invoke_all
      # require 'ros/generators/stack/env/env_generator.rb'
      # %w(development test production).each do |env|
      #   generator = Ros::Generators::EnvGenerator.new([env, nil, name, nil])
      #   generator.destination_root = name
      #   generator.invoke_all
      # end
      require 'ros/generators/be/rails/rails_generator.rb'
      generator = Ros::Generators::Be::RailsGenerator.new(args)
      generator.destination_root = "#{name}/be"
      generator.invoke_all
    end

    def generate_env(args, options = {}, behavior = nil)
      require "ros/generators/be/env/env_generator.rb"
      args.push('http://localhost:3000') unless args[1]
      args.push(File.basename(Ros.root)) unless args[2]
      args.push('')
      generator = Ros::Generators::EnvGenerator.new(args)
      generator.options = options
      generator.behavior = behavior if behavior
      generator.destination_root = Ros.root
      generator.invoke_all
    end

    def preflight_check(fix: false)
      options = {}
      ros_repo = Dir.exists?(Ros.ros_root)
      env_config = File.exists?("#{environments_dir}/#{Ros.env}.yml")
      if fix
        %x(git clone git@github.com:rails-on-services/ros.git) unless ros_repo
        generate_env([Ros.env]) unless env_config
      else
        puts "ros repo: #{ros_repo ? 'ok' : 'missing'}"
        puts "environment configuration: #{env_config ? 'ok' : 'missing'}"
      end
    end

    def generate_service(args, options = {}, behavior = nil)
      require 'ros/generators/be/service/service_generator'
      # require_relative "ros/generators/service/service_generator.rb"
      args.push(File.basename(Ros.root)) unless args[1]
      generator = Ros::Generators::ServiceGenerator.new(args, options)
      # generator.options = options
      generator.behavior = behavior if behavior
      generator.destination_root = Ros.root
      generator.invoke_all
    end

    def from_rake(task, args)
      behavior, *stack = task.name.split(':')
      require 'ros/generators/stack'
      g_string = "#{stack.map{ |s| s.capitalize }.join('::')}::#{stack.last.capitalize}Generator"
      generator = Ros::Generators.const_get(g_string).new
      generator.behavior = behavior.eql?('destroy') ? :revoke : :invoke
      generator.destination_root = Ros.root
      generator.invoke_all
    end

    def install_templates
      %w(platform services).each do |type|
        require "ros/generators/be/application/#{type}/#{type}_generator"
        klass = Object.const_get("Ros::Generators::Be::Application::#{type.capitalize}::#{type.capitalize}Generator")
        klass.install_templates
      end
      %w(infra services).each do |type|
        require "ros/generators/be/cluster/#{type}/#{type}_generator"
        klass = Object.const_get("Ros::Generators::Be::Cluster::#{type.capitalize}::#{type.capitalize}Generator")
        klass.install_templates
      end
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

    # def service_names_enabled; Settings.platform.services.reject{|s| s.last.enabled.eql? false }.map{ |s| s.first } end
    # def service_names; Settings.platform.services.keys end

    # def tf_root; root.join('devops/terraform') end
    # def ansible_root; root.join('devops/ansible') end
    def helm_root; root.join('devops/helm') end
    def k8s_root; root.join('devops/k8s') end

    def config_dir; "#{Ros.root}/config" end
    def environments_dir; "#{config_dir}/environments" end
    def deployments_dir; "#{config_dir}/deployments" end

    def ros_root; is_ros? ? root : root.join('ros') end

    def has_ros?; not is_ros? and Dir.exists?(ros_root) end

    # TODO: This is a hack in order to differentiate for purpose of templating files
    def is_ros?
      Settings.config.platform.config.image_registry.eql?('railsonservices') and platform.environment.platform.partition_name.eql?('ros')
    end

    def platform; Settings.components.be.components.application.components.platform end
  end
end

Ros.load_env unless Ros.root.nil?
