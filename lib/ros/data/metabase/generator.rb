# frozen_string_literal: true
require 'ros/data/generator'

module Ros
  module Data
    module Metabase
      module Model
        class << self
          def settings; Settings.components.data.components.metabase end
          def config; settings.config || Config::Options.new end
          def deploy_path; "#{Stack.deploy_path}/data/metabase" end
        end
      end

      class Generator < Thor::Group
        include Thor::Actions
        include Ros::Data::CommonGenerator

        def self.a_path; File.dirname(__FILE__) end

        def generate
          unless tf_state.empty? || current_feature_set.eql?("master")
            tf_state[:terraform][:backend][:s3][:key] = tf_state[:terraform][:backend][:s3][:key] + "-#{current_feature_set}"
          end

          create_file("#{metabase.deploy_path}/state.tf.json", "#{JSON.pretty_generate(tf_state)}")
          template("terraform/metabase.tf.erb", "#{metabase.deploy_path}/metabase.tf")

        end

        private
        def tf_state
          @tf_state ||= {
            terraform: {
              backend: {
                "#{Settings.config.terraform.state.metabase.type}": Settings.config.terraform.state.metabase.to_h.select { |k, v| k.to_s != 'type' && ! v.nil? } || {}
              }
            }
          }
        end
        def current_feature_set; Ros::Be::Application::Model.current_feature_set end
        def metabase; Ros::Data::Metabase::Model end
        def app; Ros::Be::Application::Model end
      end
    end
  end
end
