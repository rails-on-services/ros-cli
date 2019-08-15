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
    def from_rake(task_name, args)
      behavior, *stack = task_name.split(':')
      require 'ros/stack'
      require 'ros/be/application/generator'
      require 'ros/be/infra/generator'
      g_string = "#{stack.map{ |s| s.capitalize }.join('::')}::Generator"
      generator = Ros.const_get(g_string).new
      generator.behavior = behavior.eql?('destroy') ? :revoke : :invoke
      generator.destination_root = Ros.root
      generator.invoke_all
    end

    def install_templates
      %w(services platform).each do |type|
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
          files.append(profile_file) if File.exist?(profile_file)
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
          break Pathname.new(cwd) if File.exist?("#{cwd}/config/deployment.yml")
          cwd = File.expand_path('..', cwd)
        end)
    end

    def gem_root; Pathname.new(File.expand_path('../..', __FILE__)) end

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
