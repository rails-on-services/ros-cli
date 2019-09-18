# frozen_string_literal: true
require 'ros/be/generator'

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

          # skaffold only methods
          def relative_path; @relative_path ||= ('../' * deploy_path.split('/').size).chomp('/') end
          def chart_path; 'helm-charts' end
          # api_hostname is for ingress controller
          def api_hostname; application.api_hostname end
          # def bucket_name; stack.current_feature_set end
          def skaffold_version; Settings.components.be.config.skaffold_version end

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
            # TODO, need to all all avro event log topics and
            [fluentd.http_log_kafka_topic]
          end

          # Configuration values for fluentd request logging config file
          def fluentd
            @fluentd ||= Config::Options.new({
              header: cluster.infra.cluster_type.eql?('kubernetes') ? "configMaps:\n  ros.conf: |" : '',
              include_tcp_source: cluster.infra.cluster_type.eql?('kubernetes') ? false : true,
              current_feature_set: application.current_feature_set,
              http_log_kafka_topic: "http_request_log"
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

          def copy_kubernetes_helm_charts
            return unless infra.cluster_type.eql?('kubernetes')
            directory('../files/helm-charts', "#{deploy_path}/helm-charts")
            FileUtils.mkdir_p("#{destination_root}/#{deploy_path}") unless File.directory?("#{destination_root}/#{deploy_path}")
            FileUtils.cp("#{Ros.environments_dir}/big_query_credentials.json", "#{destination_root}/#{deploy_path}") if File.exists?("#{Ros.environments_dir}/big_query_credentials.json")
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
