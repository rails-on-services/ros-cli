# frozen_string_literal: true

module Ros
  module Generators
    module Be
      module Application
        module Services

          class Service
            attr_accessor :name, :config, :environment, :deploy_path
            def initialize(name, definition, deploy_path)
              @name = name
              @config = definition&.dig(:config)
              @environment = definition&.dig(:environment)
              @deploy_path = deploy_path
            end

            def stack_name; Stack.name end
            def current_feature_set; Application.current_feature_set end
            def has_envs; !environment.nil? end

            # skaffold only methods
            def relative_path; @relative_path ||= ('../' * deploy_path.split('/').size).chomp('/') end
            def chart_path; "#{relative_path}/devops/helm/charts/application/services" end
            # api_hostname is for ingress controller
            def api_hostname; Application.api_hostname end
            # def bucket_name; stack.current_feature_set end
            def skaffold_version; Stack.config.skaffold_version end

            # skaffold sftp only methods
            def sftp
              @sftp ||= Config::Options.new({
                secrets_files: environment ? [:services, name.to_sym] : %i(services),
                pull_policy: 'Always',
                hostname: Application.sftp_hostname
              })
            end

            # def self.aws_environment
            #   {
            #     aws_access_key_id: Ros::Generators::Be::Cluster.provider.credentials.access_key_id,
            #     aws_secret_access_key: Ros::Generators::Be::Cluster.provider.credentials.secret_access_key,
            #     aws_default_region: Ros::Generators::Be::Cluster.provider.credentials.region
            #   }
            # end

            # Configuration values for fluentd request logging config file
            def fluentd
              # binding.pry
              # If type is kubernetes, then value of header is:
              # "configMaps:\n  rails-audit-log.conf: |"
              @fluentd ||= Config::Options.new({
                header: cluster.config.type.eql?('kubernetes') ? "configMaps:\n  rails-audit-log.conf: |" : '',
                # log_tag: "#{api_hostname}.rack-traffic-log",
                log_tag: "**.rack-traffic-log",
                fluent_code_from_duan: 'fluent_code_from_duan',
                provider: Settings.components.be.config.provider, # infra.config.provider,
                # storage_name: "storage#{base_hostname.gsub('.', '-')}",
                storage_name: Application.bucket_name,
                storage_region: 'abc', # provider.config.region,
                current_feature_set: Application.current_feature_set
              })
            end
            def cluster; Ros::Generators::Be::Infra::Cluster end
          end

          # Depending on the deployment type, use either compose or skaffold
          # Write out all the service templates that are in that directory
          # unless the name of the service to template was passed in
          class ServicesGenerator < Thor::Group
            include Thor::Actions
            extend CommonGenerator
            add_runtime_options!

            def self.a_path; File.dirname(__FILE__) end

            def environment_file
              content = Ros.format_envs('', environment).join("\n")
              create_file("#{destination_root}/#{deploy_path}/services.env", "#{content}\n")
            end

            def service_files
              empty_directory("#{destination_root}/#{deploy_path}")
              components.each do |service, definition|
                @service = Service.new(service, definition, deploy_path)
                template("#{template_dir}/#{service}.yml.erb", "#{destination_root}/#{deploy_path}/#{service}.yml")
                service_dir = "#{File.dirname(__FILE__)}/templates/services/#{service}"
                if Dir.exists?(service_dir)
                  Dir["#{service_dir}/*"].each do |template_file|
                    next if File.basename(template_file).eql?('nginx.conf.erb')
                    template(template_file, "#{destination_root}/#{deploy_path}/#{service}/#{File.basename(template_file).gsub('.erb', '')}")
                  end
                end
                next unless envs = @service.environment
                content = Ros.format_envs('', envs).join("\n")
                create_file("#{destination_root}/#{deploy_path}/#{service}.env", "#{content}\n")
              end
            end

            def write_nginx
              # empty_directory("#{destination_root}/#{deploy_path}/nginx")
              remove_file("#{destination_root}/#{deploy_path}/nginx/nginx.conf")
              template("services/nginx/nginx.conf.erb", "#{destination_root}/#{deploy_path}/nginx/nginx.conf")
            end

            def generate_support_files
              if Infra.cluster_type.eql?('cluster')
                directory('../files/helm', "#{deploy_path}/helm")
                directory('../files/k8s', "#{deploy_path}/k8s")
              end
            end

            # def write_fluentd
            #   return unless components.keys.include?(:fluentd)
            #   content_dir = "#{core_root}/fluentd"
            #   FileUtils.mkdir_p("#{content_dir}/log")
            #   FileUtils.chmod('+w', "#{content_dir}/log")
            #   FileUtils.mkdir_p("#{content_dir}/etc")
            # end

            private
             
            def nginx_services; @nginx_services ||= (args[0] || platform_service_names) end

            def deploy_path
              "#{Application.deploy_path}/services"
            end

            def environment
              @environment ||= Application.environment.dup.merge!(settings.environment&.to_hash)
            end

            def service_names; components.keys  end

            def platform_service_names; platform_components.keys end

            def platform_components
              platform_settings.components.to_h.select{|k, v| v.nil? || v.dig(:config, :enabled).nil? || v.dig(:config, :enabled) }
            end

            def platform_settings; Application.settings.components.platform end

            def components
              settings.components.to_h.select{|k, v| v.nil? || v.dig(:config, :enabled).nil? || v.dig(:config, :enabled) }
            end

            def settings; Application.settings.components.services end

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
