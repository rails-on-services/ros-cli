# frozen_string_literal: true

require 'ros/generators/common_generator'

module Ros
  module Generators
    module Be
      module Cluster
        module Infra

          class Aws
            def self.tf_vars_instance(provider)
              {
                aws_region: provider.region,
                route53_zone_main_name: Settings.components.be.components.cluster.config.dns.domain,
                route53_zone_this_name: Settings.components.be.components.cluster.config.dns.subdomain,
                ec2_instance_type: provider.instance.type,
                ec2_key_pair: provider.instance.key_pair,
                ec2_tags: provider.instance.tags,
                ec2_ami_distro: provider.instance.ami_distro
                # lambda_filename: infra.lambda_filename
              }
            end

            def self.tf_vars_kubernetes(provider)
              {
                aws_region: provider.region,
                route53_zone_main_name: Settings.components.be.components.cluster.config.dns.domain,
                route53_zone_this_name: Settings.components.be.components.cluster.config.dns.subdomain,
                # name: infra.name
              }
            end
          end

          class Gcp
            def self.tf_vars_instance(provider)
              {}
            end

            def self.tf_vars_kubernetes(provider)
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
              directory("../files/terraform/#{Settings.components.be.config.provider}/provision/#{cluster.config.type}", deploy_path)
              # TODO: If templates are required then place them in 'templates' dir with a path that is idenitcal to the generated path
              # template('config/deployments/development.yml')
            end

            private

            def tf_vars
              obj = Object.const_get("Ros::Generators::Be::Cluster::Infra::#{Settings.components.be.config.provider.capitalize}")
              obj.send("tf_vars_#{cluster.config.type}", Ros::Generators::Be::Cluster.provider)
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

            def deploy_path
              "#{Cluster.deploy_path}/infra"
            end

            def cluster; Settings.components.be.components.cluster end
            def settings; cluster.components.infra end
          end
        end
      end
    end
  end
end
