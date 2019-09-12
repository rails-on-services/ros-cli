# frozen_string_literal: true

require 'ros/be/infra/cluster/generator'

module Ros
  module Be
    module Infra
      module Model
        class << self
          def settings; Settings.components.be.components.infra end
          def components; settings.components || Config::Options.new end
          def config; settings.config || Config::Options.new end
          def environment; settings.environment || Config::Options.new end
          def deploy_path; "#{Stack.deploy_path}/be/infra" end
          def cluster_type; config.cluster.type end
          # def skaffold_version; config.skaffold_version end
          def dns; settings.components.dns.config end
          def uri; URI("#{dns.endpoints.api.scheme}://#{dns.endpoints.api.host}.#{dns.sub_domain}.#{dns.root_domain}") end
        end
      end

      class Generator < Thor::Group
        include Thor::Actions
        include Ros::Be::CommonGenerator

        def self.a_path; File.dirname(__FILE__) end

        def generate
          create_file("#{infra.deploy_path}/state.tf.json", "#{JSON.pretty_generate(tf_state)}")
          providers = Set.new
          # For each component, copy over the provider/component_type TF module code
          infra.components.each_pair do |component, config|
            next if %i(kubernetes instance).include?(component) and infra.cluster_type != component.to_s
            provider = config.config.provider
            providers.add(provider)
            module_names = send(provider, component)
            module_names.each do |module_name|
              module_path = "../files/terraform/#{provider}/#{module_name}"
              # NOTE: Uncomment next line to pause execution and inspect variable values, test code, etc
              # binding.pry
              directory(module_path, "#{infra.deploy_path}/#{provider}/#{module_name}")
            end
          end
          # Render each provider's main.tf
          providers.each do |provider|
            template("terraform/#{provider}/#{infra.cluster_type}.tf.erb", "#{infra.deploy_path}/#{provider}-main.tf")
          end
          # Copy over gcp creds for cluster level fluentd logging collection
          if infra.cluster_type.eql?('kubernetes') and File.exists?("#{Ros.environments_dir}/gcp_fluentd_logging_credentials.json")
            FileUtils.cp("#{Ros.environments_dir}/gcp_fluentd_logging_credentials.json", "#{infra.deploy_path}/aws/eks-resources/files")
          end
          create_file("#{infra.deploy_path}/terraform.tfvars.json", "#{JSON.pretty_generate(tf_vars)}")
        end

        def execute
          [Cluster::Generator].each do |klass|
            generator = klass.new
            generator.behavior = behavior
            generator.destination_root = destination_root
            generator.invoke_all
          end
        end

        private
        def aws(type)
          {
            cert: ['acm'],
            dns: ['route53'],
            instance: ['ec2'],
            kubernetes: ['eks-cluster', 'eks-resources'],
            vpc: ['vpc'],
            iam: ['eks-iam'],
            globalaccelerator: ['globalaccelerator'],
            databases: ['rds'],
            redis: ['elasticache-redis']
          }[type]
        end

        def gcp(type)
          {
            vpc: ['vpc'],
            instance: ['gci']
          }[type]
        end

        def azure(type)
          {
          }[type]
        end

        def oracle(type)
          {
          }[type]
        end

        def tf_state
          {
            terraform: {
              backend: {
                "#{Settings.config.terraform.state.type}": Settings.config.terraform.state.to_h.select { |k, v| k.to_s != 'type' && ! v.nil? } || {}
              }
            }
          }
        end

        def tf_vars
            vars = {
              tags: infra.config.cluster.tags, 
            }
            if infra.cluster_type.eql?('kubernetes')
              vars["eks_worker_groups"] = infra.components.kubernetes.config.worker_groups
            end
            return vars
        end

        def tf; infra.components end
        def infra; Ros::Be::Infra::Model end
      end
    end
  end
end
