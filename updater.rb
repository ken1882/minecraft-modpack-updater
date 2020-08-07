require 'fiddle'
require 'io/console'
require 'filesize'
require 'zip'

# Load API library
class RubyVM::InstructionSequence
  load_fn_addr = Fiddle::Handle::DEFAULT['rb_iseq_load']
  load_fn = Fiddle::Function.new(load_fn_addr, [Fiddle::TYPE_VOIDP] * 3, Fiddle::TYPE_VOIDP)

  define_singleton_method(:load) do |data, parent = nil, opt = nil|
    load_fn.call(Fiddle.dlwrap(data), parent, opt).to_value
	end
end

File.open('mf_modpack_updater.so', 'rb') do |fp|
  RubyVM::InstructionSequence.load(Marshal.load(fp)).eval
end

# Disable warning
module Warning
  def self.warn(*args)
  end
end

def report_exception(error, ex_caller=[])
  backtrace = [] + error.backtrace + ex_caller
  error_line = backtrace.first
  backtrace[0] = ''
  err_class = " (#{error.class})"
  back_trace_txt = backtrace.join("\n\tfrom ")
  error_txt = sprintf("%s %s %s %s %s %s",error_line, ": ", error.message, err_class, back_trace_txt, "\n" )
  print error_txt
  return error_txt
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

def extract_zip(zfile, base_path='.')
  Zip::File.open(zfile) do |archive|
    archive.each do |file|
      _dpath = "#{base_path}/#{file}"
      if File.exist? _dpath
        if File.directory? _dpath
          FileUtils.rm_rf _dpath
        else
          File.delete _dpath
        end
      end
      puts "Extracting #{_dpath}"
      archive.extract(file, _dpath)
    end
  end
end

if !File.exist?("mods/")
  puts "Mods folder (mods/) not found!"
  puts "Please put the update in the minecraft folder and try again..."
  puts "Or download and extract the modpack manually at:"
  puts "https://drive.google.com/drive/u/1/folders/1s2sviktIm0mxMLSA2AQJtz_KSFjYhSFe"
  exit
end

MAIN_FOLDER_ID = '1s2sviktIm0mxMLSA2AQJtz_KSFjYhSFe'
UPDATE_FOLDER_ID = '1BFgEAjTIWglRL8HIStkXxkRgl8MFAVAj'
VERSION_FILE = ".version"

Session.file_by_id(MAIN_FOLDER_ID).files.each do |f|
  $latest_update = f if f.title.downcase.include? 'modernfantasy'
  $latest_header = f if f.title.downcase.include? '.version'
end

if !$latest_header
  puts "ERROR: Header file missing"
  exit
end

$latest_header.download_to_file('.__latestversion')
File.open('.__latestversion', 'rb'){|fp| $latest_header = Marshal.load(fp)}
File.delete '.__latestversion'

class << $latest_update
  attr_reader :version, :size
  def initialize
    return unless title =~ /v(\d+)\.(\d+)\.(\d+)/i
    @version = "#{$1}.#{$2}.#{$3}"
    @size = $latest_header[:size]
  end
end
$latest_update.initialize

$cur_version = (Marshal.load(File.open(VERSION_FILE, 'rb')) rescue nil)
if $cur_version.nil? 
  $cur_version = {
    :version => '0.0.0'
  }
end
puts "Latest version:  #{$latest_update.version}"
puts "Current version: #{$cur_version[:version]}"

filename = $latest_update.title

if $cur_version[:version] >= $latest_update.version 
  puts "\nYour modpack is up to update, nice!"
  exit
end

upgrade_tree = {}

Session.file_by_id(UPDATE_FOLDER_ID).files.each do |file|
  begin
    _old, _new = file.title.split('~>').collect{|v| v.strip}
    puts "An update is detected: #{_old} ~> #{_new}" if _old >= $cur_version[:version]
    upgrade_tree[_old] = [_new, file]
  rescue Exception => err
  end
end

REMOVE_FOLDERS = [
  'config/',
  'mods/',
  'scripts/',
  'Flan/',
  'resourcespacks/',
  'shaderpacks/'
]

if !upgrade_tree[$cur_version[:version]]
  puts "No update available, a complete-update required."
  
  if check_yesno "Do you want to auto-download and update the latest version (#{$latest_update.version})(#{Filesize.from("#{$latest_update.size} B").to_s("MB")})? (y/n): "
    puts "Following folders will be removed:"
    puts REMOVE_FOLDERS.join("\n")
    puts "And options (e.g. keybinds) will also be replaced!"
    if check_yesno "Continue? (y/n): "
      _filename = $latest_update.title
      print_downloading_info(_filename, $latest_update.size)
      $latest_update.download_to_file(_filename)
      finalize_downloading(_filename)
      extract_zip(_filename)
      puts "Complete!"
      if check_yesno "Remove downloaded zip file? (y/n)"
        File.delete _filename
      else
      end
    else
      puts "Aborting updater"
      exit
    end
  else
    puts "Aborting updater"
    exit
  end
end