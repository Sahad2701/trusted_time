#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint trusted_time.podspec` to validate before publishing.
#
require 'pathname'
pubspec_path = Pathname.new(File.join(__dir__, '..', 'pubspec.yaml'))
version = pubspec_path.read[/version: (.*)/, 1].strip

Pod::Spec.new do |s|
  s.name             = 'trusted_time'
  s.version          = version
  s.summary          = 'Tamper-proof, multi-source trusted time for Flutter.'
  s.description      = <<-DESC
A high-integrity time engine that provides reliable timestamps immune to system clock manipulation by anchoring network time to hardware monotonic oscillators.
                       DESC
  s.homepage         = 'https://github.com/Sahad2701/trusted_time'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'TrustedTime Maintainers' => 'https://github.com/Sahad2701/trusted_time' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
