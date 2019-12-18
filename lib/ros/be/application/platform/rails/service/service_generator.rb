# frozen_string_literal: true

require 'thor/group'

module Ros
  module Be::Application::Platform
    module Rails
      module Service
        class Generator < Thor::Group
          include Thor::Actions
          argument :name

          def self.source_paths; ["#{File.dirname(__FILE__)}/templates", File.dirname(__FILE__)] end

          # TODO: db and dummy path are set from config values
          def generate
            return unless behavior.eql? :invoke
            return if Dir.exist?("services/#{name}")

            rails_generator = Ros.is_ros? ? 'plugin' : 'app'
            plugin = Ros.is_ros? ? 'plugin' : ''
            plugin_options = Ros.is_ros? ? '--full --dummy-path=spec/dummy' : ''
            template_file = "#{File.dirname(__FILE__)}/#{rails_generator}/#{rails_generator}_generator.rb"
            rails_options = '--api -G -S -J -C -T -M --skip-turbolinks --database=postgresql --skip-active-storage'
            exec_string = "rails #{plugin} new #{rails_options} #{plugin_options} -m #{template_file} #{name}"
            puts exec_string
            FileUtils.mkdir_p("#{destination_root}/services")
            Dir.chdir("#{destination_root}/services") { system(exec_string) }
          end

          def revoke
            return unless behavior.eql? :revoke

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
            create_file "#{sdk_lib_path}/models/#{name}.rb", <<~RUBY
              # frozen_string_literal: true

              module #{platform_name.split('_').collect(&:capitalize).join}
                module #{name.split('_').collect(&:capitalize).join}
                  class Client < Ros::Platform::Client; end
                  class Base < Ros::Sdk::Base; end

                  class Tenant < Base; end
                end
              end
            RUBY

            append_file "#{sdk_lib_path}/models.rb", <<~RUBY
              require '#{platform_name}_sdk/models/#{name}.rb'
            RUBY
          end

          private

          def platform_name; File.basename(Dir["#{lib_path.join('sdk')}/*.gemspec"].first).gsub('_sdk.gemspec', '') end

          def lib_path; Pathname(destination_root).join('lib') end

          def sdk_lib_path; lib_path.join("sdk/lib/#{platform_name}_sdk") end
        end
  end
end
  end
end
