# frozen_string_literal: true
require 'open3'

module Ros
  class Errors
    attr_reader :messages, :details

    def initialize
      @messages = {}
      @details = {}
    end

    def add(attribute, message = :invalid, options = {})
      @messages[attribute] = message
      @details[attribute] = options
    end

    def size; @messages.size end
  end

  module CliBase
    attr_accessor :options, :errors, :stdout, :stderr, :exit_code

    def test_for_project
      raise Error, set_color('ERROR: Not a Ros project', :red) if Ros.root.nil?
    end

    # run command with output captured to variables
    # returns boolean true if command successful, false otherwise
    def capture_cmd(cmd, envs = {})
      return if setup_cmd(cmd)
      @stdout, @stderr, process_status = Open3.capture3(envs, cmd)
      @exit_code = process_status.exitstatus
      @exit_code.zero?
    end

    # run command with output captured unless verbose (options.v) then to terminal
    # returns boolean true if command successful, false otherwise
    def system_cmd(cmd, envs = {}, never_capture = false)
      return capture_cmd(cmd, envs) unless (options.v or never_capture)
      return if setup_cmd(cmd)
      system(envs, cmd)
      @exit_code = $?.exitstatus
      @exit_code.zero?
    end

    def setup_cmd(cmd)
      puts cmd if options.v
			@stdout = nil
			@stderr = nil
      @exit_code = 0
      options.n
    end

    def exit
      STDOUT.puts(errors.messages.map{ |(k, v)| "#{k} error:\n---\n#{v}\n---" }) if errors.size.positive?
      Kernel.exit(errors.size)
    end

    # TODO: the namespace needs to be configurable; don't assume 'be'
    def stale_config
      return true if config_files.empty?

      mtime = config_files.map { |f| File.mtime(f) }.min
      # Check config files
      Dir["#{Ros.root}/config/**/*.yml"].each { |f| return true if mtime < File.mtime(f) }
      # Check template files
      Dir["#{Ros.gem_root.join('lib/ros/be')}/**/{templates,files}/**/*"].each do |f|
        return true if mtime < File.mtime(f)
      end
      # Check custom templates
      Dir["#{Ros.root.join('lib/generators')}/be/**/{templates,files}/**/*"].each do |f|
        return true if mtime < File.mtime(f)
      end
      false
    end

    def config_files; raise NotImplementedError end

    def generate_config; raise NotImplementedError end

    def silence_output
      unless options.v
        rs = $stdout
        $stdout = StringIO.new
      end
      yield
      $stdout = rs unless options.v
    end
  end
end
