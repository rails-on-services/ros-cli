# frozen_string_literal: true
require 'ros/be/generator'
require 'json'

module Ros
  module Be
    module Application
      module Services

        class Model
          attr_accessor :name, :config, :environment, :deploy_path, :runtime_path
          def initialize(name, definition, deploy_path, runtime_path)
            @name = name
            @config = definition&.dig(:config)
            @environment = definition&.dig(:environment)
            @deploy_path = deploy_path
            @runtime_path = runtime_path
          end

          def stack_name; Stack.name end
          def current_feature_set; application.current_feature_set end
          def has_envs; !environment.nil? end

          def dependency_exclusions
            {
              development: %i[wait sftp],
              test: %i[wait sftp nginx]
            }[Ros.env.to_sym]
          end

          def dependency_environments
            {
              postgres: '5432',
              redis: '6379',
              fluentd: '24224',
              localstack: '4572'
            }
          end

          # skaffold only methods
          def relative_path; @relative_path ||= ('../' * deploy_path.split('/').size).chomp('/') end
          def chart_path; 'helm-charts' end
          # api_hostname is for ingress controller
          def api_hostname; application.api_hostname end
          # def bucket_name; stack.current_feature_set end
          def skaffold_version; Settings.components.be.config.skaffold_version end
          def compose_version; Settings.components.be.config.compose_version || '3.2' end
          def map_ports_to_host; false end
          def expose_ports(port)
            port, proto = port.to_s.split('/')
            host_port = map_ports_to_host ? "#{port}:" : ''
            proto = proto ? "/#{proto}" : ''
            "\"#{host_port}#{port}#{proto}\""
          end

          # skaffold sftp only methods
          def sftp
            @sftp ||= Config::Options.new({
              secrets_files: environment ? [:services, name.to_sym] : %i(services),
              pull_policy: 'Always',
              hostname: application.sftp_hostname
            })
          end

          def kafka_connect
            @kafka_connect ||= application.components.services.components[:'kafka-connect'].config
          end

          def kafka_schema_registry
            @kafka_schema_registry ||= application.components.services.components[:'kafka-schema-registry'].config
          end

          # def self.aws_environment
          #   {
          #     aws_access_key_id: Ros::Generators::Be::Cluster.provider.credentials.access_key_id,
          #     aws_secret_access_key: Ros::Generators::Be::Cluster.provider.credentials.secret_access_key,
          #     aws_default_region: Ros::Generators::Be::Cluster.provider.credentials.region
          #   }
          # end

          def kafka
            @kafka ||=
            if application.components.services.components.kafka&.config&.enabled
              Config::Options.new({
                bootstrap_servers: "kafka:9092"
              })
            elsif application.components.services.components.kafkastack&.config&.enabled
              Config::Options.new({
                bootstrap_servers: "kafkastack:9092"
              })
            else
              application&.config&.external_kafka || Config::Options.new
            end
          end

          # kafka topics involved
          def kafka_topics
            @kafka_topics ||= cloudevents_subjects
          end

          def cloudevents_subjects
            subjects = {}
            platform_components.each do |service, definition|
              ros_prefix = definition.config.ros ? "ros/" : ""
              Dir.glob("#{ros_prefix}services/#{service.to_s}/doc/schemas/cloud_events/#{service.to_s}/*.avsc") do |file|
                json = JSON.parse(File.read(file))
                key = json["name"].split(".").first.to_sym
                (subjects[key] ||=[]) << json["name"]
              end
            end
            subjects
          end

          def platform_components
            application.settings.components.platform.components.to_h.select{|k, v| v.nil? || v.dig(:config, :enabled).nil? || v.dig(:config, :enabled) }
          end

          # bigquery dataset to write data into
          def bigquery_dataset
            @bigquery_dataset ||= application.override_feature_set.empty? ? "warehouse" : "warehouse_" + current_feature_set.gsub(/\W/, '_')
          end

          # Configuration values for fluentd request logging config file
          def fluentd
            @fluentd ||= Config::Options.new({
              header: cluster.infra.cluster_type.eql?('kubernetes') ? "configMaps:\n  ros.conf: |" : '',
              include_input_source: cluster.infra.cluster_type.eql?('kubernetes') ? false : true,
              current_feature_set: application.current_feature_set
            }).merge!((application.components.services.components[:'fluentd'].config)&.to_hash)
          end

          def cluster; Ros::Be::Infra::Cluster::Model end
          def application; Ros::Be::Application::Model end
        end

        # Depending on the deployment type, use either compose or skaffold
        # Write out all the service templates that are in that directory
        # unless the name of the service to template was passed in
        class Generator < Thor::Group
          include Thor::Actions
          include Ros::Be::CommonGenerator
          add_runtime_options!

          def self.a_path; File.dirname(__FILE__) end

          def environment_file
            content = Ros.format_envs('', environment).join("\n")
            content = content.split("\n").sort.select { |a| a.split('=').size > 1 }.join("\n")
            create_file("#{destination_root}/#{deploy_path}/services.env", "#{content}\n")
          end

          def create_fluentd_log_dir_for_compose
            return unless components.keys.include?(:fluentd) and infra.cluster_type.eql?('instance') and behavior.eql?(:invoke)
            empty_directory(runtime_path)
            FileUtils.chmod('+w', runtime_path)
          end

          def runtime_path; "#{deploy_path.gsub('deployments', 'runtime')}/fluentd/log" end

          def service_files
            empty_directory("#{destination_root}/#{deploy_path}")
            base_service_template_dir = "#{File.dirname(__FILE__)}/templates/services"
            base_job_template_dir = "#{File.dirname(__FILE__)}/templates/jobs"
            components.each do |service, definition|
              @service = Model.new(service, definition, deploy_path, runtime_path)
              template("#{template_dir}/#{service}.yml.erb", "#{destination_root}/#{deploy_path}/#{service}.yml")
              service_template_dir = "#{base_service_template_dir}/#{service}"
              if Dir.exists?(service_template_dir)
                Dir["#{service_template_dir}/**/*"].reject{ |fn| File.directory?(fn) }.each do |template_file|
                  # skip if it exists as an instance method on this class as it will be invoked by thor automatically
                  next if respond_to?(File.basename(template_file).gsub('.', '_').chomp('_erb').to_sym)
                  destination_file = "#{destination_root}/#{deploy_path}/#{template_file.gsub("#{base_service_template_dir}/", '')}".chomp('.erb')
                  template(template_file, destination_file)
                end
              end

              # Generate K8s jobs
              job_template_dir = "#{base_job_template_dir}/#{service}"
              if infra.cluster_type.eql?('kubernetes') and Dir.exists?(job_template_dir)
                Dir["#{job_template_dir}/**/*"].reject{ |fn| File.directory?(fn) }.each do |template_file|
                  destination_file = "#{destination_root}/#{deploy_path}/jobs/#{service}/#{template_file.gsub("#{job_template_dir}/", '')}".chomp('.erb')
                  template(template_file, destination_file)
                end
              end

              next unless envs = @service.environment
              content = Ros.format_envs('', envs).join("\n")
              create_file("#{destination_root}/#{deploy_path}/#{service}.env", "#{content}\n")
            end
          end

          def nginx_conf
            return unless infra.cluster_type.eql?('instance')
            # empty_directory("#{destination_root}/#{deploy_path}/nginx")
            remove_file("#{destination_root}/#{deploy_path}/nginx/nginx.conf")
            template("services/nginx/nginx.conf.erb", "#{destination_root}/#{deploy_path}/nginx/nginx.conf")
          end

          def copy_kubernetes_files
            return unless infra.cluster_type.eql?('kubernetes')
            directory('../files/kubernetes', "#{deploy_path}/kubernetes")
          end

          private

          def nginx_services; @nginx_services ||= (args[0] || platform_service_names) end

          def deploy_path
            "#{application.deploy_path}/services"
          end

          def environment
            @environment ||= application.environment.dup.merge!(settings.environment&.to_hash)
          end

          def service_names; components.keys  end

          def platform_service_names; platform_components.keys end

          def platform_components
            platform_settings.components.to_h.select{|k, v| v.nil? || v.dig(:config, :enabled).nil? || v.dig(:config, :enabled) }
          end

          def platform_settings; application.settings.components.platform end

          def components
            settings.components.to_h.select{|k, v| v.nil? || v.dig(:config, :enabled).nil? || v.dig(:config, :enabled) }
          end

          def settings; application.settings.components.services end

          def template_dir
            infra.cluster_type.eql?('kubernetes') ? 'skaffold' : 'compose'
          end
        end
      end
    end
  end
end
