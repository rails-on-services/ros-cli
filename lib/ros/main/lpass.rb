# frozen_string_literal: true

module Ros
  module Cli
    # TODO: Get this working again
    class Lpass < Thor
      def initialize(*args)
        super
        self.options = args[2][:class_options]
      end

      desc 'add', "Add #{Ros.env} environment to Lastpass"
      def add
        test_for_project
        lpass_name = "#{Ros.root}/config/environments/#{Ros.env}.yml"
        `lpass login #{options.username}` if options.username
        binding.pry
        # %x(lpass add --non-interactive --notes #{Ros.env} < #{lpass_name})
      end

      desc 'show', "Displays #{Ros.env} environment from Lastpass"
      def show
        test_for_project
        `lpass show --notes #{Ros.env}`
      end

      desc 'update', "Updates #{Ros.env} environment in Lastpass"
      def update
        test_for_project
      end

      private

      def test_for_project
        raise Error, set_color('ERROR: Not a Ros project', :red) if Ros.root.nil?
      end
    end
  end
end
