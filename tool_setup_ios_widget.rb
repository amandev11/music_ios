#!/usr/bin/env ruby
# Adds the AuroraWidget WidgetKit extension to ios/Runner.xcodeproj. Run on a Mac, after
# `python3 tool_setup.py` and `flutter pub get`:   ruby tool_setup_ios_widget.rb
# Needs the `xcodeproj` gem (installed with CocoaPods). Idempotent.
require 'xcodeproj'
require 'fileutils'

root = File.expand_path(__dir__)
proj_path = File.join(root, 'ios', 'Runner.xcodeproj')
abort 'ios/Runner.xcodeproj not found: run tool_setup.py first' unless File.exist?(proj_path)
project = Xcodeproj::Project.open(proj_path)
exit 0 if project.targets.any? { |t| t.name == 'AuroraWidget' }

src = File.join(root, 'native', 'ios')
dst = File.join(root, 'ios', 'AuroraWidget')
FileUtils.mkdir_p(dst)
%w[AuroraWidget.swift Info.plist AuroraWidget.entitlements].each { |f| FileUtils.cp(File.join(src, 'AuroraWidget', f), dst) }
FileUtils.cp(File.join(src, 'Runner.entitlements'), File.join(root, 'ios', 'Runner', 'Runner.entitlements'))

runner = project.targets.find { |t| t.name == 'Runner' }
runner_id = runner.build_configurations.first.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] || 'com.aurora.music'

widget = project.new_target(:app_extension, 'AuroraWidget', :ios, '16.0')
group = project.main_group.new_group('AuroraWidget', 'AuroraWidget')
swift = group.new_file('AuroraWidget.swift')
group.new_file('Info.plist')
group.new_file('AuroraWidget.entitlements')
widget.add_file_references([swift])
widget.add_system_frameworks(%w[SwiftUI WidgetKit])

widget.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = "#{runner_id}.AuroraWidget"
  s['INFOPLIST_FILE'] = 'AuroraWidget/Info.plist'
  s['CODE_SIGN_ENTITLEMENTS'] = 'AuroraWidget/AuroraWidget.entitlements'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['SKIP_INSTALL'] = 'YES'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['MARKETING_VERSION'] = '1.0'
  s['CURRENT_PROJECT_VERSION'] = '1'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
end

runner.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end
runner.add_dependency(widget)
ents = project.main_group['Runner'] || project.main_group.new_group('Runner', 'Runner')
ents.new_file('Runner.entitlements') unless ents.files.any? { |f| f.path == 'Runner.entitlements' }

embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
bf = embed.add_file_reference(widget.product_reference, true)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
# Flutter's "Thin Binary" phase must run after embedding or Xcode reports a dependency cycle.
thin = runner.build_phases.find { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
if thin
  runner.build_phases.delete(embed)
  runner.build_phases.insert(runner.build_phases.index(thin), embed)
end
project.save
puts 'AuroraWidget added. In Xcode set your Team for both Runner and AuroraWidget (Signing & Capabilities).'
