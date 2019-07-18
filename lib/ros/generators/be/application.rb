# frozen_string_literal: true
require 'ros/generators/be/cluster'

module Ros
  module Generators
    module Be
      module Application
        class << self
          def settings; Settings.components.be.components.application end
          def config; settings.config || Config::Options.new end
          def c_environment; settings.environment || Config::Options.new end
          def deploy_path; "tmp/deployments/#{Ros.env}/be/application" end

          def environment
            @environment ||= Stack.environment.dup.merge!(c_environment.merge!(application_environment).to_hash)
          end

          # Common environment for application services
          def application_environment
            {
              infra: {
                provider: Settings.components.be.config.provider,
              },
              platform: {
                feature_set: Stack.current_feature_set,
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

          def api_hostname
            @api_hostname ||= "#{config.endpoints.api.host}#{base_hostname}"
          end

          def sftp_hostname
            @sftp_hostname ||= "#{config.endpoints.sftp.host}#{base_hostname}"
          end

          def base_hostname
            @base_hostname ||= (config.dns ? "#{Stack.override_feature_set ? '-' + Stack.current_feature_set : ''}.#{dns_domain}" : 'localhost')
          end

          def dns_domain
            @dns_domain ||= "#{config.dns.subdomain}.#{config.dns.domain}"
          end

          def bucket_name
            @bucket_name ||= "#{Stack.current_feature_set}-#{Stack.name}-#{Cluster.name}"
          end
        end
      end
    end
  end
end
