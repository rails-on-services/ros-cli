# frozen_string_literal: true
require 'bump'

module Ros
  class Deployment
    attr_accessor :infra, :core, :platform, :devops
    attr_accessor :provider
    attr_accessor :options # CLI options

    def initialize(options)
      self.options = options
      %i(infra core platform devops).each do |type|
        self.send("#{type}=", Settings.send(type))
      end
      self.provider = Config::Options.new
      provider.config = infra.config.providers[infra.config.provider]
    end

    def template_hash(name = '', profile = ''); template_vars(name, profile).merge(base_vars) end
    def template_vars(name, profile); {} end
    def base_vars; { infra: infra, platform: platform, core: core, devops: devops } end

    def uri; URI("#{infra.config.endpoints.api.scheme}://#{api_hostname}") end

    def api_hostname
      @api_hostname ||= "#{infra.config.endpoints.api.host}#{base_hostname}"
    end

    def sftp_hostname
      @sftp_hostname ||= "#{infra.config.endpoints.sftp.host}#{base_hostname}"
    end

    def base_hostname
      @base_hostname ||= (infra.config.dns ? "#{current_branch_name}.#{dns_domain}" : 'localhost')
    end

    def dns_domain
      @dns_domain ||= "#{infra.config.dns.subdomain}.#{infra.config.dns.domain}"
    end

    def current_branch_name
      @current_branch_name ||= (infra.config.branch_deployments and not branch_name.eql?(infra.config.api_branch)) ? "-#{branch_name}" : ''
    end

    def version; Dir.chdir(Ros.root) { Bump::Bump.current } end
    def image_tag; "#{version}-#{sha}#{image_suffix}" end
    def image_suffix; platform.config.image.build_args.rails_env.eql?('production') ? '' : "-#{platform.config.image.build_args.rails_env}" end

    def branch_name
      return unless system('git rev-parse --git-dir > /dev/null 2>&1')
      @branch_name ||= %x(git rev-parse --abbrev-ref HEAD).strip.gsub(/[^A-Za-z0-9-]/, '-')
    end

    def sha
      return @sha if @sha
      return unless system('git rev-parse --git-dir > /dev/null 2>&1')
      @sha = %x(git rev-parse --short HEAD).chomp
    end

    def deploy_root; @deploy_root ||= "#{Ros.root}/tmp/deployments/#{deploy_path}" end
    def relative_path_from_root; @relative_path_from_root ||= deploy_root.gsub("#{Ros.root}/", '') end
    def relative_path; @relative_path ||= ('../' * deploy_root.gsub("#{Ros.root}/", '').split('/').size).chomp('/') end
    def template_root; @template_root ||= Pathname(__FILE__).dirname.join("./generators/deployment/#{template_prefix}") end
    def template_services_root; @template_services_root ||= Pathname(__FILE__).dirname.join("./generators/deployment/services") end

    def system_cmd(env, cmd)
      puts "Running #{cmd}"
      system(env, cmd) unless options.noop
    end
  end
end
