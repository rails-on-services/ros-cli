# frozen_string_literal: true
require 'ros/be/generator'

module Ros
  module Be
    module Application
      module Platform
        module Model
          class << self
            def settings; Settings.components.be.components.application.components.platform end
            def config; settings.config end
            def components; settings.components end
          end
        end

        class Service
          attr_accessor :name, :config, :environment, :deploy_path
          def initialize(name, definition, deploy_path)
            @name = name
            @config = definition.dig(:config)
            @environment = definition.dig(:environment)
            @deploy_path = deploy_path
          end

          def tag; config&.tag || 'latest' end
          def repository; config&.repository || name end
          def profile; config&.profile || name end
          def ports; config&.ports || [] end
          def use_ros_context_dir; (not Ros.is_ros? and config.ros) end
          def context_dir; use_ros_context_dir ? 'ROS_CONTEXT_DIR' : 'CONTEXT_DIR' end
          def has_envs; !environment.nil? end
          def env_files
            ary = []
            ary.append('../platform/platform.env')
            ary.append('../platform/credentials.env') if File.exist?("#{deploy_path}/credentials.env")
            ary.append("../platform/#{name}.env") if has_envs
            ary
          end
          # NOTE: Update image_type
          def image; Stack.config.platform.config.images.rails end
          def mount_ros; (not Ros.is_ros? and not config.ros) end
          def profiles; config&.profiles || [] end

          def stack_name; Stack.name end
          def current_feature_set; Ros::Be::Application::Model.current_feature_set end

          # skaffold only methods
          def relative_path; @relative_path ||= ('../' * deploy_path.split('/').size).chomp('/') end
          def context_path; "#{relative_path}#{config.ros ? '/ros' : ''}" end
          # NOTE: from skaffold v0.36.0 the dockerfile_path is relative to context_path
          # leaving this in in case the behvior reverts back
          # def dockerfile_path; "#{relative_path}/#{config.ros ? 'ros/' : ''}Dockerfile" end
          def dockerfile_path; 'Dockerfile' end
          def compose_version; Settings.components.be.config.compose_version end
          def chart_path; 'helm-charts/service' end
          def is_ros_service; config.ros end
          def pull_policy; 'Always' end
          def pull_secret; Stack.registry_secret_name end
          def secrets_files; environment ? [:platform, name.to_sym] : %i(platform) end
          def skaffold_version; Settings.components.be.config.skaffold_version end
        end

        class Generator < Thor::Group
          include Thor::Actions
          include Ros::Be::CommonGenerator
          add_runtime_options!

          def self.a_path; File.dirname(__FILE__) end

          def service_files
            empty_directory("#{destination_root}/#{deploy_path}")
            components.each do |service, definition|
              @service = Service.new(service, definition, deploy_path)
              # The default template type is config.type or else look for 'service.yml.erb'
              template_type = definition.dig(:config, :type) || 'service'
              template("#{template_dir}/#{template_type}.yml.erb", "#{destination_root}/#{deploy_path}/#{service}.yml")
              next unless envs = @service.environment
              content = Ros.format_envs('', envs).join("\n")
              create_file("#{destination_root}/#{deploy_path}/#{service}.env", "#{content}\n")
            end
          end

          def environment_file
            content = Ros.format_envs('', environment).join("\n")
            create_file("#{destination_root}/#{deploy_path}/platform.env", "#{content}\n")
          end

          # Compose only methods
          def write_compose_envs
            return unless infra.cluster_type.eql?('instance')
            content = compose_environment.each_with_object([]) do |kv, ary|
              ary << "#{kv[0].upcase}=#{kv[1]}"
            end.join("\n")
            content = "# This file was auto generated\n# The values are used by docker-compose\n# #{Ros.env}\n#{content}"
            # empty_directory(Ros::Generators::Stack.compose_dir)
            create_file(application.compose_file, "#{content}\n")
          end

          def copy_kubernetes_helm_charts
            return unless infra.cluster_type.eql?('kubernetes')
            directory('../files/helm-charts', "#{deploy_path}/helm-charts")
          end

          def write_nginx
            return unless infra.cluster_type.eql?('instance')
            Ros::Be::Application::Services::Generator.new([], {}, { behavior: behavior }).invoke(:nginx_conf)
          end

          private

          # continue compose only methods
          def compose_environment
            ext_info = OpenStruct.new
            if (RbConfig::CONFIG['host_os'] =~ /linux/ and Etc.getlogin)
              shell_info = Etc.getpwnam(Etc.getlogin)
              ext_info.puid = shell_info.uid
              ext_info.pgid = shell_info.gid
            end
            {
              compose_file: Dir["#{application.deploy_path}/**/*.yml"].map{ |p| p.gsub("#{Ros.root}/", '') }.sort.join(':'),
              compose_project_name: application.compose_project_name,
              context_dir: relative_path,
              ros_context_dir: "#{relative_path}/ros",
              image_repository: Stack.config.platform.config.image_registry,
              image_tag: Stack.image_tag
            }.merge(ext_info.to_h)
          end

          def relative_path; @relative_path ||= ('../' * deploy_path.split('/').size).chomp('/') end
          # end compose only methods

          def environment
            @environment ||= application.environment.dup.merge!(settings.environment.to_hash).merge!(
              { platform: { hosts: application.api_hostname } }
            )
          end

          def config
            @config ||= Stack.config.dup.merge!(application.config.dup.merge!(settings.config.to_hash).to_hash)
          end

          def deploy_path
            "#{application.deploy_path}/platform"
          end

          def services_components
            services_settings.components.to_h.select{|k, v| v.nil? || v.dig(:config, :enabled).nil? || v.dig(:config, :enabled) }
          end

          def services_settings; application.settings.components.services end

          def components
            settings.components.to_h.select{|k, v| v.dig(:config, :enabled).nil? || v.dig(:config, :enabled) }
          end

          def settings; application.settings.components.platform end

          def template_dir
            infra.cluster_type.eql?('kubernetes') ? 'skaffold' : 'compose'
          end

          # def cluster; Ros::Be::Infra::Model end
          # def cluster; Ros::Be::Infra::Cluster::Model end
          # def application; Ros::Be::Application::Model end
        end
      end
    end
  end
end
