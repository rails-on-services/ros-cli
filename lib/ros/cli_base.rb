# frozen_string_literal: true

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
    attr_accessor :options
    def test_for_project
      raise Error, set_color("ERROR: Not a Ros project", :red) if Ros.root.nil?
    end

    def system_cmd(label = :unknown, env = {}, cmd)
      puts cmd if options.v
      return if options.n
      result = system(env, cmd)
      errors.add(label) unless result
      result
    end

    def exit
      STDOUT.puts(errors.messages.map{|(k,v)| "#{k}=#{v}"}) unless errors.size.zero?
      Kernel.exit(errors.size)
    end

    # TODO: the namespace needs to be configurable; don't assume 'be'
    def stale_config
      return true if config_files.empty?
      mtime = config_files.map{ |f| File.mtime(f) }.min
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
