#!/usr/bin/env ruby

require 'optparse'
require 'logger'
require 'json'
require 'colorize'

class ChefTree

  attr_accessor :logger

  def initialize(options)
    @options = options
    @cookbook_paths = []
    @colors = String.colors
    @colors.delete(:black)
    @cookbook_color_map = {}
  end

  def fatal(message)
    @logger.fatal message
    raise
  end

  def read_metadata(path = nil)
    file = path.nil? ? 'metadata.rb' : File.join(path, 'metadata.rb')
    @logger.debug "Reading #{file}"
    if not File.exist?(file)
      fatal 'Could not read metadata'
    end
    metadata = {:depends => {}}
    File.open(file).read.each_line do |line|
      /^\s*name\s+['"](?<name>.+?)['"]$/.match(line) { |m| metadata[:name] = m[:name] }
      /^\s*version\s+['"](?<version>.+?)['"]$/.match(line) { |m| metadata[:version] = m[:version] }
      /^\s*depends\s*\(?\s*['"](?<cookbook>.+?)['"](?:\,\s*['"](?<version>.+?)['"])?\)?\s*$/.match(line) do |m|
        cookbook = m[:cookbook]
        version = m[:version]
        metadata[:depends][cookbook] = version
      end
    end
    @logger.debug "Found the following metadata #{metadata}"
    metadata
  end

  def read_recipe(name)
    recipe_file = File.join('recipes', "#{name}.rb")
    includes = []
    @logger.debug "Reading recipe #{recipe_file}"
    if not File.exist?(recipe_file)
      @logger.warn "Could not read recipe #{name}, might be a variable"
      return includes
    end
    File.open(recipe_file).read.each_line do |line|
      /^\s*include_recipe\s*\(?\s*['"](?<recipe>.+?)['"]\s*\)?\s*$/.match(line) { |m| includes << m[:recipe] }
    end
    @logger.debug "Found the following included recipes #{includes}"
    includes
  end

  def parse_cookbook(name)
    parts = name.split('::')
    cookbook = parts[0]
    recipe = parts.size == 1 ? 'default' : parts[1]
    [cookbook, recipe]
  end

  def print_line(index, cookbook, name, version, dep_version)
    data = []
    data << "#{'    ' * index}"
    data << name
    
    if dep_version != 'recipe'
      version_data = []
      version_data << version if version
      version_data << dep_version
      data << "(#{version_data.join(' ')})"
    end
    puts data.join(' ').colorize(@cookbook_color_map[cookbook])
  end

  def goto_cookbook(cookbook)
    return true if cookbook.nil?
    
    @cookbook_paths.each do |path|
      @logger.debug "Looking for cookbook #{cookbook} in #{path}"
      cookbook_dir = File.join(path, cookbook)
      if File.directory?(cookbook_dir) and File.exist?(File.join(cookbook_dir, 'metadata.rb'))
        @logger.debug "Found it"
        Dir.chdir(cookbook_dir)
        return true
      end
    end

    @logger.debug "Having to use aggressive search"
    @cookbook_paths.each do |path|
      Dir.glob(File.join(path, '*')).each do |child_path|
        @logger.debug "Looking for cookbook #{cookbook} in #{child_path}"
        if read_metadata(child_path)[:name] == cookbook
          @logger.debug "Found it"
          Dir.chdir(child_path)
          return true
        end
      end
    end

    @logger.warn "Could not find cookbook #{cookbook}, assuming not local"
    return false
  end

  def process_cookbook(index, cookbook, recipe, dep_version)
    @logger.info "Processing cookbook #{cookbook}::#{recipe} #{dep_version} at index #{index}"

    if not @cookbook_color_map.has_key?(cookbook)
      i = @cookbook_color_map.size % @colors.size
      @logger.debug "Setting color for cookbook #{cookbook} to #{@colors[i]}"
      @cookbook_color_map[cookbook] = @colors[i]
    end

    if not goto_cookbook(cookbook)
      @logger.debug "Nowhere to go"
      print_line(index, cookbook, "#{cookbook}::#{recipe}", nil, dep_version)
      return
    end

    metadata = read_metadata
    print_line(index, cookbook, "#{metadata[:name]}::#{recipe}", metadata[:version], dep_version)

    read_recipe(recipe).each do |included|
      (c, r) = parse_cookbook(included)
      if c == cookbook
        version = 'recipe'
      elsif metadata[:depends].has_key?(c)
        version = metadata[:depends][c] ? metadata[:depends][c] : 'ANY'
      else
        @logger.warn "Dependency not found for #{c} in metadata.rb for #{cookbook}"
        version = "NOT FOUND"
      end
      process_cookbook(index + 1, c, r, version)
    end
  end

  def goto_starting_dir
    if @options[:path] != Dir.getwd
      @logger.info "Changing directory to #{@options[:path]}"
      Dir.chdir(@options[:path])
    end
  end

  def read_config
    file = File.expand_path(@options[:config])
    @logger.info "Reading config file #{file}"
    if File.exist?(file)
      config = JSON.parse(File.open(file).read, :symbolize_names => true)
      @logger.info "Found the following config #{config}"
      if config.has_key?(:cookbook_paths)
        @cookbook_paths = config[:cookbook_paths]
      end
    else
      @logger.warn "Could not find config file."
    end
  end

  def run
    @logger.info "Running"
    goto_starting_dir
    read_config
    metadata = read_metadata
    process_cookbook(0, metadata[:name], @options[:recipe], 'START')
  end

end

options = {
  :path => Dir.getwd,
  :recipe => 'default',
  :log_level => 'error',
  :config => '~/.chef-tree.json'
}

OptionParser.new do |opts|
  opts.banner = "Usage: chef-tree.rb [options]"
  opts.on('-p', '--path PATH', 'Starting path') { |v| options[:path] = v }
  opts.on('-r', '--recipe RECIPE', 'Starting recipe') { |v| options[:recipe] = v }
  opts.on('-l', '--log LOG_LEVEL', 'Log level') { |v| options[:log_level] = v }
  opts.on('-c', '--config FILE', 'Config gile') { |v| options[:config] = v }
end.parse!

t = ChefTree.new(options)

t.logger = Logger.new(STDOUT)
case options[:log_level]
when 'debug'
  t.logger.level = Logger::DEBUG
when 'info'
  t.logger.level = Logger::INFO
when 'warn'
  t.logger.level = Logger::WARN
when 'error'
  t.logger.level = Logger::ERROR
when 'fatal'
  t.logger.level = Logger::FATAL
else
  t.logger.level = Logger::UNKNOWN
end

t.run
