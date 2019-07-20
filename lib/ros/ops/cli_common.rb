# frozen_string_literal: true
require 'ros/generators/be/application/services/services_generator'
require 'ros/generators/be/application/platform/platform_generator'
require 'ros/ops/rails'

module Ros
  module Ops
    module CliCommon
      attr_accessor :options

      def initialize(options = {})
        @options = options
      end

      def enabled_services
        Settings.components.be.components.application.components.platform.components.to_hash.select do |k, v|
          v.nil? || v.dig(:config, :enabled).nil? || v.dig(:config, :enabled)
        end.keys
      end

      # Standup infra via Terraform: k8s, minikube or instance
      # TODO: Define the workdir; this is where tfvars files are written and from where the commands will be applied
      # NOTE: The TF infra code will live in a different (generated) directory
      def apply
        Dir.chdir(workdir) do
          system('terraform init')
          system('terraform apply')
        end
        after_apply
      end

      def after_apply; end

      # Destroy the infrastructure
      def destroy
        Dir.chdir(workdir) do
          system_cmd('terraform destroy')
        end
      end

      def system_cmd(env = {}, cmd)
        puts cmd if options.v
        system(env, cmd) unless options.n
      end

      def stale_config
        return true unless File.exists?(Ros::Generators::Stack.compose_file)
        mtime = File.mtime(Ros::Generators::Stack.compose_file)
        # Check config files
        Dir["#{Ros.root}/config/**/*.yml"].each { |f| return true if mtime < File.mtime(f) }
        # Check template files
        Dir["#{Pathname.new(File.dirname(__FILE__)).join('../generators')}/be/{application,cluster}/**/templates/**/*"].each { |f| return true if mtime < File.mtime(f) }
        # Check custom templates
        Dir["#{Ros.root.join('lib/generators')}/be/{application,cluster}/**/templates/**/*"].each { |f| return true if mtime < File.mtime(f) }
        false
      end

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
