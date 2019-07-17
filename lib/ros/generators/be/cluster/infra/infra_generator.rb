# frozen_string_literal: true

require 'thor/group'

module Ros
  module Generators
    module Be
      module Cluster
        module Infra

          class Instance
            def self.tf_vars_aws(provider)
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
          end

          class Kubernetes
            def self.tf_vars_aws(provider)
              {
                aws_region: provider.region,
                route53_zone_main_name: Settings.components.be.components.cluster.config.dns.domain,
                route53_zone_this_name: Settings.components.be.components.cluster.config.dns.subdomain,
                # name: infra.name
              }
            end
          end

          class InfraGenerator < Thor::Group
            include Thor::Actions

            def self.source_paths; ["#{File.dirname(__FILE__)}/templates", File.dirname(__FILE__)] end

            def generate
              create_file("#{workdir}/state.tf.json", "#{JSON.pretty_generate(tf_state)}")
              create_file("#{workdir}/terraform.tfvars", "#{JSON.pretty_generate(tf_vars)}")
            end

            private
            def tf_vars
              obj = Object.const_get("Ros::Generators::Be::Cluster::Infra::#{cluster.config.type.capitalize}")
              obj.send("tf_vars_#{Settings.components.be.config.provider}", Ros::Generators::Be::Cluster.provider)
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

            def workdir; "#{Ros.tf_root}/#{Settings.components.be.config.provider}/provision/#{Settings.components.be.components.cluster.config.type}" end

            def cluster; Settings.components.be.components.cluster end
            def settings; cluster.components.infra end
          end
        end
      end
    end
  end
end
