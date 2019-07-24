# frozen_string_literal: true
require 'ros/generators/be/infra/infra_generator'

module Ros
  module Be
    module Infra
      class Cli
        include Ros::Be::Common::Cli

        def generate
          Dir.chdir(infra.deploy_path) do
            # TODO: Refactor to do a check to generate the infrastructure templates
            # generate_config if stale_config
            system_cmd({}, 'terraform init')
            system_cmd({}, 'terraform plan') unless options.apply
            system_cmd({}, 'terraform apply') if options.apply
          end
        end

        def destroy
          Dir.chdir(infra.deploy_path) do
            system_cmd({}, 'terraform destroy')
          end
        end

        private
        def infra; Ros::Generators::Be::Infra end
      end
    end
  end
end
