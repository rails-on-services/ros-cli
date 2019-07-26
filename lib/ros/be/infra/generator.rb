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
        extend CommonGenerator

        def self.a_path; File.dirname(__FILE__) end

        def generate
          create_file("#{deploy_path}/state.tf.json", "#{JSON.pretty_generate(tf_state)}")
          providers = Set.new
          # For each component, copy over the provider/component_type TF module code
          infra.components.each_pair do |component, config|
            next if %i(kubernetes instance).include?(component) and Infra::Model.cluster_type != component.to_s
            provider = config.config.provider
            providers.add(provider)
            module_name = send(provider, component)
            module_path = "../files/terraform/#{provider}/#{module_name}"
            # NOTE: Uncomment next line to pause execution and inspect variable values, test code, etc
            # binding.pry
            directory(module_path, "#{deploy_path}/#{provider}/#{module_name}")
          end
          # Render each provider's main.tf
          providers.each do |provider|
            template("terraform/#{provider}/#{Infra::Model.cluster_type}.tf.erb", "#{deploy_path}/#{provider}-main.tf")
          end
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
            cert: 'acm',
            dns: 'route53',
            instance: 'ec2',
            kubernetes: 'eks',
            vpc: 'vpc'
          }[type]
        end

        def gcp(type)
          {
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
                "#{Settings.config.terraform.state.type}": Settings.config.terraform.state.to_h.select { |k, v| k.to_s != 'type' } || {}
              }
            }
          }
        end

        def tf; infra.components end
        def infra; Settings.components.be.components.infra end
        def deploy_path; Infra::Model.deploy_path end
      end
    end
  end
end
