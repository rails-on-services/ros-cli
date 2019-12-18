# frozen_string_literal: true

require 'ros/be/generator'

module Ros
  module Be
    module Infra
      module Cluster
        module Service
          class Model
            attr_accessor :name, :config, :environment

            def initialize(name, definition)
              @name = name
              @config = definition&.dig(:config)
              @environment = definition&.dig(:environment)
            end
          end

          class Generator < Thor::Group
            include Thor::Actions
            include Ros::Be::CommonGenerator

            def self.a_path; File.dirname(__FILE__) end

            def generate_service_files
              empty_directory("#{destination_root}/#{deploy_path}")
              components.each do |service, definition|
                @service = Model.new(service, definition)
                template("#{template_dir}/#{service}.yml.erb", "#{destination_root}/#{deploy_path}/#{service}.yml")
                service_dir = "#{File.dirname(__FILE__)}/templates/services/#{service}"
                next unless Dir.exist?(service_dir)

                Dir["#{service_dir}/*"].each do |template_file|
                  template(template_file, "#{destination_root}/#{deploy_path}/#{service}/#{File.basename(template_file).gsub('.erb', '')}")
                end
              end
            end

            private

            def environment
              @environment ||= Stack.environment.dup.merge!(cluster.environment.dup.merge!(settings.environment.to_hash).to_hash)
            end

            def config
              @config ||= Stack.config.dup.merge!(cluster.config.dup.merge!(settings.config.to_hash).to_hash)
            end

            def deploy_path
              # TODO: For fluentd, grafana and prometheus, where do the templates go?
              "#{cluster.deploy_path}/services"
            end

            def components
              settings.components.to_h.select { |_k, v| v.nil? || v.dig(:config, :enabled).nil? || v.dig(:config, :enabled) }
            end

            def settings; cluster.settings.components&.services || Config::Options.new end

            # def environment ; settings.environment end
            def template_dir
              cluster.config.type.eql?('kubernetes') ? 'skaffold' : 'compose'
            end
          end
        end
      end
    end
  end
end
