# Oynatıcı: VideoLAN'ın resmî MobileVLCKit'i (MKV, HEVC, gömülü altyazı; iOS'un kendi oynatıcısı bunları açmaz).
platform :ios, '17.0'

target 'Alpflix' do
  use_frameworks!
  pod 'MobileVLCKit', '~> 3.6.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    end
  end
end
