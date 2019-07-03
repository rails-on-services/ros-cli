# frozen_string_literal: true

require 'thor/group'

module Ros
  module Generators
    class EnvGenerator < Thor::Group
      include Thor::Actions
      argument :name
      argument :uri
      argument :partition_name
      argument :content

      def self.source_paths; ["#{File.dirname(__FILE__)}/templates", File.dirname(__FILE__)] end

      def generate_secrets
        self.uri = URI(uri)
        require 'securerandom'
        in_root do
          template 'environments.yml.erb', "#{Ros.environments_dir}/#{name}.yml"
        end
      end

      def create_console_env
        return unless name.eql?('console')
        in_root do
          Config.load_and_set_settings("#{Ros.environments_dir}/console.yml")
          self.content = Ros.format_envs('', Settings.platform.environment).join("\n")
          # TODO: Settings.services.each
          # self.content = Ros.format_envs('', Settings.platform.environment).join("\n")
          FileUtils.rm("#{Ros.environments_dir}/console.yml")
          template 'console.env.erb', "#{Ros.config_dir}/console.env"
        end
      end
    end
  end
end
