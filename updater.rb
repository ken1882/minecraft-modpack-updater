RubyVM::InstructionSequence.load_from_binary(File.read('mf_modpack_updater.so')).eval
require 'io/console'
require 'filesize'

module Warning
  def self.warn(*args)
  end
end

PROGRESS_BAR_LEN = 40
PROGRESS_OK_CHAR   = '='
PROGRESS_WAIT_CHAR = '-'
STDOUT.sync = false

puts %{
  __  __           _                 
 |  \\/  | ___   __| | ___ _ __ _ __  
 | |\\/| |/ _ \\ / _` |/ _ \\ '__| '_ \\ 
 | |  | | (_) | (_| |  __/ |  | | | |
 |_|  |_|\\___/ \\__,_|\\___|_|  |_| |_|
 _____           _                  
 |  ___|_ _ _ __ | |_ __ _ ___ _   _ 
 | |_ / _` | '_ \\| __/ _` / __| | | |
 |  _| (_| | | | | || (_| \\__ \\ |_| |
 |_|  \\__,_|_| |_|\\__\\__,_|___/\\__, |
                               |___/ 
  _   _           _       _            
 | | | |_ __   __| | __ _| |_ ___ _ __ 
 | | | | '_ \\ / _` |/ _` | __/ _ \\ '__|
 | |_| | |_) | (_| | (_| | ||  __/ |   
  \\___/| .__/ \\__,_|\\__,_|\\__\\___|_|   
       |_|                             

}

def check_yesno(info)
  print info
  inp = ''
  until inp == 'y' || inp == 'n'
    inp = $stdin.getch.downcase rescue nil
  end
  puts inp
  return inp == 'y' ? true : false
end

def humanize_time(secs)
  ret = [[60, :s], [60, :m], [24, :h], [Float::INFINITY, :d]].map{ |count, name|
    if secs > 0
      secs, n = secs.divmod(count)

      "#{n.to_i}#{name}" unless n.to_i==0
    end
  }.compact.reverse.join('')
  return ret.empty? ? '0s' : ret
end

def print_downloading_info(file, total_size)
  $__th_download = Thread.new{
    last_fsize = 0
    max_len = 0
    loop do 
      sleep(1)
      fn = File.size(file) rescue nil
      fn ||= 0
      percent = fn * 100.0 / total_size
      ok_t = (percent / (100.0 / PROGRESS_BAR_LEN)).to_i
      progress_bar = ''
      ok_t.times{progress_bar += PROGRESS_OK_CHAR}
      (PROGRESS_BAR_LEN - ok_t).times{progress_bar += PROGRESS_WAIT_CHAR}

      delta = fn - last_fsize
      vol_ok = vol_spd = nil

      # iB to B
      Filesize.from("#{fn} B").pretty.split.last.tap{|s| vol_ok = s[0] + s[-1]}
      Filesize.from("#{delta} B").pretty.split.last.tap{|s| vol_spd = s[0] + s[-1]}
    
      info = sprintf("[%s] %.1f%% %s %s/s ETA: %s", progress_bar, percent, 
        Filesize.from("#{fn} B").to_s(vol_ok), Filesize.from("#{delta} B").to_s(vol_spd),
        delta == 0 ? '0s' : humanize_time(((total_size - fn) / delta).to_i)
      )

      # clear previous output
      if info.length < max_len
        (max_len - info.length).times{ info += ' '}
        max_len = info.length
      else
        max_len = info.length
      end
      print "#{info}\r"
      
     last_fsize = fn
    end
  }
end

def finalize_downloading(file)
  fn  = File.size(file)
  vol = Filesize.from("#{fn} B").pretty.split.last.tap{|s| s[0] + s[-1]}
  puts sprintf("[%s] 100%% %s Done" + ' '*(PROGRESS_BAR_LEN/2), PROGRESS_OK_CHAR*PROGRESS_BAR_LEN, Filesize.from("#{fn} B").to_s(vol))
  Thread.kill $__th_download
  puts "Downloading Complete, file saved to #{file}"
end

MAIN_FOLDER_ID = '1s2sviktIm0mxMLSA2AQJtz_KSFjYhSFe'
UPDATE_FOLDER_ID = '1BFgEAjTIWglRL8HIStkXxkRgl8MFAVAj'
VERSION_FILE = ".version"

$latest_update = Session.file_by_id(MAIN_FOLDER_ID).files.find{|f| f.title.downcase.include? 'modernfantasy'}
class << $latest_update
  attr_reader :version
  def initialize
    return unless title =~ /v(\d+)\.(\d+)\.(\d+)/i
    @version = "#{$1}.#{$2}.#{$3}"
  end
end
$latest_update.initialize

$cur_version = (Marshal.load(File.open(VERSION_FILE, 'rb')) rescue nil)
puts "Latest version:  #{$latest_update.version}"
puts "Current version: #{$cur_version[:version]}"

filename = $latest_update.title

if $cur_version[:version] >= $latest_update.version 
  puts "\nYour modpack is up to update, nice!"
end

if check_yesno("Verify file integrity? (y/n): ")
else
end