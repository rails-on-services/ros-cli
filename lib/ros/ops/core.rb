# frozen_string_literal: true

module Ros
  module Ops
    module Core
      # Write the configuration files, e.g. skaffold, compose, etc
      def setup
        FileUtils.rm_rf(core_root)
        FileUtils.mkdir_p(core_root)
        write_service_templates
        write_service_content
      end

      def core_root; "#{deploy_root}/core" end

      def write_service_templates
        core.services.each do |name, config|
          next if config&.enabled.eql? false
          content = File.read("#{template_root}/#{name}.yml.erb")
          content = ERB.new(content).result_with_hash(template_hash(name))
          File.write("#{core_root}/#{name}.yml", "#{content}\n")
          if envs = core.services.dig(name, :environment)
            content = Ros.format_envs('', envs).join("\n")
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
          log_tag: "#{api_hostname}.rack-traffic-log",
          provider: infra.config.provider,
          config: {
            # TODO: bucket name comes from the deployment
            bucket: "#{api_hostname}-#{core.services.dig(:fluentd, :config, :bucket)}",
            # region: infra.aws_region
            region: provider.region
          }
        }
      end
      def fluentd_header; '' end
    end
  end
end
