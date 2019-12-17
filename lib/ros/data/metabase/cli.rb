# frozen_string_literal: true

require 'ros/cli_base'
require 'ros/cli'
require 'ros/data/metabase/generator'
require 'ros/data/generator'

module Ros
  module Data
    module Metabase
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
          Dir.chdir(metabase.deploy_path) do
            fetch_metabase_cards()
            fetch_terraform_custom_providers()
            system_cmd('rm -rf .terraform/modules/') if options.cl
            system_cmd('terraform init', cmd_environment)
            system_cmd('terraform plan', cmd_environment)
          end
        end

        desc 'apply', 'Apply the terraform infrastructure plan'
        option :cl, type: :boolean, aliases: '--clear', desc: 'Clear local modules cache. Force to download latest modules from TF registry'
        def apply
          generate_config if stale_config
          Dir.chdir(metabase.deploy_path) do
            fetch_metabase_cards()
            fetch_terraform_custom_providers()
            system_cmd('rm -rf .terraform/modules/') if options.cl
            system_cmd('rm -f .terraform/terraform.tfstate')
            system_cmd('terraform init', cmd_environment)
            system_cmd('terraform apply', cmd_environment)
            system_cmd('terraform output -json > output.json', cmd_environment)
          end
        end

        desc 'destory', 'Destroy infrastructure'
        def destroy
          Dir.chdir(metabase.deploy_path) do
            fetch_terraform_custom_providers()
            system_cmd('terraform destroy', {})
          end
        end

        private

        def fetch_metabase_cards
          STDOUT.puts "Fetching data sources v#{metabase.config.data_version} ..."
          File.open("#{metabase.config.data_version}.tar.gz", 'wb') do |fo|
            fo.write open("https://github.com/#{metabase.config.data_repo}/archive/#{metabase.config.data_version}.tar.gz",
                "Authorization" => "token #{metabase.config.github_token}",
                "Accept" => "application/vnd.github.v4.raw").read
          end
          %x(tar xzvf "#{metabase.config.data_version}.tar.gz" "whistler-data-#{metabase.config.data_version}/metabase")
        end

        def fetch_terraform_custom_providers
          case RUBY_PLATFORM
          when /linux/
            platform = "linux"
          when /darwin/
            platform = "darwin"
          else
            STDOUT.puts "Platform not supported. Exiting..."
            exit
          end

          metabase.config.custom_tf_providers.each { |k, v|
          f = "terraform-provider-#{k.to_s}_#{v.config.version}-#{platform}-amd64"
          unless File.file?(f) then
            File.open(f, 'wb') do |fo|
              STDOUT.puts "Downloading terraform provider #{k.to_s} #{v.config.version} ..."
              fo.write open("https://github.com/#{v.config.repo}/releases/download/#{v.config.version}/#{f}",
                "Accept" => "application/vnd.github.v4.raw").read
              File.chmod(0755, f)
            end
          else
            STDOUT.puts "Terraform provider #{k.to_s} #{v.config.version} exists locally"
          end
          }
        end

        # TODO: this needs to be per provider and region comes from deployment.yml
        def cmd_environment
          { 'AWS_DEFAULT_REGION' => 'ap-southeast-1' }
        end

        def config_files
          Dir["#{Ros.root.join(metabase.deploy_path)}/*.tf"]
        end

        def generate_config
          silence_output do
            Ros::Data::Metabase::Generator.new([], {}, {behavior: :revoke}).invoke_all
            Ros::Data::Metabase::Generator.new.invoke_all
          end
        end

        def metabase; Ros::Data::Metabase::Model end
      end
    end
  end
end
