# frozen_string_literal: true

require 'ros/be/infra/cluster/services/generator'

module Ros
  module Be
    module Infra
      module Cluster
        module Model
          class << self
            def settings; infra.components[infra.cluster_type] end
            def config; settings.config || {} end
            def environment; settings.environment || {} end
            def deploy_path; "#{infra.deploy_path}/cluster" end
            def provider; Stack.config.infra[config.provider] end
            def name; config.name.nil? ? infra.config.cluster.name : config.name end
            def infra; Infra::Model end

            def init(cli)
              unless infra.cluster_type.eql?('kubernetes')
                STDOUT.puts 'command only applicable to kubernetes deployments'
                return
              end
              send("init_#{config.provider}", cli)
            end

            def init_aws(cli)
              credentials_file = "#{Dir.home}/.aws/credentials"
              unless (File.exist?(credentials_file) or ENV['AWS_ACCESS_KEY_ID'])
                STDOUT.puts "missing #{credentials_file}"
                return
              end
              infra.config.cluster.aws_profile.nil? || ENV['AWS_PROFILE'] || ENV['AWS_DEFAULT_PROFILE'] ? profile = "" : profile = "--profile #{infra.config.cluster.aws_profile}"
              cmd_string = "aws eks update-kubeconfig --name #{name} #{profile}"

              role_name = cli.options.role_name.nil? ? provider.cluster.role_name : cli.options.role_name
              cmd_string = "#{cmd_string} --role-arn arn:aws:iam::#{provider.account_id}:role/#{role_name}" if cli.options.long || cli.options.role_name
              cli.system_cmd(cmd_string)
              cli.errors.add(:update_kube_config, cli.stderr) if cli.exit_code.positive?
              cli.system_cmd('kubectl cluster-info')
              cli.errors.add(:get_cluster_info, cli.stderr) if cli.exit_code.positive?
            end
          end
        end

        class Generator < Thor::Group
          include Thor::Actions
          include Ros::Be::CommonGenerator

          def self.a_path; File.dirname(__FILE__) end

          def execute
            [Service::Generator].each do |klass|
              generator = klass.new
              generator.behavior = behavior
              generator.destination_root = destination_root
              generator.invoke_all
            end
          end
        end
      end
    end
  end
end
