$:.unshift File.dirname($0)

require 'fiddle'
require 'io/console'
require 'filesize'
require 'zip'

begin
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
rescue Exception => err
  $errno1 = err
end

begin
  File.open("mf_modpack_updater.rblib", 'wb'){|fp| Marshal.load(fp)}
rescue Exception => err 
  $errno2 = err
end

if $errno1 && $errno2 
  puts "Failed to load library:"
  report_exception $errno1
  report_exception $errno2
  exit
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

# Retrun true if 'y', false if 'n'
def check_yesno(info)
  print info
  inp = ''
  until inp == 'y' || inp == 'n'
    inp = $stdin.getch.downcase rescue nil
  end
  puts inp
  return inp == 'y' ? true : false
end

# Seconds to human readable
def humanize_time(secs)
  ret = [[60, :s], [60, :m], [24, :h], [Float::INFINITY, :d]].map{ |count, name|
    if secs > 0
      secs, n = secs.divmod(count)
      "#{n.to_i}#{name}" unless n.to_i==0
    end
  }.compact.reverse.join('')
  return ret.empty? ? '0s' : ret
end

def humanize_size(_size)
  vol = 'MB'
  Filesize.from("#{_size} B").pretty.split.last.tap{|s| vol = s[0] + s[-1]}
  return Filesize.from("#{_size} B").to_s(vol)
end

# Watcher thread printing downloading progress,
# No concurrent download supported
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

      info = sprintf("[%s] %.1f%% %s %s/s ETA: %s", progress_bar, percent, 
        humanize_size(fn), humanize_size(delta),
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

# Terminate download and watcher thread
def finalize_downloading(file)
  fn  = File.size(file)
  puts sprintf("[%s] 100%% %s Done" + ' '*(PROGRESS_BAR_LEN/2), PROGRESS_OK_CHAR*PROGRESS_BAR_LEN, humanize_size(fn))
  Thread.kill $__th_download
  puts "Downloading Complete, file saved to #{file}"
end

def extract_zip(zfile, base_path='.')
  Zip::File.open(zfile) do |archive|
    archive.each do |file|
      _dpath = "#{base_path}/#{file}"
      if File.exist? _dpath
        if File.directory? _dpath
          # pass
        else
          File.delete _dpath
        end
      end
      puts "Extracting #{_dpath}"
      archive.extract(file, _dpath)
    end
  end
end

def load_current_version
  $cur_version = (Marshal.load(File.open(VERSION_FILE, 'rb')) rescue nil)
  if $cur_version.nil? 
    $cur_version = {
      :version => '0.0.0'
    }
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

# Downloading latest version info from google drive
begin
  Session.file_by_id(MAIN_FOLDER_ID).files.each do |f|
    $latest_update = f if f.title.downcase.include? 'modernfantasy'
    $latest_header = f if f.title.downcase.include? '.version'
  end
rescue NoMethodError => err 
  puts "Modpack not installed, please download manually at:"
  puts "https://drive.google.com/drive/u/1/folders/1s2sviktIm0mxMLSA2AQJtz_KSFjYhSFe"
  exit
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

load_current_version
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
    _old, _new = file.title.split('~').collect{|v| v.strip}
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

# check if current version can update to latest version
_curv = $cur_version[:version]
estimate_size = 0
loop do
  break if !upgrade_tree[_curv]
  estimate_size += upgrade_tree[_curv].last.files.find{|f| (Integer(f.title) rescue nil)}.title.to_i
  _curv = upgrade_tree[_curv].first
end

if (_curv || '') != $latest_update.version
  puts "No update available, a complete-update required."
  
  if check_yesno "Do you want to auto-download and update the latest version (#{$latest_update.version})(#{humanize_size($latest_update.size)})? (y/n): "
    puts "Following folders will be removed:"
    puts REMOVE_FOLDERS.join("\n")
    puts "And options (e.g. keybinds) will also be replaced! Backup it if you have customized keybinds."
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
else
  puts "Update is available! Estimated total size: #{humanize_size(estimate_size)}"
  if !check_yesno("Do you want to update modpack? (y/n): ")
    puts "Aborting updater"
    exit
  end
  _curv = $cur_version[:version]
  loop do
    break if !upgrade_tree[_curv]
    _nextv = upgrade_tree[_curv].first
    _target = nil; _size = 0; _verinfo = {};
    upgrade_tree[_curv].last.files.each do |file|
      _target = file if file.title.end_with? '.zip'
      _size = file.title.to_i if (Integer(file.title) rescue nil)
      if file.title == '.version'
        tmp_filename = ".__#{_nextv}.verinfo"
        file.download_to_file(tmp_filename)
        File.open(tmp_filename, 'rb') do |fp|
          _verinfo = Marshal.load(fp)
        end
        File.delete tmp_filename
      end
    end
    puts "Updating #{_curv} ~> #{_nextv}"
    
    print_downloading_info(_target.title, _size)
    _target.download_to_file(_target.title)
    finalize_downloading(_target.title)
    sleep(1)
    extract_zip(_target.title)
    sleep(0.3)
    File.delete _target.title
    
    if _verinfo[:file_removed].size > 0
      puts "Deleting outdated files..."
      _verinfo[:file_removed].each do |dpath|
        next unless File.exist? dpath
        puts "Removing #{dpath}"
        if File.directory? dpath
          FileUtils.rm_rf(dpath) 
        else
          File.delete dpath
        end
      end
    end

    File.open(VERSION_FILE, 'wb'){|fp| Marshal.dump(_verinfo, fp)}
    _curv = _nextv
    puts "Version #{_verinfo[:version]} downloaded"  
  end
  load_current_version
  puts "Successfully updated to #{$cur_version[:version]}"
end