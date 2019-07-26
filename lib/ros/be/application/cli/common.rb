# frozen_string_literal: true
require 'thor'
require 'ros/stack'
# require 'ros/generators/be/application/services/services_generator'
# require 'ros/generators/be/application/platform/platform_generator'

module Ros
  module Be
    module Application
      module Common
        attr_accessor :options

        def test_for_project
          raise Error, set_color("ERROR: Not a Ros project", :red) if Ros.root.nil?
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
          return true if config_files.empty?
          mtime = config_files.map{ |f| File.mtime(f) }.min
          # Check config files
          Dir["#{Ros.root}/config/**/*.yml"].each { |f| return true if mtime < File.mtime(f) }
          # Check template files
          Dir["#{Ros.gem_root.join('lib/ros/generators')}/be/**/{templates,files}/**/*"].each do |f|
            return true if mtime < File.mtime(f)
          end
          # Check custom templates
          Dir["#{Ros.root.join('lib/generators')}/be/**/{templates,files}/**/*"].each do |f|
            return true if mtime < File.mtime(f)
          end
          false
        end

        def config_files; raise NotImplementedError end
        def generate_config; raise NotImplementedError end

        def silence_output
          unless options.v
            rs = $stdout
            $stdout = StringIO.new
          end
          yield
          $stdout = rs unless options.v
        end
      end
    end
  end
end
