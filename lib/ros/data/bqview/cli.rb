# frozen_string_literal: true

require 'ros/cli_base'
require 'ros/cli'
require 'ros/data/bqview/generator'
require 'ros/data/generator'

module Ros
  module Data
    module Bqview
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
          Dir.chdir(bqview.deploy_path) do
            fetch_data_repo()
            fetch_terraform_custom_providers(bqview.config.custom_tf_providers, options.cl)
            system_cmd('rm -rf .terraform/modules/') if options.cl
            system_cmd('terraform init', cmd_environment)
            errors.add(:terraform_init, stderr) if exit_code.positive?
            system_cmd('terraform plan', cmd_environment)
            errors.add(:terraform_plan, stderr) if exit_code.positive?
          end
        end

        desc 'apply', 'Apply the terraform infrastructure plan'
        option :cl, type: :boolean, aliases: '--clear', desc: 'Clear local modules cache. Force to download latest modules from TF registry'
        option :auto_approve, type: :boolean, aliases: '--auto-approve', desc: 'Terraform. Skip interactive approval of plan before applying'
        def apply
          generate_config if stale_config
          auto_approve = options.auto_approve? ? "-auto-approve" : ""
          Dir.chdir(bqview.deploy_path) do
            fetch_data_repo()
            fetch_terraform_custom_providers(bqview.config.custom_tf_providers, options.cl)
            system_cmd('rm -rf .terraform/modules/') if options.cl
            system_cmd('rm -f .terraform/terraform.tfstate')
            system_cmd('terraform init', cmd_environment)
            errors.add(:terraform_init, stderr) if exit_code.positive?
            system_cmd("terraform apply #{auto_approve}", cmd_environment)
            errors.add(:terraform_apply, stderr) if exit_code.positive?
            system_cmd('terraform output -json > output.json', cmd_environment)
          end
        end

        desc 'destory', 'Destroy infrastructure'
        def destroy
          Dir.chdir(bqview.deploy_path) do
            fetch_terraform_custom_providers()
            system_cmd('terraform destroy', {})
          end
        end

        private
        def cmd_environment; {} end

        def config_files
          Dir["#{Ros.root.join(bqview.deploy_path)}/*.tf"]
        end

        def generate_config
          silence_output do
            Ros::Data::Bqview::Generator.new([], {}, {behavior: :revoke}).invoke_all
            Ros::Data::Bqview::Generator.new.invoke_all
          end
        end

        def bqview; Ros::Data::Bqview::Model end
      end
    end
  end
end
