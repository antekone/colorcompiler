require 'optparse'
require 'hjson'

def main(args)
  options = {}
  filenames = OptionParser.new { |opts|
    opts.banner = "usage: Compiler.rb [options] filenames..."

    opts.on("-h", "--help", "Show this help screen") { |v|
      puts "ColorCompiler v1.1 (C)opyright by Grzegorz Antoniak"
      puts ""
      puts opts
      puts ""
      puts "All filenames will be merged to one output file."
      exit 1
    }

    opts.on("-o", "--output FILENAME", "Generate file named FILENAME") { |name|
      options[:output] = name
    }
  }.parse!()

  if !options.has_key?(:output)
    puts "Error: no `--output` switch found! I need it."
    puts "Use `--help` to get some help."
    exit 1
  end

  if filenames.size == 0
    puts "Error: no input file was specified."
    puts "Use `--help` to get some help."
    exit 1
  end

  run(filenames, options)
end

def run(filenames, options)
  context = {}
  filenames.each() { |filename|
    compile_file(context, filename)
  }

  generate_binary(context, options[:output])
end

def compile_file(context, filename)
  File.open(filename) { |fp|
    compile_hjson(context, Hjson.parse(fp.read))
  }
end

def compile_hjson(context, hjson)
  hjson.each() do |theme_object|
    theme_name, theme_object = theme_object

    add_theme_object(context, theme_name, theme_object)
  end
end

def add_theme_object(context, theme_name, theme_object)
  return if context.has_key?(theme_name)

  puts("Adding theme '#{theme_name}'...")
  context[theme_name] = theme_object
end

def build_intern_dict(context)
  intern = Hash.new(0)

  context.each() { |theme_name, theme_object|
    intern[theme_name] += 1
    theme_object['colors'].each() { |color_name, color_string|
      intern[color_name] += 1
    }
  }

  intern
end

def make_seq(intern)
  seq = []
  intern.each() do |name, count|
    seq << name
  end
  seq
end

def generate_binary(context, output_filename)
  intern = build_intern_dict(context)
  intern_seq = make_seq(intern)

  File.open(output_filename, 'wb') { |fw|
    offset = 0x20
    data = [0xa1, 0xa2, 0x00, 0x01, 1, 2, offset].pack("C4N3")
    padding = [0] * (offset - data.size)

    fw.write(data)
    fw.write(padding.pack("C#{offset - data.size}"))

    # Write interns
    fw.write([0x1F, intern.size].pack("CN"))
    intern.each() do |name, _|
      fw.write([name.size, name].pack("NA*"))
    end

    # Write colors
    fw.write([0x80, context.size].pack("CN"))
    context.each() { |theme_name, theme_object|
      theme_name_idx = intern_seq.index(theme_name)
      num_of_colors = theme_object['colors'].size

      puts "Theme name: '%s', idx: %d" % [theme_name, theme_name_idx]
      puts "Number of colors: %d" % [num_of_colors]

      fw.write([theme_name_idx, num_of_colors].pack("NC"))

      theme_object['colors'].each() { |color_name, color_text|
        color_name_idx = intern_seq.index(color_name)
        color_value = calculate_color(color_text)

        puts "Color: %s, text: %s, value: %x" % [color_name, color_text, color_value]

        fw.write([color_name_idx, color_value].pack("NN"))
      }
    }

    # Write map entries
  }
end

def parsenum(num)
  num = num.strip
  if num.index("0x") == 0
    num.to_i(16)
  else
    num.to_i(10)
  end
end

def calculate_color(text)
  if text =~ /^rgb\((.*?),(.*?),(.*?)\)$/
    r = parsenum($1)
    g = parsenum($2)
    b = parsenum($3)
    return ("%02x%02x%02x" % [r, g, b]).to_i(16)
  elsif text=~ /^argb\((.*?),(.*?),(.*?),(.*?)\)$/
    a = parsenum($1)
    r = parsenum($2)
    g = parsenum($3)
    b = parsenum($4)
    return ("%02x%02x%02x%02x" % [a, r, g, b]).to_i(16)
  elsif text =~ /^0x(.*)$/
    num = $1.strip
    return num.to_i(16)
  else
    puts "Syntax error, invalid color encoding: %s" % text
    exit 1
  end
end

main(ARGV)
