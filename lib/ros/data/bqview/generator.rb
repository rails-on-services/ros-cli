# frozen_string_literal: true
require 'ros/data/generator'

module Ros
  module Data
    module Bqview
      module Model
        class << self
          def data; Settings.components.data end
          def settings; data.components.bqview end
          def config; settings.config || Config::Options.new end
          def deploy_path; "#{Stack.deploy_path}/data/bqview" end
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

          create_file("#{bqview.deploy_path}/terraform.tfvars.json", "#{JSON.pretty_generate(tf_vars)}")
          create_file("#{bqview.deploy_path}/state.tf.json", "#{JSON.pretty_generate(tf_state)}")
          template("terraform/bqview.tf.erb", "#{bqview.deploy_path}/bqview.tf")
        end

        private
        def tf_state
          @tf_state ||= {
            terraform: {
              backend: {
                "#{Settings.config.terraform.state.bqview.type}": Settings.config.terraform.state.bqview.to_h.select { |k, v| k.to_s != 'type' && ! v.nil? } || {}
              }
            }
          }
        end

        def tf_vars
          vars = {}
            vars["fluentd_gcp_logging_service_account_json_key"] = \
            Ros::Be::Infra::Model.infra.components.kubernetes.components&.services&.components&.cluster_logging&.config&.gcp_service_account_key || ""
          return vars
      end

        def profile; Ros.profile end
        def current_feature_set; Ros::Be::Application::Model.current_feature_set end
        def bqview; Ros::Data::Bqview::Model end
      end
    end
  end
end
