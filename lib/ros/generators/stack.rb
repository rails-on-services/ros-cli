# frozen_string_literal: true
require 'bump'

require 'thor/group'
require 'ros/generators/common_generator'
require 'ros/generators/be/infra/infra_generator'
require 'ros/generators/be/application/application_generator'

module Ros
  module Generators
    module Stack
      class << self
        def settings; Settings end
        def config; settings.config || Config::Options.new end
        def environment; settings.environment || Config::Options.new end

        def name; config.name end

        def registry_secret_name; "registry-#{Settings.platform.config.image_registry}" end

        def deploy_path; "tmp/deployments/#{Ros.env}" end

        def image_tag; "#{version}-#{sha}" end

        # image_suffix is specific to the image_type
        # TODO: Update to handle more than just rails
        def image_suffix; Settings.platform.config.image.build_args.rails_env.eql?('production') ? '' : "-#{Settings.platform.config.image.build_args.rails_env}" end

        def branch_name
          return unless system('git rev-parse --git-dir > /dev/null 2>&1')
          @branch_name ||= %x(git rev-parse --abbrev-ref HEAD).strip.gsub(/[^A-Za-z0-9-]/, '-')
        end

        def sha
          @sha ||= system('git rev-parse --git-dir > /dev/null 2>&1') ? %x(git rev-parse --short HEAD).chomp : 'no-sha'
        end

        def version; Dir.chdir(Ros.root) { Bump::Bump.current } end
      end
    end

    module Be
      class << self
        def settings; Settings.components.be end
      end

        class BeGenerator < Thor::Group
          include Thor::Actions
          extend CommonGenerator

          def self.a_path; File.dirname(__FILE__) end

          def execute
            [Infra::InfraGenerator, Application::ApplicationGenerator].each do |klass|
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
