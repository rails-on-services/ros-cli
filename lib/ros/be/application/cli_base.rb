# frozen_string_literal: true
require 'thor'
require 'ros/stack'
require 'ros/cli_base'
# require 'ros/generators/be/application/services/services_generator'
# require 'ros/generators/be/application/platform/platform_generator'

module Ros
  module Be
    module Application
      module CliBase
        include Ros::CliBase
        attr_accessor :options

        def show(service_name)
          service = service_name.split('/')[0]
          service_name = "#{service_name}.yml" unless service_name.index('.')
          %w(services platform).each do |type|
            keys = application.components[type].components.keys
            next unless keys.include?(service.to_sym)
            file = "#{application.deploy_path}/#{type}/#{service_name}"
            STDOUT.puts File.read(file)
          end
        end

        def show_endpoint
          STDOUT.puts "\n*** Services available at #{application.api_uri} ***"
          STDOUT.puts "*** API Docs available at [TO IMPLEMENT] ***\n\n"
        end

        def enabled_services
          application.components.platform.components.to_hash.select do |k, v|
            v.nil? || v.dig(:config, :enabled).nil? || v.dig(:config, :enabled)
          end.keys
        end

        def enabled_services_f
          application.components.services.components.to_hash.select do |k, v|
            v.nil? || v.dig(:config, :enabled).nil? || v.dig(:config, :enabled)
          end.keys
        end

        # TODO: After every IAM seed then write all versions of credentials
        # TODO: ros generate:docs:erd
        # NOTE: if these are cli commands then can take one or more services
        def publish_env_credentials
          return unless File.exists?(creds_file)
          content = json.each_with_object([]) { |j, a| a.append(Credential.new(j).to_env) }.join("\n")
          File.open("#{application.deploy_path}/platform/credentials.env", 'w') { |f| f.puts "#{content}\n" }
        end

        def json
          @json ||= File.exists?(creds_file) ? JSON.parse(File.read(creds_file)) : []
        end

        def creds_file; "#{Ros.is_ros? ? '' : 'ros/'}services/iam/tmp/#{application.current_feature_set}/credentials.json" end

        # TODO: support the proprietary project
        # TODO: each type, instance and k8s need to get their files
        # TODO: For now just change the host in the API docs
        def publish
          erd_dir = "#{application.deploy_path.gsub('deployments', 'documents')}/platform"
          FileUtils.mkdir_p(erd_dir)
          services.each do |service|
            exec(service, 'rails app:ros:erd:generate')
            if File.exists?("services/#{service}/spec/dummy/erd.pdf")
              FileUtils.mv("services/#{service}/spec/dummy/erd.pdf", "#{erd_dir}/#{service}.erd")
            end
          end
          # TODO publish to slack, confluence or someother
        end

        def convert
          require 'ros/postman/open_api'
          postman_dir = "tmp/api/#{application.api_hostname}/postman"
          openapi_dir = "tmp/api/#{application.api_hostname}/openapi"
          FileUtils.mkdir_p(openapi_dir)
          services.each do |service|
            if exec(service, 'rails app:ros:apidoc:generate')
              FileUtils.mv("services/#{service}/tmp/docs/openapi/ros-api.json", "#{openapi_dir}/#{service}.json")
            end
          end
          Dir["#{openapi_dir}/*.json"].each do |file|
            Postman::OpenApi.new(file_name: File.basename(file), openapi_dir: openapi_dir, postman_dir: postman_dir).convert_to_postman
          end
        end

        # desc 'Publish docs to Postman'
        # task publish: :environment do
        def publish_to_postman
          require 'faraday'
          require 'ros/postman/comm'
          require 'ros/postman/workspace'
          comm = Postman::Comm.new
          workspace = Postman::Workspace.new(name: application.api_hostname, comm: comm)
          postman_dir = "tmp/api/#{application.api_hostname}/postman"
          # @workspace = Postman::Workspace.new(id: '3e6ef171-dccd-4164-ae0d-cc3abbb43bad')
          # Dir["#{openapi_dir}/*.json"].each do |file|
          Dir["#{postman_dir}/*.json"].each do |file|
            service = File.basename(file).gsub('.json', '')
            collection = workspace.collection(service)
            data = JSON.parse(File.read(file))

            # Modify Postman JSON to replace the authorization value <String> with the Postman variable {{authorization}}
            data['item'].each { |item| modify_payload(item) }
            payload = workspace.payload(collection, data)
            result = workspace.publish(collection, payload)
            next if result.eql?('ok')
            STDOUT.puts "Error publishing #{service}\n#{JSON.parse(result)}"
          end

          # TODO: publish credentials
          # Invoke service's publish task if it exists
          # service_task = "#{ros_task_prefix}ros:#{Settings.service.name}:apidoc:publish"
          # Rake::Task[service_task].invoke if Rake::Task.task_defined? service_task
        end

        def modify_payload(item)
          if item.is_a? Array
            item.each { |item| modify_payload(item) }
          elsif item['item']
            modify_payload(item['item'])
          else
            # if item['request'].try(:[], 'body').try(:[], 'raw')
            if item['request'] and item['request']['body'] and item['request']['body']['raw']
              type = JSON.parse(item['request']['body']['raw'])['data']['xyz_type']
              replace_type = type.gsub(/<|>/, '')
              item['request']['body']['raw'].gsub!('xyz_type', 'type')
              item['request']['body']['raw'].gsub!(type, replace_type)
            end
            item['request']['header'].select{ |k| k['key'].eql?('Authorization') }.first['value'] = '{{authorization}}'
          end
        end

        def publish_cli_credentials
          cli_credentials_dir = "#{Dir.home}/.#{Stack.config.name}"
          FileUtils.mkdir_p(cli_credentials_dir)
          File.open("#{cli_credentials_dir}/credentials", 'a') do |f|
            # TODO: implement
          end
        end
      end

      class Credential
        attr_accessor :type, :owner, :tenant, :credential, :secret

        def initialize(json)
          self.type = json['type']
          self.owner = json['owner']
          self.tenant = json['tenant']
          self.credential = json['credential']
          self.secret = json['secret']
        end

        def to_env
          Ros.format_envs('', Config::Options.new.merge!({
            'platform' => {
              'tenant' => {
                "#{tenant['id']}" => {
                  "#{type}" => {
                    "#{owner['id']}" => "Basic #{credential['access_key_id']}:#{secret}"
                  }
                }
              }
            }
          })).first
        end

        def to_cli
          "[#{identifier}]\n" \
          "#{part_name}_access_key_id=#{credential['access_key_id']}\n" \
          "#{part_name}_secret_access_key=#{secret}"
        end

        def to_postman
          # TODO: password is not serialized
          {
            name: identifier,
            values: [
              { key: :authorization, value: "Basic #{credential['access_key_id']}:#{secret}" },
              { key: uid, value: owner[uid] },
              { key: :password, value: owner['password'] }
            ]
          }
        end

        def identifier; "#{tenant_account_id}-#{cred_uid}" end

        def uid; type.eql?('root') ? 'email' : 'username' end

        def cred_uid; type.eql?('root') ? owner['email'].split('@').first : owner['username'] end

        def part_name; application.components.platform.environment.platform.partition_name end

        def tenant_account_id; tenant['urn'].split('/').last end

        def application; Ros::Be::Application::Model end
      end
    end
  end
end
