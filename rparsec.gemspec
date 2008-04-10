require 'rake'

spec = Gem::Specification.new do |s|
  s.name = 'rparsec'
  s.version = '1.0'
  s.summary = 'A Ruby Parser Combinator Framework'
  s.description = 'rparsec is a recursive descent parser combinator framework. Declarative API allows creating parser intuitively and dynamically.'
  s.author = 'Ben Yu'
  s.email = 'ajoo.email@gmail.com'
  s.files = FileList['rparsec/*.rb','rparsec.rb']
  s.test_files = FileList['test/src/*.rb']
  s.has_rdoc = true
  s.require_paths=['.']
  s.autorequire='rparsec'
end