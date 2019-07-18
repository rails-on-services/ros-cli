# frozen_string_literal: true
require 'ros/generators/be/application/services/services_generator'
require 'ros/generators/be/application/platform/platform_generator'

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

      # TODO: implement
      def gem_version_check
        require 'bundler'
        errors = services.each_with_object([]) do |service, errors|
          config = service.last
          next if config&.enabled.eql? false
          check = image_gems_version_check(service)
          errors.append({ image: service.first, mismatches: check }) if check.size.positive?
        end
        if errors.size.positive?
          if config.force
            STDOUT.puts 'Gem version mismatch. -f used to force'
          else
            STDOUT.puts 'Gem version mismatch. Bundle update or use -f to force (build will be slower)'
            STDOUT.puts "\n#{errors.join("\n")}"
            return
          end
        end
        true
      end

      def image_gems_version_check(service)
        image = service.first
        root_dir = service.last.dig(:ros) ? "#{Ros.root}/ros" : Ros.root
        service_dir = "#{root_dir}/services/#{image}"
        definition = nil
        Dir.chdir(service_dir) do
          definition = Bundler::Definition.build('Gemfile', 'Gemfile.lock', nil)
        end
        gems = definition.requested_specs.select{ |s| images.static_gems.keys.include?(s.name.to_sym) }
        gems.each_with_object([]) do |gemfile_gem, errors|
          gemfile_version = gemfile_gem.version
          image_version = Gem::Version.new(images.static_gems[gemfile_gem.name.to_sym])
          next if gemfile_version.eql?(image_version)
          errors << { image: image, name: gemfile_gem.name, image_version: image_version.to_s, gemfile_version: gemfile_version.to_s }
        end
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
        # TODO: Add path to custom templates
        Dir["#{Pathname.new(File.dirname(__FILE__)).join('../generators')}/be/{application,cluster}/**/templates/**/*"].each { |f| return true if mtime < File.mtime(f) }
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
