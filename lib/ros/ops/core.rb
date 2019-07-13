# frozen_string_literal: true

module Ros
  module Ops
    module Core
      # Write the configuration files, e.g. skaffold, compose, etc
      def setup
        FileUtils.rm_rf(core_root)
        FileUtils.mkdir_p(core_root)
        write_core_envs
        write_service_templates
        write_service_content
      end

      def core_root; "#{deploy_root}/core" end

      def write_core_envs
        # envs = core.environment.dup.merge!(environment)
        envs = environment
        content = Ros.format_envs('', envs).join("\n")
        File.write("#{core_root}/core.env", "#{content}\n")
      end

      # Common environment for core services
      def environment
        Config::Options.new().merge!({
          # ros_name: core.config.name,
          # core.config.name => {
          core: {
            infra: {
              provider: infra.config.provider
            },
            feature_set: current_feature_set,
            services: {
              storage: {
                # bucket_endpoint_url: 'http://localstack:4572',
                bucket_name: bucket_name,
                bucket_root: current_feature_set
              }
            }
          }
        }).merge!(send("#{infra.config.provider}_environment"))
      end

      def aws_environment
        {
          aws_access_key_id: provider.config.credentials.access_key_id,
          aws_secret_access_key: provider.config.credentials.secret_access_key,
          aws_default_region: provider.config.credentials.region
        }
      end

      def write_service_templates
        core.services.each do |name, config|
          next if config&.enabled.eql? false
          content = File.read("#{template_root}/#{name}.yml.erb")
          content = ERB.new(content).result_with_hash(template_hash(name))
          File.write("#{core_root}/#{name}.yml", "#{content}\n")
          if envs = core.services.dig(name, :environment) or respond_to?("#{name}_envs".to_sym)
            ienvs = respond_to?("#{name}_envs".to_sym) ? send("#{name}_envs") : {}
            ienvs.merge!(envs || {})
            content = Ros.format_envs('', ienvs).join("\n")
            File.write("#{core_root}/#{name}.env", "#{content}\n")
          end
        end
      end

      # NOTE: Implemented by instance
      def write_service_content
        core.services.each do |name, config|
          next if config&.enabled.eql? false
          send("write_#{name}") if respond_to? "write_#{name}".to_sym
        end
      end

      def sftp_envs
        envs = Config::Options.new({
          bucket_name: bucket_name,
          bucket_prefix: "#{current_feature_set}/storage/"
        })
        envs.merge!(core.services.sftp.environment.to_h) if core.services.sftp&.environment
        envs
      end

      def write_fluentd
        content = File.read("#{template_services_root}/fluentd/requests.conf.erb")
        content = ERB.new(content).result_with_hash(fluentd_env)
        content_dir = "#{core_root}/fluentd"
        FileUtils.mkdir_p("#{content_dir}/log")
        FileUtils.chmod('+w', "#{content_dir}/log")
        FileUtils.mkdir_p("#{content_dir}/etc")
        File.write("#{content_dir}/etc/requests.conf", content)
      end

      def fluentd_env
        {
          header: fluentd_header,
          # log_tag: "#{api_hostname}.rack-traffic-log",
          log_tag: "**.rack-traffic-log",
          fluent_code_from_duan: 'test',
          provider: infra.config.provider,
          # storage_name: "storage#{base_hostname.gsub('.', '-')}",
          storage_name: bucket_name,
          storage_region: provider.config.region,
          current_feature_set: current_feature_set
        }
      end
      def fluentd_header; '' end
    end
  end
end
