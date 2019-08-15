# frozen_string_literal: true
# require 'ros/cli_base'
require 'ros/be/generator'
require 'ros/be/application/cli_base'
require 'ros/be/infra/generator'

module Ros
  module Be
    module Infra
      class Cli < Thor
        include CliBase

        check_unknown_options!
        class_option :v, type: :boolean, default: false, desc: 'verbose output'
        class_option :n, type: :boolean, default: false, desc: "run but don't execute action"

        desc 'init', 'Initialize the cluster'
        option :long, type: :boolean, aliases: '-l', desc: 'Run the long form of the command'
        def init
          cluster.init(self)
        end

        desc 'plan', 'Show the terraform infrastructure plan'
        def plan
          generate_config if stale_config
          Dir.chdir(infra.deploy_path) do
            system_cmd(cmd_environment, 'terraform init')
            system_cmd(cmd_environment, 'terraform plan')
          end
        end

        desc 'apply', 'Apply the terraform infrastructure plan'
        def apply
          generate_config if stale_config
          Dir.chdir(infra.deploy_path) do
            system_cmd(cmd_environment, 'terraform init')
            system_cmd(cmd_environment, 'terraform apply')
            system_cmd(cmd_environment, 'terraform output -json > output.json')
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
        # TODO: this needs to be per provider and region comes from deployment.yml
        def cmd_environment
          { 'AWS_DEFAULT_REGION' => 'ap-southeast-1' }
        end

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
          if File.exist?('output.json')
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
        def cluster; Ros::Be::Infra::Cluster::Model end
      end
    end
  end
end
