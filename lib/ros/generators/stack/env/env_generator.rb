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
      def app; Settings.components.be.components.application end
      def partition_name; app.components.platform.environment.platform.partition_name end
      def dns; app.config.dns end
      def uri; URI("#{app.config.endpoints.api.scheme}://#{app.config.endpoints.api.host}.#{dns.subdomain}.#{dns.domain}") end
    end
  end
end
