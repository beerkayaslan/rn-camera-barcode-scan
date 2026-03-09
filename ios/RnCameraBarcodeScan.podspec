Pod::Spec.new do |s|
  s.name           = 'RnCameraBarcodeScan'
  s.version        = '1.0.0'
  s.summary        = 'High-performance barcode scanner for React Native Expo'
  s.description    = 'A barcode scanner component using AVFoundation on iOS and ML Kit on Android'
  s.author         = ''
  s.homepage       = 'https://github.com/'
  s.platforms      = { :ios => '15.0' }
  s.source         = { git: '' }
  s.static_framework = true
  s.license        = { type: 'MIT' }

  s.dependency 'ExpoModulesCore'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_COMPILATION_MODE' => 'wholemodule'
  }

  s.source_files = "**/*.swift"
end
