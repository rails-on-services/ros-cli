# frozen_string_literal: true

require 'thor/group'

module Ros
  module Main
    module Env
      class Generator < Thor::Group
        include Thor::Actions
        argument :name

        def self.source_paths; ["#{File.dirname(__FILE__)}/templates", File.dirname(__FILE__)] end

        def generate
          require 'securerandom'
          in_root do
            Ros.load_env(name)
            template 'environments.yml.erb', "#{Ros.environments_dir}/#{name}.yml"
          end
        end

        # TODO: some other way to seed services on host with an env
        # This would be to write the same values as in the compose platform.env to
        # Ros.root/lib/core/config/environments/local.yml so core could load it
        # What would normally be 
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
        def partition_name; platform.environment.platform.partition_name end
        def platform; application.components.platform end
        def application; Settings.components.be.components.application end
        def uri; infra.uri end
        def infra; Ros::Be::Infra::Model end
      end
    end
  end
end
