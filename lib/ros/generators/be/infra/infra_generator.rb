# frozen_string_literal: true

require 'ros/generators/be/infra/cluster/cluster_generator'

module Ros
  module Generators
    module Be
      module Infra
        class << self
          def settings; Settings.components.be.components.infra end
          def components; settings.components || Config::Options.new end
          def config; settings.config || Config::Options.new end
          def environment; settings.environment || Config::Options.new end
          def deploy_path; "#{Stack.deploy_path}/be/infra" end
          # def skaffold_version; config.skaffold_version end

          def tf_vars
            (components.keys - %i(kubernetes instance) + [config.cluster.type]).each do |name|
              klass = const_get(components[name].config.provider.capitalize)
              # puts JSON.pretty_generate(klass.send(name, components[name]))
            end
          end
        end

        # TODO: This is not based on just instance vs kubernetes
        # There will be tf_vars for all kinds of resources
        class Aws
          def self.instance(values)
            {
              aws_region: values.config.name
            }
          end

          def self.kubernetes(values)
            {
              aws_region: values.config.name
            }
          end

          def self.tf_vars_instance(cluster)
            {
              aws_region: cluster.provider.region,
              route53_zone_main_name: cluster.config.dns.domain,
              route53_zone_this_name: cluster.config.dns.subdomain,
              ec2_instance_type: cluster.provider.instance.type,
              ec2_key_pair: cluster.provider.instance.key_pair,
              ec2_tags: cluster.provider.instance.tags,
              ec2_ami_distro: cluster.provider.instance.ami_distro
              # lambda_filename: infra.lambda_filename
            }
          end

          def self.tf_vars_kubernetes(cluster)
            {
              aws_region: cluster.provider.region,
              route53_zone_main_name: cluster.config.dns.domain,
              route53_zone_this_name: cluster.config.dns.subdomain,
              # name: infra.name
            }
          end
        end

        class Gcp
          def self.tf_vars_instance(cluster)
            {}
          end

          def self.tf_vars_kubernetes(cluster)
            {}
          end
        end

        class InfraGenerator < Thor::Group
          include Thor::Actions
          extend CommonGenerator

          def self.a_path; File.dirname(__FILE__) end

          def generate
            create_file("#{deploy_path}/state.tf.json", "#{JSON.pretty_generate(tf_state)}")
            create_file("#{deploy_path}/terraform.tfvars", "#{JSON.pretty_generate(tf_vars)}")
            # Copies over the provider+type files only
            infra.components.each_pair do |component, config|
              next if %i(kubernetes instance).include?(component) and Infra.config.cluster.type != component.to_s
              provider = config.config.provider
              module_name = send(provider, component)
              module_path = "../files/terraform/#{provider}/#{module_name}"
              directory(module_path, "#{deploy_path}/#{provider}-#{module_name}")
            end
            create_file("#{deploy_path}/main.tf", '')
            # TODO: If templates are required then place them in 'templates' dir with a path that is idenitcal to the generated path
            # template('config/deployments/development.yml')
          end

          def execute
            [Cluster::ClusterGenerator].each do |klass|
              generator = klass.new
              generator.behavior = behavior
              generator.destination_root = destination_root
              generator.invoke_all
            end
          end

          private

          def aws(type)
            {
              kubernetes: 'eks',
              dns: 'route53',
              instance: 'ec2',
              vpc: 'vpc'
            }[type]
          end

          def tf_vars
            # binding.pry
            # obj = Object.const_get("Ros::Generators::Be::Infra::#{Cluster.config.provider.capitalize}")
            # obj.send("tf_vars_#{Cluster.config.type}", Cluster)
            Infra.tf_vars
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

          def infra; Settings.components.be.components.infra end

          def deploy_path; Infra.deploy_path end

          # def cluster; Settings.components.be.components.infra.components.cluster end
          # def settings; cluster.components.infra end
        end
      end
    end
  end
end
