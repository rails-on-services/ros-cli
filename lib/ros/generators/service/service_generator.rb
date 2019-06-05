# frozen_string_literal: true

require 'thor/group'

module Ros
  module Generators
    class ServiceGenerator < Thor::Group
      include Thor::Actions
      argument :name
      argument :project

      def self.source_paths; ["#{File.dirname(__FILE__)}/templates", File.dirname(__FILE__)] end

      # TODO: db and dummy path are set from config values
      def generate
        return unless self.behavior.eql? :invoke
        return if Dir.exists?("services/#{name}")
        rails_generator = Ros.is_ros? ? 'plugin' : 'app'
        plugin = Ros.is_ros? ? 'plugin' : ''
        plugin_options = Ros.is_ros? ? '--full --dummy-path=spec/dummy' : ''
        template_file = "#{File.dirname(__FILE__)}/#{rails_generator}/#{rails_generator}_generator.rb"
        rails_options = '--api -G -S -J -C -T -M --skip-turbolinks --database=postgresql --skip-active-storage'
        exec_string = "rails #{plugin} new #{rails_options} #{plugin_options} -m #{template_file} #{name}"
        puts exec_string
        Dir.chdir("#{destination_root}/services") { system(exec_string) }
      end

      def revoke
        return unless self.behavior.eql? :revoke
        FileUtils.rm_rf("#{destination_root}/services/#{name}")
        say "      remove  services/#{name}"
      end

      # TODO: maybe move this to plugin
      def gemspec_content
        return unless Ros.is_ros?
        gemspec = "services/#{name}/#{name}.gemspec"
        gsub_file gemspec, '  spec.name        = "', '  spec.name        = "ros-'
      end

      def sdk_content
        create_file "lib/sdk/lib/#{project}_sdk/models/#{name}.rb", <<~RUBY
          # frozen_string_literal: true

          module #{project.split('_').collect(&:capitalize).join}
            module #{name.split('_').collect(&:capitalize).join}
              class Client < Ros::Platform::Client; end
              class Base < Ros::Sdk::Base; end

              class Tenant < Base; end
            end
          end
        RUBY

        append_file "lib/sdk/lib/#{project}_sdk/models.rb", <<~RUBY
          require '#{project}_sdk/models/#{name}.rb'
        RUBY
      end
    end
  end
end
