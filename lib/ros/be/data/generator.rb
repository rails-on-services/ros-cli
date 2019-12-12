# frozen_string_literal: true

module Ros
  module Be
    module Data
      module Model
        class << self
          def settings; Settings.components.be.components.data end
          def components; settings.components || Config::Options.new end
          def config; settings.config || Config::Options.new end
          def environment; settings.environment || Config::Options.new end
          def deploy_path; "#{Stack.deploy_path}/be/data" end
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
          # create_file("#{data.deploy_path}/state.tf.json", "#{JSON.pretty_generate(tf_state)}")
          # providers = Set.new
          # # For each component, copy over the provider/component_type TF module code
          # infra.components.each_pair do |component, config|
          #   next if %i(kubernetes instance).include?(component) and infra.cluster_type != component.to_s
          #   provider = config.config.provider
          #   providers.add(provider)
          #   # Since we got Terraform modules in external registry we don't have local copy
          #   # module_names = send(provider, component)
          #   # module_names.each do |module_name|
          #     # module_path = "../files/terraform/#{provider}/#{module_name}"
          #     # NOTE: Uncomment next line to pause execution and inspect variable values, test code, etc
          #     # binding.pry
          #     # directory(module_path, "#{infra.deploy_path}/#{provider}/#{module_name}")
          #   # end
          # end
          # # Render each provider's main.tf
          # providers.each do |provider|
          #   @provider_config = Stack.config.infra[provider]
          #   template("terraform/#{provider}/#{infra.cluster_type}.tf.erb", "#{infra.deploy_path}/#{provider}-main.tf")
          end

          # create_file("#{infra.deploy_path}/terraform.tfvars.json", "#{JSON.pretty_generate(tf_vars)}")

          # Copy over 3rd party terraform plugins
          directory('../files/terraform/plugins', "#{data.deploy_path}", :mode => :preserve)
        end

        # def execute
        #   [Cluster::Generator].each do |klass|
        #     generator = klass.new
        #     generator.behavior = behavior
        #     generator.destination_root = destination_root
        #     generator.invoke_all
        #   end
        # end

        private
      end
    end
  end
end
