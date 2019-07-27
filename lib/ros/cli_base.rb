# frozen_string_literal: true

module Ros
  module CliBase
    attr_accessor :options
    def test_for_project
      raise Error, set_color("ERROR: Not a Ros project", :red) if Ros.root.nil?
    end

    def system_cmd(env = {}, cmd)
      puts cmd if options.v
      system(env, cmd) unless options.n
    end

    # TODO: the namespace needs to be configurable; don't assume 'be'
    def stale_config
      return true if config_files.empty?
      mtime = config_files.map{ |f| File.mtime(f) }.min
      # Check config files
      Dir["#{Ros.root}/config/**/*.yml"].each { |f| return true if mtime < File.mtime(f) }
      # Check template files
      Dir["#{Ros.gem_root.join('lib/ros/generators')}/be/**/{templates,files}/**/*"].each do |f|
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
