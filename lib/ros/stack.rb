# frozen_string_literal: true
require 'bump'

module Ros
  module Stack
    class << self
      def settings; Settings end
      def config; settings.config || Config::Options.new end
      def environment; settings.environment || Config::Options.new end

      def name; config.name end

      def registry_secret_name; "registry-#{Settings.config.platform.config.image_registry}" end

      def deploy_path; "tmp/deployments/#{Ros.env}" end

      def image_tag
        "#{version}-#{image_prefix}#{sha}"
      end

      # image_prefix is specific to the image_type
      # TODO: Update to handle more than just rails
      def image_prefix
        @image_prefix ||= (
          images.rails.build_args.rails_env.eql?('production') ? '' : "#{images.rails.build_args.rails_env}-"
        )
      end

      def tag_name
        @tag_name ||= %x(git tag --points-at HEAD).chomp
      end

      def branch_name
        return unless system('git rev-parse --git-dir > /dev/null 2>&1')
        @branch_name ||= %x(git rev-parse --abbrev-ref HEAD).strip.gsub(/[^A-Za-z0-9-]/, '-')
      end

      def sha
        @sha ||= system('git rev-parse --git-dir > /dev/null 2>&1') ? %x(git rev-parse --short HEAD).chomp : 'no-sha'
      end

      def version; Dir.chdir(Ros.root) { Bump::Bump.current } end
      def images; Settings.config.platform.config.images end
    end
  end
end
