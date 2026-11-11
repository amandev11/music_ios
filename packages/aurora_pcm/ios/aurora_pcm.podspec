Pod::Spec.new do |s|
  s.name             = 'aurora_pcm'
  s.version          = '0.0.1'
  s.summary          = 'AVFoundation PCM decoder for Automix.'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Aurora' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
end
