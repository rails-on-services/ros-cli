# frozen_string_literal: true

require 'thor/group'

module Ros
  module Generators
    class EnvGenerator < Thor::Group
      include Thor::Actions
      argument :name

      def self.source_paths; ["#{File.dirname(__FILE__)}/templates", File.dirname(__FILE__)] end

      def generate_secrets
        require 'securerandom'
        in_root do
          Ros.load_env(name)
          template 'environments.yml.erb', "#{Ros.environments_dir}/#{name}.yml"
        end
      end

      # TODO: some other way to seed services on host with an env
      # def create_console_env
      #   return unless name.eql?('console')
      #   in_root do
      #     Config.load_and_set_settings("#{Ros.environments_dir}/console.yml")
      #     self.content = Ros.format_envs('', Settings.platform.environment).join("\n")
      #     # TODO: Settings.services.each
      #     # self.content = Ros.format_envs('', Settings.platform.environment).join("\n")
      #     FileUtils.rm("#{Ros.environments_dir}/console.yml")
      #     template 'console.env.erb', "#{Ros.config_dir}/console.env"
      #   end
      # end

      private
      def application; Settings.components.be.components.application end
      def platform; application.components.platform end
      def partition_name; platform.environment.platform.partition_name end
      def infra; Ros::Generators::Be::Infra end
      def uri; infra.uri end
    end
  end
end
