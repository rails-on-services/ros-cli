# frozen_string_literal: true

require 'ros/generators/be/infra/cluster/services/services_generator'

module Ros
  module Generators
    module Be
      module Infra
        module Cluster
          class << self
            def settings; Settings.components.be.components.infra.components[Infra.cluster_type] end
            def config; settings.config || {} end
            def environment; settings.environment || {} end
            def deploy_path; "#{Infra.deploy_path}/cluster" end
            def provider; Infra.config.providers[config.provider] end
            def name; config.name end

            def init(cli); send("init_#{config.provider}", cli) end

            def init_aws(cli)
              # TODO: raise error if ~/.aws/credentials doesn't exist
              cmd_string = "aws eks update-kubeconfig --name #{name}"
              cmd_string = "#{cmd_string} --role-arn arn:aws:iam::#{provider.account_id}:role/#{provider.cluster.role_name}" if cli.options.long
              cli.system_cmd({}, cmd_string)
              cli.system_cmd({}, 'kubectl cluster-info')
            end
          end

          class ClusterGenerator < Thor::Group
            include Thor::Actions
            extend CommonGenerator

            def self.a_path; File.dirname(__FILE__) end

            def execute
              [Cluster::ServicesGenerator].each do |klass|
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
end
