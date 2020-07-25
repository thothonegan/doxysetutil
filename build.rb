#!/usr/bin/env ruby

# Used with the hguild package system

# Will be handed where to install things, etc

require 'optparse'
require 'fileutils'

options = {}

OptionParser.new do |opts|
	opts.banner = "Usage: build.rb [command] [options]"

	opts.on("--sourceTree=PATH", "Path for the git repository") do |v|
		options[:repoPath] = v
	end

	opts.on("--profile=PROFILE", "The profile to build for.") do |v|
		options[:profile] = v
	end

	opts.on("--buildPath=PATH", "The path our build occurs in") do |v|
		options[:buildPath] = v
	end

	opts.on("--buildType=TYPE", "The type of build to make") do |v|
		options[:buildType] = v
	end

	opts.on("--installPath=PATH", "The location to install our files") do |v|
		options[:installPath] = v
	end
end.parse!

command = ARGV.shift

if command == "build_install"
    puts "-- Copying files: " + "#{options[:repoPath]}/doxysetutil.rb" + " to " + "#{options[:installPath]}/bin"

    FileUtils.mkdir_p "#{options[:installPath]}/bin"
    FileUtils.cp_r "#{options[:repoPath]}/doxysetutil.rb", "#{options[:installPath]}/bin/doxysetutil.rb"

	puts "-- Finished"
end
