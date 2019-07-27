# frozen_string_literal: true

require 'ros/generator_base'
require 'ros/be/application/platform/generator'
require 'ros/be/application/services/generator'

module Ros
  module Be
    module Application
      module Model
        class << self
          def settings; Settings.components.be.components.application end
          def config; settings.config || Config::Options.new end
          def components; settings.components end
          def c_environment; settings.environment || Config::Options.new end
          # def deploy_path; "#{Stack.deploy_path}/be/application" end
          def deploy_path; "#{Stack.deploy_path}/be/application/#{current_feature_set}" end

          def compose_file; @compose_file ||= "#{compose_dir}/compose.env" end
          def compose_dir; "#{Ros.root}/tmp/compose/#{Ros.env}/#{current_feature_set}" end
          def compose_project_name; "#{Stack.name}_#{current_feature_set}" end

          def current_feature_set
            @feature_set ||= (override_feature_set ? Stack.branch_name : settings.config.feature_set)
          end

          def override_feature_set
            @override_feature_set ||= (settings.config.feature_from_branch and not Stack.branch_name.eql?(settings.config.feature_set))
          end

          def environment
            @environment ||= Stack.environment.dup.merge!(c_environment.merge!(application_environment).to_hash)
          end

          # Common environment for application services
          def application_environment
            {
              infra: {
                # provider: Settings.components.be.config.provider,
                provider: cluster.config.provider,
              },
              platform: {
                feature_set: current_feature_set,
                infra: {
                  resources: {
                    storage: {
                      primary: {
                        bucket_name: bucket_name
                      }
                    }
                  }
                }
              },
              bucket_name: bucket_name
            }
          end

          def api_uri
            URI("#{infra.dns.endpoints.api.scheme}://#{api_hostname}").to_s
          end

          def api_hostname
            @api_hostname ||= "#{infra.dns.endpoints.api.host}#{base_hostname}"
          end

          def sftp_hostname
            @sftp_hostname ||= "#{infra.dns.endpoints.sftp.host}#{base_hostname}"
          end

          def base_hostname
            @base_hostname ||= (infra.dns ? "#{override_feature_set ? '-' + current_feature_set : ''}.#{dns_domain}" : 'localhost')
          end

          def dns_domain
            @dns_domain ||= "#{infra.dns.sub_domain}.#{infra.dns.root_domain}"
          end

          def bucket_name
            @bucket_name ||= "#{current_feature_set}-#{Stack.name}-#{cluster.name}"
          end

          def infra; Ros::Be::Infra::Model end
          def cluster; Ros::Be::Infra::Cluster::Model end
        end
      end

      class Generator < Thor::Group
        include Thor::Actions
        include Ros::Be::CommonGenerator

        def self.a_path; File.dirname(__FILE__) end

        def execute
          [Ros::Be::Application::Platform::Generator, Ros::Be::Application::Services::Generator].each do |klass|
            generator = klass.new
            generator.behavior = behavior
            generator.destination_root = destination_root
            generator.invoke_all
          end
        end
      end
    end
  end
end
