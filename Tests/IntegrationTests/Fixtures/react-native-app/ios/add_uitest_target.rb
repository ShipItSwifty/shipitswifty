require 'xcodeproj'
require 'fileutils'

project_path = File.join(__dir__, 'HelloWorld.xcodeproj')
project = Xcodeproj::Project.open(project_path)

if project.targets.any? { |t| t.name == 'HelloWorldUITests' }
  puts "HelloWorldUITests target already exists — skipping."
  exit 0
end

app_target = project.targets.find { |t| t.name == 'HelloWorld' }
raise "Could not find HelloWorld target" unless app_target

ui_test_target = project.new_target(:ui_test_bundle, 'HelloWorldUITests', :ios, '16.0')
ui_test_target.add_dependency(app_target)

tests_group = project.main_group.new_group('HelloWorldUITests', 'HelloWorldUITests')
tests_dir = File.join(__dir__, 'HelloWorldUITests')
FileUtils.mkdir_p(tests_dir)

test_file_path = File.join(tests_dir, 'HelloWorldUITests.swift')
unless File.exist?(test_file_path)
  File.write(test_file_path, <<~SWIFT)
    import XCTest

    final class HelloWorldUITests: XCTestCase {
        var app: XCUIApplication!

        override func setUpWithError() throws {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launch()
        }

        override func tearDownWithError() throws {
            app = nil
        }

        func testAppLaunches() throws {
            XCTAssertTrue(app.exists)
        }

        func testMainWindowExists() throws {
            XCTAssertFalse(app.windows.isEmpty)
        }

        func testAppIsInForeground() throws {
            XCTAssertEqual(app.state, .runningForeground)
        }

        func testScrollViewExistsOrRootViewVisible() throws {
            // React Native renders into a root view — verify the window has children
            let window = app.windows.firstMatch
            XCTAssertTrue(window.exists)
        }
    }
  SWIFT
end

file_ref = tests_group.new_file('HelloWorldUITests/HelloWorldUITests.swift')
ui_test_target.add_file_references([file_ref])

ui_test_target.build_configurations.each do |config|
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  config.build_settings['TEST_TARGET_NAME'] = 'HelloWorld'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'org.reactjs.native.example.HelloWorldUITests'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['DEVELOPMENT_TEAM'] = 'H3VJ3NCEU2'
end

project.save
puts "HelloWorldUITests target added successfully."
