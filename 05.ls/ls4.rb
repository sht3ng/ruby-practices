#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'etc'
require 'date'

COLUMN_COUNT = 3

def main
  options = ARGV.getopts('l')
  path    = ARGV[0] || Dir.pwd
  ls(path, option_l: options['l'])
end

def ls(path, option_l: false)
  files = read_files(path)
  return if files.empty?

  if option_l
    file_stats = read_file_stats(path, files)
    return ls_with_option_l(file_stats)
  end

  ls_with_no_options(files)
end

def read_files(path)
  raise ArgumentError, "#{File.basename(__FILE__)}: #{path}: No such file or directory" unless File.exist?(path) || File.symlink?(path)
  return Dir.glob('*', base: path) if File.directory?(path)

  [path]
end

def ls_with_no_options(files)
  row_count       = calculate_row_count(files)
  max_width       = calculate_max_width(files)
  formatted_files = format_files(files, row_count)
  printf_files(formatted_files, max_width)
end

def calculate_row_count(files)
  (files.size.to_f / COLUMN_COUNT).ceil
end

def calculate_max_width(files, margin = 1)
  files.map(&:length).max + margin
end

def format_files(files, row_count)
  sliced_files = files.each_slice(row_count).to_a
  sliced_files.last << nil while sliced_files.last.size < row_count
  sliced_files.transpose.map(&:compact)
end

def printf_files(formatted_files, max_width)
  formatted_files.each do |formatted_file|
    format_specifier = generate_format_specifier(formatted_file.size, max_width)
    printf format_specifier, *formatted_file
  end
end

def generate_format_specifier(column_count, max_width)
  base_format_specifier = "%-#{max_width}s"
  "#{base_format_specifier * column_count}\n"
end

def read_file_stats(path, files)
  file_stats = []
  files.each do |file|
    file_stat                 = {}
    fs                        = File.lstat("#{path}/#{file}")
    octal_type                = format('%06o', fs.mode)[0..1]
    octal_permissions         = format('%06o', fs.mode)[3..-1]
    octal_special_permissions = format('%06o', fs.mode)[2]
    file_stat[:type]          = translate_octal_type_into_symbol(octal_type)
    file_stat[:permissions]   = translate_octal_permissions_into_symbols(octal_permissions, octal_special_permissions)
    file_stat[:link]          = fs.nlink.to_s
    file_stat[:user]          = Etc.getpwuid(fs.uid).name
    file_stat[:group]         = Etc.getgrgid(fs.gid).name
    file_stat[:size]          = fs.size.to_s
    file_stat[:timestamp]     = generate_timestamp(fs.mtime)
    file_stat[:name]          = generate_file_name(path, file)
    file_stat[:blocks]        = fs.blocks

    file_stats << file_stat
  end

  file_stats
end

def ls_with_option_l(file_stats)
  format_specifier = generate_format_specifier_of_file_stats(file_stats)

  puts "total #{file_stats.map { |file_stat| file_stat[:blocks] }.sum}"
  file_stats.each do |file_stat|
    printf(format_specifier, file_stat)
  end
end

def generate_format_specifier_of_file_stats(file_stats)
  [
    "%<type>#{calculate_max_width_of_file_stats_element(file_stats, :type)}s",
    "%<permissions>#{calculate_max_width_of_file_stats_element(file_stats, :permissions)}s  ",
    "%<link>#{calculate_max_width_of_file_stats_element(file_stats, :link)}s ",
    "%<user>-#{calculate_max_width_of_file_stats_element(file_stats, :user)}s  ",
    "%<group>-#{calculate_max_width_of_file_stats_element(file_stats, :group)}s  ",
    "%<size>#{calculate_max_width_of_file_stats_element(file_stats, :size)}s ",
    "%<timestamp>#{calculate_max_width_of_file_stats_element(file_stats, :timestamp)}s ",
    "%<name>-#{calculate_max_width_of_file_stats_element(file_stats, :name)}s\n"
  ].join
end

def calculate_max_width_of_file_stats_element(file_stats, element)
  file_stats.map { |file_stat| file_stat[element].length }.max
end

def translate_octal_type_into_symbol(octal_type)
  {
    '01' => 'p',
    '02' => 'c',
    '04' => 'd',
    '06' => 'b',
    '10' => '-',
    '12' => 'l',
    '14' => 's'
  }[octal_type]
end

def translate_octal_permissions_into_symbols(octal_permissions, octal_special_permissions)
  symbolic_permissions = []
  octal_permissions.chars.each do |octal_permission|
    binary_permissions = format('%03b', octal_permission)
    symbolic_permissions << translate_binary_permissions_into_symbols(binary_permissions)
  end

  binary_special_permissions = format('%03b', octal_special_permissions)
  symbolic_permissions = overwrite_symbols_with_suid(symbolic_permissions, binary_special_permissions[0])
  symbolic_permissions = overwrite_symbols_with_sgid(symbolic_permissions, binary_special_permissions[1])
  symbolic_permissions = overwrite_symbols_with_stickybit(symbolic_permissions, binary_special_permissions[2])

  symbolic_permissions.join
end

def translate_binary_permissions_into_symbols(binary_permissions)
  list_of_permission_symbols = %w[r w x]
  symbolic_permissions       = []
  binary_permissions.chars.each_with_index do |permission, index|
    symbolic_permissions <<
      case permission
      when '1'
        list_of_permission_symbols[index]
      when '0'
        '-'
      end
  end

  symbolic_permissions
end

def overwrite_symbols_with_suid(symbolic_permissions, suid_permission)
  return symbolic_permissions if suid_permission == '0'

  symbolic_permissions[0][2] =
    case symbolic_permissions[0][2]
    when 'x'
      's'
    when '-'
      'S'
    end

  symbolic_permissions
end

def overwrite_symbols_with_sgid(symbolic_permissions, sgid_permission)
  return symbolic_permissions if sgid_permission == '0'

  symbolic_permissions[1][2] =
    case symbolic_permissions[1][2]
    when 'x'
      's'
    when '-'
      'S'
    end

  symbolic_permissions
end

def overwrite_symbols_with_stickybit(symbolic_permissions, stickybit_permission)
  return symbolic_permissions if stickybit_permission == '0'

  symbolic_permissions[2][2] =
    case symbolic_permissions[2][2]
    when 'x'
      't'
    when '-'
      'T'
    end

  symbolic_permissions
end

def generate_timestamp(time)
  timestamp = []
  timestamp << time.strftime('%_m')
  timestamp << time.strftime('%_d')
  timestamp <<
    if time.to_date.between?(Time.now.to_date << 6, Time.now.to_date >> 6)
      time.strftime('%H:%M')
    else
      time.year.to_s
    end
  timestamp.join(' ')
end

def generate_file_name(path, file)
  return "#{file} -> #{File.readlink("#{path}/#{file}")}" if File.symlink?("#{path}/#{file}")

  file
end

main if __FILE__ == $PROGRAM_NAME
