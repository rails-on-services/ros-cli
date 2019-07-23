# frozen_string_literal: true
require 'ros/ops/cli_common'
require 'ros/generators/be/cluster'

module Ros
  module Ops
    module Infra
      class Cli
        include Ros::Ops::CliCommon

        def generate
          Dir.chdir("#{Ros::Generators::Be::Cluster.deploy_path}/infra") do
            # TODO: Refactor to do a check to generate the infrastructure templates
            # generate_config if stale_config
            system_cmd({}, 'terraform init')
            system_cmd({}, 'terraform plan') unless options.apply
            system_cmd({}, 'terraform apply') if options.apply
          end
        end

        def destroy
          Dir.chdir("#{Ros::Generators::Be::Cluster.deploy_path}/infra") do
            system_cmd({}, 'terraform destroy')
          end
        end
      end
    end
  end
end
