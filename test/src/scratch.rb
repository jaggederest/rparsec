require 'benchmark'
require 'strscan'

require 'a'
puts __FILE__
str = ''
N = 10
N.times{str << 'abc'}

def scanner
  StringScanner.new(str)
end

ptn1 = /bc/
ptn2 = /^bc/

Benchmark.bm do |x|
  x.report("check with anchor") {N.times{StringScanner.new(str).scan(ptn2)}}
  x.report("check without anchor") {N.times{StringScanner.new(str).scan(ptn1)}}
  x.report("check_until with anchor") {N.times{StringScanner.new(str).check_until(ptn2)}}
  x.report("check_until without anchor") {N.times{StringScanner.new(str).check_until(ptn1)}}
  x.report("=~ with anchor") {N.times{ptn2 =~ str}}
  x.report("=~ without anchor") {N.times{ptn1 =~ str[N/2,N]}}
end
