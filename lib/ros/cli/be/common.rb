# frozen_string_literal: true
require 'thor'
require 'ros/generators/stack'
require 'ros/generators/be/application/services/services_generator'
require 'ros/generators/be/application/platform/platform_generator'
require 'ros/cli/be/rails'

module Ros
  module Ops
    module CliCommon
      attr_accessor :options

      def initialize(options = {})
        @options = options
      end

      def show(service_name)
        service = service_name.split('/')[0]
        service_name = "#{service_name}.yml" unless service_name.index('.')
        %w(services platform).each do |type|
          keys = application.components[type].components.keys
          next unless keys.include?(service.to_sym)
          file = "#{Ros::Generators::Be::Application.deploy_path}/#{type}/#{service_name}"
          STDOUT.puts File.read(file)
        end
      end

      def show_endpoint
        STDOUT.puts "\n*** Services available at #{application.api_uri} ***\n\n"
      end

      def enabled_services
        Settings.components.be.components.application.components.platform.components.to_hash.select do |k, v|
          v.nil? || v.dig(:config, :enabled).nil? || v.dig(:config, :enabled)
        end.keys
      end

      def system_cmd(env = {}, cmd)
        puts cmd if options.v
        system(env, cmd) unless options.n
      end

      def stale_config
        return true unless File.exists?(application.compose_file)
        mtime = File.mtime(application.compose_file)
        # Check config files
        Dir["#{Ros.root}/config/**/*.yml"].each { |f| return true if mtime < File.mtime(f) }
        # Check template files
        Dir["#{Pathname.new(File.dirname(__FILE__)).join('../generators')}/be/{application,cluster}/**/templates/**/*"].each { |f| return true if mtime < File.mtime(f) }
        # Check custom templates
        Dir["#{Ros.root.join('lib/generators')}/be/{application,cluster}/**/templates/**/*"].each { |f| return true if mtime < File.mtime(f) }
        false
      end

      def application; Ros::Generators::Be::Application end

      def generate_config
        unless options.v
          rs = $stdout
          $stdout = StringIO.new
        end
        Ros::Generators::Be::Application::Services::ServicesGenerator.new([], {}, {behavior: :revoke}).invoke_all
        Ros::Generators::Be::Application::Services::ServicesGenerator.new.invoke_all
        Ros::Generators::Be::Application::Platform::PlatformGenerator.new([], {}, {behavior: :revoke}).invoke_all
        Ros::Generators::Be::Application::Platform::PlatformGenerator.new.invoke_all
        $stdout = rs unless options.v
      end
    end
  end
end
