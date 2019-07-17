# frozen_string_literal: true

require 'thor/group'

module Ros
  module Generators
    module Deployment
      class ServicesGenerator < Thor::Group
        include Thor::Actions
        argument :name
        argument :project

        def self.source_paths; ["#{File.dirname(__FILE__)}/templates", File.dirname(__FILE__)] end

        def grafana
        end

        def fluentd
        end

        def nginx
        end
        # infra: Template terraform tfvars and tfstate
        # platform: template compose/skaffold templates and service configuration, e.g. fluentd logs
        # service: template compose/skaffold templates and service content
        def generate
        end

        def finish_message
          FileUtils.rm_rf(destination_root) if self.behavior.eql? :revoke
          action = self.behavior.eql?(:invoke) ? 'Created' : 'Destroyed'
          say "\n#{action} service at #{destination_root}"
        end
      end
    end
  end
end
