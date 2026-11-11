#!/usr/bin/env ruby
# Adds Siri / App Intents support (native/ios/Runner/AuroraIntents.swift) to the Runner target. Idempotent.
require 'xcodeproj'
require 'fileutils'

root = File.expand_path(__dir__)
proj_path = File.join(root, 'ios', 'Runner.xcodeproj')
abort 'ios/Runner.xcodeproj not found: run tool_setup.py first' unless File.exist?(proj_path)
project = Xcodeproj::Project.open(proj_path)
runner = project.targets.find { |t| t.name == 'Runner' }
exit 0 if runner.source_build_phase.files_references.any? { |f| f && f.path == 'AuroraIntents.swift' }

FileUtils.cp(File.join(root, 'native', 'ios', 'Runner', 'AuroraIntents.swift'), File.join(root, 'ios', 'Runner', 'AuroraIntents.swift'))
group = project.main_group['Runner'] || project.main_group.new_group('Runner', 'Runner')
ref = group.new_file('AuroraIntents.swift')
runner.add_file_references([ref])
runner.add_system_frameworks(%w[AppIntents])
runner.build_configurations.each { |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0' }
project.save
puts 'Siri intents added to Runner.'
