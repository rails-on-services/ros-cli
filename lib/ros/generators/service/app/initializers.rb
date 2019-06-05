# frozen_string_literal: true

application "require 'rails-html-sanitizer'"

insert_into_file @profile.config_file, before: 'require' do <<-RUBY
require 'ros/core'
RUBY
end

# TODO: here might be the issue with spec/dummy migrations
if @profile.is_ros?
  inject_into_file @profile.initializer_file, after: ".api_only = true\n" do <<-RUBY

      # Adds this gem's db/migrations path to the enclosing application's migraations_path array
      # if the gem has been included in an application, i.e. it is not running in the dummy app
      # https://github.com/rails/rails/issues/22261
      initializer :append_migrations do |app|
        config.paths['db/migrate'].expanded.each do |expanded_path|
          app.config.paths['db/migrate'] << expanded_path
          ActiveRecord::Migrator.migrations_paths << expanded_path
        end unless app.config.paths['db/migrate'].first.include? 'spec/dummy'
      end
RUBY
  end
end

inject_into_file @profile.initializer_file, after: ".api_only = true\n" do <<-RUBY
      initializer :console_methods do |app|
        Ros.config.factory_paths += Dir[Pathname.new(__FILE__).join('../../../../spec/factories')]
        Ros.config.model_paths += config.paths['app/models'].expanded
      end if Rails.env.development?
RUBY
end

=begin
   # Service values for apps, e.g. Survey
   initializer :service_values do |app|
     name = self.class.name.split('::').first
     Settings.service['name'] = name.downcase
     Settings.service['policy_name'] = name
   end
# =end

   # Service values for engines, e.g. Iam
inject_into_file @profile.initializer_file, after: ".api_only = true\n" do <<-RUBY
       initializer :service_values do |app|
         name = self.class.parent.name.demodulize.underscore
         Settings.prepend_source!({ service: { name: name, policy_name: name.capitalize } })
       end
RUBY
end


# =begin
# TODO: Test this with an application like Survey b/c that's not an engine.
inject_into_file @profile.initializer_file, after: ".api_only = true\n" do <<-RUBY
      initializer :service_values do |app|
        name = self.class.parent.name.demodulize.underscore
        Settings.service.name = name # '#{@profile.service_name}'
        Settings.service.policy_name = name.capitalize # '#{@profile.service_name.capitalize}'
      end
RUBY
end
=end
