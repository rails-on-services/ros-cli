# frozen_string_literal: true
require 'bump'

module Ros
  module Generators
    class Stack
      class << self
        def name; Settings.config.name end

        def current_feature_set
          @feature_set ||= (override_feature_set ? branch_name : settings.config.feature_set)
        end

        def override_feature_set
          @override_feature_set ||= (settings.config.feature_from_branch and not branch_name.eql?(settings.config.feature_set))
        end

        def branch_name
          return unless system('git rev-parse --git-dir > /dev/null 2>&1')
          @branch_name ||= %x(git rev-parse --abbrev-ref HEAD).strip.gsub(/[^A-Za-z0-9-]/, '-')
        end
        def settings; Settings.components.be end
        def config; settings.config || Config::Options.new end
        def environment; settings.environment || Config::Options.new end
        def skaffold_version; config.skaffold_version end
        def registry_secret_name; "registry-#{Settings.platform.config.image_registry}" end

        def version; Dir.chdir(Ros.root) { Bump::Bump.current } end
        def image_tag; "#{version}-#{sha}" end
        # image_suffix is specific to the image_type
        # TODO: Update to handle more than just rails
        def image_suffix; Settings.platform.config.image.build_args.rails_env.eql?('production') ? '' : "-#{Settings.platform.config.image.build_args.rails_env}" end
        def deploy_path; "tmp/deployments/#{Ros.env}/#{current_feature_set}" end

        def sha
          @sha ||= system('git rev-parse --git-dir > /dev/null 2>&1') ? %x(git rev-parse --short HEAD).chomp : 'no-sha'
        end

        def compose_file; @compose_file ||= "#{compose_dir}/compose.env" end
        def compose_dir; "#{Ros.root}/tmp/compose/#{Ros.env}/#{current_feature_set}" end
        def compose_project_name; "#{name}_#{current_feature_set}" end
      end
    end
  end
end
