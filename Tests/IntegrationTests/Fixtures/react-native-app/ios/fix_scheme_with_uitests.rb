require 'xcodeproj'

project = Xcodeproj::Project.open(File.join(__dir__, 'HelloWorld.xcodeproj'))
app_target    = project.targets.find { |t| t.name == 'HelloWorld' }
unit_target   = project.targets.find { |t| t.name == 'HelloWorldTests' }
ui_target     = project.targets.find { |t| t.name == 'HelloWorldUITests' }
raise "Required targets not found" unless app_target && unit_target && ui_target

app_uuid      = app_target.uuid
unit_uuid     = unit_target.uuid
ui_uuid       = ui_target.uuid

scheme_path = File.join(__dir__, 'HelloWorld.xcodeproj/xcshareddata/xcschemes/HelloWorld.xcscheme')
scheme_xml = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <Scheme
     LastUpgradeVersion = "1210"
     version = "1.3">
     <BuildAction
        parallelizeBuildables = "YES"
        buildImplicitDependencies = "YES">
        <BuildActionEntries>
           <BuildActionEntry
              buildForTesting = "YES"
              buildForRunning = "YES"
              buildForProfiling = "YES"
              buildForArchiving = "YES"
              buildForAnalyzing = "YES">
              <BuildableReference
                 BuildableIdentifier = "primary"
                 BlueprintIdentifier = "#{app_uuid}"
                 BuildableName = "HelloWorld.app"
                 BlueprintName = "HelloWorld"
                 ReferencedContainer = "container:HelloWorld.xcodeproj">
              </BuildableReference>
           </BuildActionEntry>
           <BuildActionEntry
              buildForTesting = "YES"
              buildForRunning = "NO"
              buildForProfiling = "NO"
              buildForArchiving = "NO"
              buildForAnalyzing = "NO">
              <BuildableReference
                 BuildableIdentifier = "primary"
                 BlueprintIdentifier = "#{unit_uuid}"
                 BuildableName = "HelloWorldTests.xctest"
                 BlueprintName = "HelloWorldTests"
                 ReferencedContainer = "container:HelloWorld.xcodeproj">
              </BuildableReference>
           </BuildActionEntry>
           <BuildActionEntry
              buildForTesting = "YES"
              buildForRunning = "NO"
              buildForProfiling = "NO"
              buildForArchiving = "NO"
              buildForAnalyzing = "NO">
              <BuildableReference
                 BuildableIdentifier = "primary"
                 BlueprintIdentifier = "#{ui_uuid}"
                 BuildableName = "HelloWorldUITests.xctest"
                 BlueprintName = "HelloWorldUITests"
                 ReferencedContainer = "container:HelloWorld.xcodeproj">
              </BuildableReference>
           </BuildActionEntry>
        </BuildActionEntries>
     </BuildAction>
     <TestAction
        buildConfiguration = "Debug"
        selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
        selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
        shouldUseLaunchSchemeArgsEnv = "YES">
        <Testables>
           <TestableReference
              skipped = "NO">
              <BuildableReference
                 BuildableIdentifier = "primary"
                 BlueprintIdentifier = "#{unit_uuid}"
                 BuildableName = "HelloWorldTests.xctest"
                 BlueprintName = "HelloWorldTests"
                 ReferencedContainer = "container:HelloWorld.xcodeproj">
              </BuildableReference>
           </TestableReference>
           <TestableReference
              skipped = "NO">
              <BuildableReference
                 BuildableIdentifier = "primary"
                 BlueprintIdentifier = "#{ui_uuid}"
                 BuildableName = "HelloWorldUITests.xctest"
                 BlueprintName = "HelloWorldUITests"
                 ReferencedContainer = "container:HelloWorld.xcodeproj">
              </BuildableReference>
           </TestableReference>
        </Testables>
     </TestAction>
     <LaunchAction
        buildConfiguration = "Debug"
        selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
        selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
        launchStyle = "0"
        useCustomWorkingDirectory = "NO"
        ignoresPersistentStateOnLaunch = "NO"
        debugDocumentVersioning = "YES"
        debugServiceExtension = "internal"
        allowLocationSimulation = "YES">
        <BuildableProductRunnable
           runnableDebuggingMode = "0">
           <BuildableReference
              BuildableIdentifier = "primary"
              BlueprintIdentifier = "#{app_uuid}"
              BuildableName = "HelloWorld.app"
              BlueprintName = "HelloWorld"
              ReferencedContainer = "container:HelloWorld.xcodeproj">
           </BuildableReference>
        </BuildableProductRunnable>
     </LaunchAction>
     <ProfileAction
        buildConfiguration = "Release"
        shouldUseLaunchSchemeArgsEnv = "YES"
        savedToolIdentifier = ""
        useCustomWorkingDirectory = "NO"
        debugDocumentVersioning = "YES">
        <BuildableProductRunnable
           runnableDebuggingMode = "0">
           <BuildableReference
              BuildableIdentifier = "primary"
              BlueprintIdentifier = "#{app_uuid}"
              BuildableName = "HelloWorld.app"
              BlueprintName = "HelloWorld"
              ReferencedContainer = "container:HelloWorld.xcodeproj">
           </BuildableReference>
        </BuildableProductRunnable>
     </ProfileAction>
     <AnalyzeAction
        buildConfiguration = "Debug">
     </AnalyzeAction>
     <ArchiveAction
        buildConfiguration = "Release"
        revealArchiveInOrganizer = "YES">
     </ArchiveAction>
  </Scheme>
XML

File.write(scheme_path, scheme_xml)
puts "Scheme updated with unit and UI test targets."
