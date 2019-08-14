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

        def infra; Ros::Be::Infra::Model end
        def cluster; Ros::Be::Infra::Cluster::Model end
        def application; Ros::Be::Application::Model end
        def platform ; Ros::Be::Application::Platform::Model end

        def generate_config
          silence_output do
            Ros::Be::Application::Services::Generator.new([], {}, {behavior: :revoke}).invoke_all
            Ros::Be::Application::Services::Generator.new.invoke_all
            Ros::Be::Application::Platform::Generator.new([], {}, {behavior: :revoke}).invoke_all
            Ros::Be::Application::Platform::Generator.new.invoke_all
          end
        end

        def test(services)
          switch!
          services = enabled_services if services.empty?
          generate_config if stale_config
          services.each do |service|
            is_ros = svc_config(service)&.config&.ros
            prefix = is_ros ? 'app:' : ''
            exec_dir = is_ros ? 'spec/dummy/' : ''
            next if exec(service, "rails #{prefix}db:test:prepare") && exec(service, "#{exec_dir}bin/spring rspec")
            return false
          end
          true
        end

        def svc_config(service); Settings.components.be.components.application.components.platform.components.dig(service) end

        def show(service_name)
          switch!
          service = service_name.split('/')[0]
          service_name = "#{service_name}.yml" unless service_name.index('.')
          %w(services platform).each do |type|
            keys = application.components[type].components.keys
            next unless keys.include?(service.to_sym)
            file = "#{application.deploy_path}/#{type}/#{service_name}"
            STDOUT.puts "Contents of #{file}"
            STDOUT.puts File.read(file)
          end
        end

        def status
          switch!
          ros_services = {}
          my_services = {}
          infra_services = {}
          application.components.platform.components.keys.sort.each do |name|
            svc = application.components.platform.components[name.to_s]
            status =
              if running_services.include?(name.to_s)
                'Running    '
              elsif svc.dig(:config, :enabled).nil? || svc.dig(:config, :enabled)
                'Stopped    '
              else
                'Not Enabled'
              end
            ros_services[name] = status if svc.dig(:config, :ros)
            my_services[name] = status unless svc.dig(:config, :ros)
          end
          (application.components.services.components.keys - %i(wait)).sort.each do |name|
            svc = application.components.services.components[name.to_s]
            status =
              if running_services.include?(name.to_s)
                'Running    '
              elsif svc&.dig(:config, :enabled).nil? || svc&.dig(:config, :enabled)
                'Stopped    '
              else
                'Not Enabled'
              end
            infra_services[name] = status
          end
          buf = ' ' * 13
          name_len = 20
          no_buf = -11
          STDOUT.puts "\nPlatform Services   Status                  Core Services" \
            "       Status                  Infra Services      Status\n#{'-' * 115}"
          (1..[infra_services.size, my_services.size, ros_services.size].max).each do |i|
            mn, ms = my_services.shift
            rn, rs = ros_services.shift
            fn, fs = infra_services.shift
            STDOUT.puts "#{mn}#{' ' * (name_len - (mn&.length || no_buf))}#{ms}#{buf}#{rn}" \
              "#{' ' * (name_len - (rn&.length || no_buf))}#{rs}#{buf}#{fn}#{' ' * (name_len - (fn&.length || no_buf))}#{fs}"
          end
          show_endpoint
        end


        def show_endpoint
          STDOUT.puts "\n*** Services available at #{application.api_uri} ***"
          STDOUT.puts "*** API Docs available at [TO IMPLEMENT] ***\n\n"
        end

        def credentials
          switch!
          get_credentials if not File.exists?(creds_file)
          generate_config if stale_config
          postman = JSON.parse(json.each_with_object([]) { |j, a| a.append(Credential.new(j).to_postman) }.to_json)
          envs = json.each_with_object([]) { |j, a| a.append(Credential.new(j).to_env) }
          cli = json.each_with_object([]) { |j, a| a.append(Credential.new(j).to_cli) }.join("\n\n")
          STDOUT.puts "Postman:"
          STDOUT.puts (postman)
          STDOUT.puts "\nEnvs:"
          STDOUT.puts (envs)
          STDOUT.puts "\nCli:"
          STDOUT.puts (cli)
          STDOUT.puts "\nCredentials source: #{creds_file}"
        end

        def json
          @json ||= File.exists?(creds_file) ? JSON.parse(File.read(creds_file)) : []
        end

        def creds_file; @creds_file ||= "#{runtime_dir}/platform/credentials.json" end

        def documents_dir; @documents_dir ||= "#{application.deploy_path.gsub('deployments', 'documents')}/platform" end
        def runtime_dir; @runtime_dir ||= application.deploy_path.gsub('deployments', 'runtime') end

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

        # TODO: support the proprietary project
        # TODO: each type, instance and k8s need to get their files
        # TODO: For now just change the host in the API docs
        def publish
          FileUtils.mkdir_p(documents_dir)
          services.each do |service|
            exec(service, 'rails app:ros:erd:generate')
            if File.exists?("services/#{service}/spec/dummy/erd.pdf")
              FileUtils.mv("services/#{service}/spec/dummy/erd.pdf", "#{documents_dir}/#{service}.erd")
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
