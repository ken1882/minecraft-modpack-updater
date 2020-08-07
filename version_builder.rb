VERSION = "1.7.0"

FILE_REMOVED = %{
	
}.split(/[\r\n]+/).collect do |line|
	next unless line && !line.strip.empty?
	line
end
FILE_REMOVED.compact!

data = {
	:version => VERSION,
	:file_removed => FILE_REMOVED,
	:size => Dir.glob("*#{VERSION}*").collect{|f| File.size(f)}.max
}

File.open(".version", 'wb') do |fp|
	Marshal.dump(data, fp)
end

p data