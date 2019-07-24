# frozen_string_literal: true
require 'ros/generators/be/infra/infra_generator'

module Ros
  module Be
    module Infra
      class Cli
        include Ros::Be::Common::Cli

        # TODO: This is maybe a standalone CLI rather than a subcommand of be
        def show(type = 'json')
          Dir.chdir(infra.deploy_path) do
            show_json
          end
        end

        def show_json
          if File.exists?('output.json')
            json = JSON.parse(File.read('output.json'))
            if json['ec2']
              ip = json['ec2']['value']['public_ip']
              STDOUT.puts "ssh admin@#{ip}"
            end
          end
        end

        def generate
          Dir.chdir(infra.deploy_path) do
            # TODO: Refactor to do a check to generate the infrastructure templates
            # generate_config if stale_config
            system_cmd({}, 'terraform init')
            system_cmd({}, 'terraform plan') unless options.apply
            system_cmd({}, 'terraform apply') if options.apply
            system_cmd({}, 'terraform output -json > output.json') if options.apply
            show_json
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
