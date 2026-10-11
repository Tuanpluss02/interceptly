Pod::Spec.new do |s|
  s.name             = 'interceptly'
  s.version          = '1.2.0'
  s.summary          = 'Flutter network inspector with hand-rolled file share.'
  s.homepage         = 'https://github.com/Tuanpluss02/interceptly'
  s.license          = { :type => 'MIT' }
  s.author           = { 'stormx' => 'dongoctuan2002sp@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'
  s.swift_version    = '5.0'
end
