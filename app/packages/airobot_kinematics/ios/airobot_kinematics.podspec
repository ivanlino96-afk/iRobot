Pod::Spec.new do |s|
 s.name = 'airobot_kinematics'
 s.version = '0.1.0'
 s.summary = 'Shared deterministic AiRobot kinematics'
 s.description = s.summary
 s.homepage = 'https://github.com/ivanlino96-afk/iRobot'
 s.license = { :file => '../LICENSE' }
 s.author = { 'AiRobot' => 'airobot@localhost' }
 s.source = { :path => '.' }
 s.source_files = 'Classes/**/*'
 s.dependency 'Flutter'
 s.platform = :ios, '13.0'
 s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17' }
 s.libraries = 'c++'
end
