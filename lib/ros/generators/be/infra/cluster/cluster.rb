# frozen_string_literal: true
require 'ros/generators/stack'

module Ros
  module Generators
    module Be
      module Cluster
        class << self
          def settings; Settings.components.be.components.cluster end
          def config; settings.config || {} end
          def environment; settings.environment || {} end
          def deploy_path; "#{Stack.deploy_path}/be/cluster" end
          def provider; Settings.infra.config.providers[Settings.components.be.config.provider] end
          def name; config.name end

          def init_aws(cli)
            # TODO: raise error if ~/.aws/credentials doesn't exist
            cmd_string = "aws eks update-kubeconfig --name #{name}"
            cmd_string = "#{cmd_string} --role-arn arn:aws:iam::#{provider.account_id}:role/#{provider.cluster.role_name}" if cli.options.long
            cli.system_cmd({}, cmd_string)
            cli.system_cmd({}, 'kubectl cluster-info')
          end
        end
      end
    end
  end
end
