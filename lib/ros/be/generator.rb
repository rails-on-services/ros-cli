# frozen_string_literal: true

require 'ros/be/infra/generator'
require 'ros/be/application/generator'

module Ros
  module Be
    module Model
      class << self
        def settings; Settings.components.be end
      end
    end

    class Generator < Thor::Group
      include Thor::Actions
      extend CommonGenerator

      def self.a_path; File.dirname(__FILE__) end

      def execute
        [Infra::Generator, Application::Generator].each do |klass|
          generator = klass.new
          generator.behavior = behavior
          generator.destination_root = destination_root
          generator.invoke_all
        end
      end
    end
  end
end
