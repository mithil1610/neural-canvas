require 'xcodeproj'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

runner_target = project.targets.find { |t| t.name == 'Runner' }
runner_target.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

# Auto-link GoogleService-Info.plist
runner_group = project.main_group.find_subpath(File.join('Runner'), true)
gs_plist = runner_group.files.find { |f| f.path == 'GoogleService-Info.plist' } || runner_group.new_file('GoogleService-Info.plist')
if !runner_target.resources_build_phase.files_references.include?(gs_plist)
  runner_target.resources_build_phase.add_file_reference(gs_plist)
end

# Check if target already exists to prevent duplication
if project.targets.any? { |t| t.name == 'ShareExtension' }
  puts "ShareExtension already exists. Saving entitlements and exiting."
  project.save
  exit
end

ext_target = project.new_target(:app_extension, 'ShareExtension', :ios, '15.0')

ext_group = project.main_group.find_subpath(File.join('ShareExtension'), true)
ext_group.set_source_tree('<group>')
ext_group.set_path('ShareExtension')

swift_file = ext_group.new_file('ShareViewController.swift')
plist_file = ext_group.new_file('Info.plist')

ext_target.source_build_phase.add_file_reference(swift_file)

project.root_object.attributes['TargetAttributes'] ||= {}
project.root_object.attributes['TargetAttributes'][ext_target.uuid] = {
  'CreatedOnToolsVersion' => '14.0'
}

ext_target.build_configurations.each do |config|
  config.build_settings['INFOPLIST_FILE'] = 'ShareExtension/Info.plist'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.mithil.neuralcanvas.ShareExtension'
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
end

# Embed the extension into the Runner app
embed_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
embed_phase.name = 'Embed Foundation Extensions'
embed_phase.symbolic_dst_subfolder_spec = :plug_ins
embed_phase.dst_path = ''
runner_target.build_phases << embed_phase

build_file = embed_phase.add_file_reference(ext_target.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

project.save
puts "Successfully configured Runner.entitlements and injected ShareExtension target into xcodeproj."
