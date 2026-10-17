#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'lumina_mouse_capture'
  s.version          = '0.0.1'
  s.summary          = 'Pointer capture for Lumina on macOS.'
  s.description      = <<-DESC
Pointer lock and relative mouse motion for Lumina on macOS using CoreGraphics and AppKit.
                       DESC
  s.homepage         = 'https://github.com/LuminaGame/tools'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Lumina' => 'dev@luminagame.org' }

  s.source           = { :path => '.' }
  s.source_files     = 'lumina_mouse_capture/Sources/lumina_mouse_capture/**/*.swift'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
