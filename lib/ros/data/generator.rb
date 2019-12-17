# frozen_string_literal: true

require 'ros/generator_base'

module Ros
  module Data
    module Model
      class << self
        def settings; Settings.components.data end
      end
    end

    module CommonGenerator
      include Ros::BaseGenerator

      def self.included(base)
        base.extend(Ros::BaseGenerator::ClassMethods)
      end

      def metabase; Ros::Data::Metabase::Model end
    end

    class Generator < Thor::Group
      include Thor::Actions
      include CommonGenerator

      def self.a_path; File.dirname(__FILE__) end

      def execute
        require 'ros/data/metabase/generator'
        [Metabase::Generator].each do |klass|
          generator = klass.new
          generator.behavior = behavior
          generator.destination_root = destination_root
          generator.invoke_all
        end
      end
    end
  end
end