# frozen_string_literal: true

module Ros
  module Generators
    module Be
      module Cluster
        class << self
          def settings; Settings.components.be.components.cluster end
          def config; settings.config || {} end
          def environment; settings.environment || {} end
          def deploy_path; "tmp/deployments/#{Ros.env}/be/cluster" end
          def provider; Settings.infra.config.providers[Settings.components.be.config.provider] end
          def name; config.name end
        end
      end
    end
  end
end
