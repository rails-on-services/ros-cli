# core/rails/gems.rb

# TODO: remove puma from Gemfile and get a version in here
comment_lines 'Gemfile', "gem 'puma'"
gem_group :production do
  gem 'puma'
end

gem 'pry-rails'
gem 'awesome_print'

gem_group :development, :test do
  gem 'brakeman', require: false
  gem 'pry-byebug'
  gem 'pry-stack_explorer'
  gem 'faker'
end
