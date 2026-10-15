Pod::Spec.new do |s|
  s.name             = 'interceptly'
  s.version          = '2.1.0'
  s.summary          = 'Client-agnostic network and realtime inspector for Flutter.'
  s.homepage         = 'https://github.com/Tuanpluss02/interceptly'
  s.license          = { :type => 'MIT' }
  s.author           = { 'stormx' => 'dongoctuan2002sp@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'interceptly/Sources/interceptly/**/*.swift'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
end
