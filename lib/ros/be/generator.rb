# frozen_string_literal: true

require 'ros/generator_base'

module Ros
  module Be
    module Model
      class << self
        def settings; Settings.components.be end
      end
    end

    module CommonGenerator
      include Ros::BaseGenerator

      def self.included(base)
        base.extend(Ros::BaseGenerator::ClassMethods)
      end

      def application; Ros::Be::Application::Model end
      def infra; Ros::Be::Infra::Model end
      def cluster; Ros::Be::Infra::Cluster::Model end
      def data; Ros::Be::Data::Model end
    end

    class Generator < Thor::Group
      include Thor::Actions
      include CommonGenerator

      def self.a_path; File.dirname(__FILE__) end

      def execute
        require 'ros/be/infra/generator'
        require 'ros/be/data/generator'
        require 'ros/be/application/generator'
        [Infra::Generator, Application::Generator, Data::Generator].each do |klass|
          generator = klass.new
          generator.behavior = behavior
          generator.destination_root = destination_root
          generator.invoke_all
        end
      end
    end
  end
end
