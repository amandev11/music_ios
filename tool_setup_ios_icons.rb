#!/usr/bin/env ruby
# Adds the alternate home-screen icons (ios_icons/<id>@2x.png, @3x.png) to the Runner target and Info.plist. Idempotent.
require 'xcodeproj'
require 'fileutils'

root = File.expand_path(__dir__)
proj_path = File.join(root, 'ios', 'Runner.xcodeproj')
abort 'ios/Runner.xcodeproj not found: run tool_setup.py first' unless File.exist?(proj_path)
project = Xcodeproj::Project.open(proj_path)
runner = project.targets.find { |t| t.name == 'Runner' }
dest = File.join(root, 'ios', 'Runner', 'AltIcons')
FileUtils.mkdir_p(dest)
group = project.main_group['Runner'] || project.main_group.new_group('Runner', 'Runner')
alt = group['AltIcons'] || group.new_group('AltIcons', 'AltIcons')

ids = []
Dir.glob(File.join(root, 'ios_icons', '*@3x.png')).sort.each do |f|
  id = File.basename(f, '@3x.png')
  next if id == 'keycapkeystone' # the primary icon comes from the asset catalog
  ids << id
  %w[@2x @3x].each do |suffix|
    name = "#{id}#{suffix}.png"
    FileUtils.cp(File.join(root, 'ios_icons', name), File.join(dest, name))
    next if alt.files.any? { |r| r.path == name }
    ref = alt.new_file(name)
    runner.resources_build_phase.add_file_reference(ref)
  end
end
project.save

plist_path = File.join(root, 'ios', 'Runner', 'Info.plist')
plist = Xcodeproj::Plist.read_from_path(plist_path)
alternates = {}
ids.each { |id| alternates[id] = { 'CFBundleIconFiles' => [id], 'UIPrerenderedIcon' => false } }
icons = plist['CFBundleIcons'] || {}
icons['CFBundleAlternateIcons'] = alternates
plist['CFBundleIcons'] = icons
plist['CFBundleIcons~ipad'] = icons
Xcodeproj::Plist.write_to_path(plist, plist_path)
puts "Added #{ids.length} alternate icons."
