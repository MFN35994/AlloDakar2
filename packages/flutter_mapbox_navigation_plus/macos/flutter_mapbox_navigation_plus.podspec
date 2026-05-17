#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_mapbox_navigation.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_mapbox_navigation_plus'
  s.version          = '1.0.0'
  s.summary          = 'An updated fork of flutter_mapbox_navigation with support for the latest Flutter and Gradle versions.'
  s.description      = <<-DESC
An updated fork of flutter_mapbox_navigation with support for the latest Flutter and Gradle versions.
                       DESC
  s.homepage         = 'https://github.com/talharehmandev/flutter_mapbox_navigation_plus'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Emmanuel Peter Oche' => 'eopeter@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
