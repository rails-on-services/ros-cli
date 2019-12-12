# frozen_string_literal: true
# require 'ros/cli_base'
require 'ros/be/generator'
require 'ros/be/application/cli_base'
require 'ros/be/data/generator'

module Ros
  module Be
    module Data
      class Cli < Thor
        include CliBase

        check_unknown_options!
        class_option :v, type: :boolean, default: true, desc: 'verbose output'
        class_option :n, type: :boolean, default: false, desc: "run but don't execute action"

        def initialize(*args)
          @errors = Ros::Errors.new
          super
        end

        desc 'plan', 'Show the terraform metabase plan'
        option :cl, type: :boolean, aliases: '--clear', desc: 'Clear local modules cache. Force to download latest modules from TF registry'
        def plan
          generate_config if stale_config
          Dir.chdir(data.deploy_path) do
            system_cmd('rm -rf .terraform/modules/') if options.cl
            system_cmd('terraform init', cmd_environment)
            system_cmd('terraform plan', cmd_environment)
          end
        end

        desc 'apply', 'Apply the terraform infrastructure plan'
        option :cl, type: :boolean, aliases: '--clear', desc: 'Clear local modules cache. Force to download latest modules from TF registry'
        def apply
          generate_config if stale_config
          Dir.chdir(data.deploy_path) do
            system_cmd('rm -rf .terraform/modules/') if options.cl
            system_cmd('rm -f .terraform/terraform.tfstate')
            system_cmd('terraform init', cmd_environment)
            system_cmd('terraform apply', cmd_environment)
            system_cmd('terraform output -json > output.json', cmd_environment)
            show_json
          end
        end

        desc 'show', 'Show infrastructure details'
        def show(type = 'json')
          Dir.chdir(data.deploy_path) do
            show_json
          end
        end

        # desc 'destory', 'Destroy infrastructure'
        # def destroy
        #   Dir.chdir(data.deploy_path) do
        #     system_cmd('terraform destroy', {})
        #   end
        # end

        private
        # TODO: this needs to be per provider and region comes from deployment.yml
        def cmd_environment
          { 'AWS_DEFAULT_REGION' => 'ap-southeast-1' }
        end

        def config_files
          Dir["#{Ros.root.join(data.deploy_path)}/*.tf"]
        end

        def generate_config
          silence_output do
            Ros::Be::Data::Generator.new([], {}, {behavior: :revoke}).invoke_all
            Ros::Be::Data::Generator.new.invoke_all
          end
        end

        def data; Ros::Be::Data::Model end
      end
    end
  end
end
