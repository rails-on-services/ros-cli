# frozen_string_literal: true

# workaround for rails 6.0.0.beta2
application "require 'rails-html-sanitizer'"

remove_file 'config/master.key'
remove_file 'config/credentials.yml.enc'

insert_into_file 'config/application.rb', before: "\n# Require the gems" do <<-RUBY
require 'ros/core'
RUBY
end

inject_into_file 'config/application.rb', after: ".api_only = true\n" do <<-RUBY
  config.generators do |g|
    g.test_framework :rspec, fixture: true
    g.fixture_replacement :factory_bot, dir: 'spec/factories'
  end

  initializer :console_methods do |app|
    # TODO: Test that this works for factories
    Ros.config.factory_paths += Dir[Pathname.new(__FILE__).join('../spec/factories')]
    Ros.config.model_paths += config.paths['app/models'].expanded
  end if Rails.env.development?

  initializer :service_values do |app|
    name = self.class.name.split('::').first
    Settings.service['name'] = name.downcase
    Settings.service['policy_name'] = name
  end
RUBY
end
