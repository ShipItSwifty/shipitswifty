require 'xcodeproj'

project = Xcodeproj::Project.open(File.join(__dir__, 'HelloWorld.xcodeproj'))
test_target = project.targets.find { |t| t.name == 'HelloWorldTests' }
raise "HelloWorldTests not found" unless test_target

test_target.build_configurations.each do |config|
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['DEVELOPMENT_TEAM'] = 'H3VJ3NCEU2'
  config.build_settings.delete('TEST_HOST')
  config.build_settings.delete('BUNDLE_LOADER')
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'org.reactjs.native.example.HelloWorldTests'
end

project.save
puts "Fixed HelloWorldTests build settings."
