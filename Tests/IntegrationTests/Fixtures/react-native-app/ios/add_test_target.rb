require 'xcodeproj'

project_path = File.join(__dir__, 'HelloWorld.xcodeproj')
project = Xcodeproj::Project.open(project_path)

# Skip if test target already exists
if project.targets.any? { |t| t.name == 'HelloWorldTests' }
  puts "HelloWorldTests target already exists — skipping."
  exit 0
end

app_target = project.targets.find { |t| t.name == 'HelloWorld' }
raise "Could not find HelloWorld target" unless app_target

# Add test target
test_target = project.new_target(:unit_test_bundle, 'HelloWorldTests', :ios, '16.0')
test_target.add_dependency(app_target)

# Create Tests group and file
tests_group = project.main_group.new_group('HelloWorldTests', 'HelloWorldTests')
tests_dir = File.join(__dir__, 'HelloWorldTests')
FileUtils.mkdir_p(tests_dir)

test_file_path = File.join(tests_dir, 'HelloWorldTests.swift')
unless File.exist?(test_file_path)
  File.write(test_file_path, <<~SWIFT)
    import XCTest

    final class HelloWorldTests: XCTestCase {
        func testAppBundleIdentifierIsSet() {
            let bundleID = Bundle.main.bundleIdentifier
            // In a unit test host, bundle ID comes from the test runner — just assert it's non-nil.
            XCTAssertNotNil(bundleID)
        }

        func testBasicArithmetic() {
            XCTAssertEqual(2 + 2, 4)
        }

        func testStringOperations() {
            let appName = "HelloWorld"
            XCTAssertFalse(appName.isEmpty)
            XCTAssertTrue(appName.hasPrefix("Hello"))
        }
    }
  SWIFT
end

file_ref = tests_group.new_file('HelloWorldTests/HelloWorldTests.swift')
test_target.add_file_references([file_ref])

# Wire build settings
test_target.build_configurations.each do |config|
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  config.build_settings['TEST_HOST'] = "$(BUILT_PRODUCTS_DIR)/HelloWorld.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/HelloWorld"
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'org.reactjs.native.example.HelloWorldTests'
end

project.save
puts "HelloWorldTests target added successfully."
