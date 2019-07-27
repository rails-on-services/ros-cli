# frozen_string_literal: true
require 'ros/be/application/cli/common'
require 'ros/be/infra/generator'

module Ros
  module Be
    module Infra
      class Cli < Thor
        include Ros::Be::Application::Common
        check_unknown_options!
        class_option :v, type: :boolean, default: false, desc: 'verbose output'
        class_option :n, type: :boolean, default: false, desc: "run but don't execute action"

        desc 'plan', 'Show the terraform infrastructure plan'
        def plan
          generate_config if stale_config
          Dir.chdir(infra.deploy_path) do
            system_cmd({}, 'terraform init')
            system_cmd({}, 'terraform plan')
          end
        end

        desc 'apply', 'Apply the terraform infrastructure plan'
        def apply
          generate_config if stale_config
          Dir.chdir(infra.deploy_path) do
            system_cmd({}, 'terraform init')
            system_cmd({}, 'terraform apply')
            system_cmd({}, 'terraform output -json > output.json')
            show_json
          end
        end

        desc 'show', 'Show infrastructure details'
        def show(type = 'json')
          Dir.chdir(infra.deploy_path) do
            show_json
          end
        end

        desc 'destory', 'Destroy infrastructure'
        def destroy
          Dir.chdir(infra.deploy_path) do
            system_cmd({}, 'terraform destroy')
          end
        end

        private
        def config_files
          Dir["#{Ros.root.join(infra.deploy_path)}/*.tf"]
        end

        def generate_config
          silence_output do
            Ros::Be::Infra::Generator.new([], {}, {behavior: :revoke}).invoke_all
            Ros::Be::Infra::Generator.new.invoke_all
          end
        end

        def show_json
          if File.exists?('output.json')
            json = JSON.parse(File.read('output.json'))
            # TODO: This will need to change for two things:
            # 1. when deploying to cluster these values will be different
            # 2. when deploying to another provider these keys will be different
            if json['ec2-eip']
              ip = json['ec2-eip']['value']['public_ip']
              STDOUT.puts "ssh -A admin@#{ip}"
            end
            if json['lb_route53_record']
              STDOUT.puts "API endpoint: #{json['lb_route53_record']['value'][0]['fqdn']}"
            end
          end
        end

        def infra; Ros::Be::Infra::Model end
      end
    end
  end
end
