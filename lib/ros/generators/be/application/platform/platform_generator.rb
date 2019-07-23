# frozen_string_literal: true

module Ros
  module Generators
    module Be
      module Application
        module Platform

          class Service
            attr_accessor :name, :config, :environment, :deploy_path
            def initialize(name, definition, deploy_path)
              @name = name
              @config = definition.dig(:config)
              @environment = definition.dig(:environment)
              @deploy_path = deploy_path
            end

            def use_ros_context_dir; (not Ros.is_ros? and config.ros) end
            def context_dir; use_ros_context_dir ? 'ROS_CONTEXT_DIR' : 'CONTEXT_DIR' end
            def has_envs; !environment.nil? end
            # NOTE: Update image_type
            def image; Settings.config.platform.images.rails end
            def mount_ros; (not Ros.is_ros? and not config.ros) end
            def profiles; config.profiles || [] end

            def stack_name; Stack.name end
            def current_feature_set; Application.current_feature_set end

            # skaffold only methods
            def relative_path; @relative_path ||= ('../' * deploy_path.split('/').size).chomp('/') end
            def context_path; "#{relative_path}#{config.ros ? '/ros' : ''}" end
            def dockerfile_path; "#{relative_path}/#{config.ros ? 'ros/' : ''}Dockerfile" end
            def chart_path; "#{relative_path}/devops/helm/charts/service" end
            def is_ros_service; config.ros end
            def pull_policy; 'Always' end
            def pull_secret; Stack.registry_secret_name end
            def secrets_files; environment ? [:platform, name.to_sym] : %i(platform) end
            def skaffold_version; Stack.config.skaffold_version end
          end

          class PlatformGenerator < Thor::Group
            include Thor::Actions
            extend CommonGenerator
            add_runtime_options!

            def self.a_path; File.dirname(__FILE__) end

            def service_files
              empty_directory("#{destination_root}/#{deploy_path}")
              components.each do |service, definition|
                @service = Service.new(service, definition, deploy_path)
                template("#{template_dir}/service.yml.erb", "#{destination_root}/#{deploy_path}/#{service}.yml")
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
              return unless cluster.config.type.eql?('instance')
              content = compose_environment.each_with_object([]) do |kv, ary|
                ary << "#{kv[0].upcase}=#{kv[1]}"
              end.join("\n")
              content = "# This file was auto generated\n# The values are used by docker-compose\n# #{Ros.env}\n#{content}"
              # empty_directory(Ros::Generators::Stack.compose_dir)
              create_file(Application.compose_file, "#{content}\n")
            end

            def write_nginx
              return unless cluster.config.type.eql?('instance')
              ServicesGenerator.new([], {}, { behavior: behavior }).invoke(:write_nginx)
            end

            private

            # continue compose only methods
            def compose_environment
              {
                compose_file: Dir["#{Application.deploy_path}//**/*.yml"].map{ |p| p.gsub("#{Ros.root}/", '') }.sort.join(':'),
                compose_project_name: Application.compose_project_name,
                context_dir: relative_path,
                ros_context_dir: "#{relative_path}/ros",
                image_repository: Settings.platform.config.image_registry,
                image_tag: Stack.image_tag
              }
            end

            def relative_path; @relative_path ||= ('../' * deploy_path.split('/').size).chomp('/') end
            # end compose only methods

            def environment
              @environment ||= Application.environment.dup.merge!(settings.environment.to_hash)
            end

            def config
              @config ||= Stack.config.dup.merge!(Application.config.dup.merge!(settings.config.to_hash).to_hash)
            end

            def deploy_path
              "#{Application.deploy_path}/platform"
            end

            def services_components
              services_settings.components.to_h.select{|k, v| v.nil? || v.dig(:config, :enabled).nil? || v.dig(:config, :enabled) }
            end

            def services_settings; Application.settings.components.services end

            def components
              settings.components.to_h.select{|k, v| v.dig(:config, :enabled).nil? || v.dig(:config, :enabled) }
            end

            def settings; Application.settings.components.platform end

            def template_dir
              cluster.config.type.eql?('kubernetes') ? 'skaffold' : 'compose'
            end

            def cluster; Ros::Generators::Be::Infra::Cluster end
          end
        end
      end
    end
  end
end
