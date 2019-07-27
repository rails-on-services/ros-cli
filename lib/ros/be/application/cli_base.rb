# frozen_string_literal: true
require 'thor'
require 'ros/stack'
require 'ros/cli_base'
# require 'ros/generators/be/application/services/services_generator'
# require 'ros/generators/be/application/platform/platform_generator'

module Ros
  module Be
    module Application
      module CliBase
        include Ros::CliBase
        attr_accessor :options

        def show(service_name)
          service = service_name.split('/')[0]
          service_name = "#{service_name}.yml" unless service_name.index('.')
          %w(services platform).each do |type|
            keys = application.components[type].components.keys
            next unless keys.include?(service.to_sym)
            file = "#{application.deploy_path}/#{type}/#{service_name}"
            STDOUT.puts File.read(file)
          end
        end

        def show_endpoint
          STDOUT.puts "\n*** Services available at #{application.api_uri} ***\n\n"
        end

        def enabled_services
          application.components.platform.components.to_hash.select do |k, v|
            v.nil? || v.dig(:config, :enabled).nil? || v.dig(:config, :enabled)
          end.keys
        end

        def enabled_services_f
          application.components.services.components.to_hash.select do |k, v|
            v.nil? || v.dig(:config, :enabled).nil? || v.dig(:config, :enabled)
          end.keys
        end
      end
    end
  end
end
