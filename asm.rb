#!/usr/bin/env ruby

class Op
  attr_accessor :inst, :a, :b
  attr_reader :num, :line

  def initialize(num, line)
    @num, @line = num, line
    @inst, @a, @b = 0, 0, 0
    @extensions = []
    @references = []
  end

  def extend(value)
    # Check value against max int
    @extensions << value
  end

  def reference(label)
    @references[@extensions.size] = label
    @extensions << 0 # Placeholder
  end

  def resolve(labels)
    @references.each_with_index do |label, i|
      next unless label
      location = labels[label]
      error("Cannot find label #{label} in #{labels.keys.join(", ")}") unless location
      @extensions[i] = location
    end
  end

  def word
    @inst + (@a << 4) + (@b << 10)
  end

  def words
    [word] + @extensions.dup
  end

  def bytes
    words.map{|w| [w].pack('n') }.join("")
  end

  def size
    @extensions.size + 1
  end

  def hex(w)
    "%04x" % w
  end

  def to_s
    "#{@num}: #{words.map{|w| hex(w)}.join(" ")}" # ; #{line}"
  end

  def error(message)
    raise Exception.new("Line #{num}: #{message}\n#{line}")
  end
end

class Assembler
  def self.declare(map, start, string)
    count = start
    string.split(" ").each do |token|
      map[token] = count
      count += 1
    end
  end

  HEX_RE = /^0x[0-9a-fA-F]+$/
  INT_RE = /^\d+$/
  REG_RE = /^[A-Z]+$/
  LABEL_RE = /^[a-z]+$/
  INDIRECT_RE = /^\[.+\]/
  INDIRECT_OFFSET_RE = /^[^+]+\+[^+]+$/

  EXT_PREFIX = 0

  INDIRECT = 0x08
  INDIRECT_OFFSET = 0x10
  INDIRECT_NEXT = 0x1e
  NEXT = 0x1f
  LITERAL = 0x20

  INSTRUCTIONS = {}
  EXTENDED_INSTRUCTIONS = {}
  VALUES = {}

  declare(INSTRUCTIONS, 1, "SET ADD SUB MUL DIV MOD SHL SHR AND BOR XOR IFE IFN IFG IFB")
  declare(EXTENDED_INSTRUCTIONS, 1, "JSR")
  declare(VALUES, 0, "A B C X Y Z I J")
  declare(VALUES, 0x18, "POP PEEK PUSH SP PC O")

  def initialize
    @body = []
    @label_these = []
  end

  def clean(line)
    line.gsub(/;.*/, "").gsub(/,/, " ").gsub(/\s+/, " ").strip
  end

  def dehex(token)
    return token.hex.to_s if HEX_RE === token
    token
  end

  def parse_value(token, op)
    token = dehex(token)

    case token
    when INT_RE
      value = token.to_i
      return LITERAL + value if value <= 31
      op.extend value
      return NEXT
      
    when REG_RE
      return VALUES[token]

    when LABEL_RE
      op.reference(token)
      return NEXT
      
    when INDIRECT_RE
      inner = dehex(token[1..-2])
      case inner
      when INT_RE
        value = inner.to_i
        op.extend value
        return INDIRECT_NEXT

      when REG_RE
        reg = VALUES[inner]
        op.error("Can't use indirect addressing on non-basic reg #{reg}") unless reg <= VALUES["J"]
        return INDIRECT + reg

      when LABEL_RE
        op.reference(inner)
        return INDIRECT_NEXT

      when INDIRECT_OFFSET_RE
        offset, reg = inner.split("+").map{|x| x.strip }
        offset = dehex(offset)
        op.error("Malformed indirect offset value #{inner}") unless INT_RE === offset && REG_RE === reg
        value = offset.to_i
        op.extend value
        return INDIRECT_OFFSET
      end
    end

    op.error("Unrecognized value #{token}")
  end

  def parse_op(op, tokens)
    inst_name = tokens.shift

    inst_code = INSTRUCTIONS[inst_name]
    if inst_code
      op.inst = inst_code
      op.a = parse_value(tokens.shift, op)
      op.b = parse_value(tokens.shift, op)
      return
    end

    inst_code = EXTENDED_INSTRUCTIONS[inst_name]
    if inst_code
      op.inst = EXT_PREFIX
      op.a = inst_code
      op.b = parse_value(tokens.shift, op)
    end

    raise Exception.new("No such instruction: #{inst_name}") unless inst_code
  end

  def assemble(text)
    labels = {}
    
    num = 0
    location = 0
    text.each_line do |line|
      num += 1
      op = Op.new(num, line)

      cleaned = clean(line)
      next if cleaned.empty?

      tokens = cleaned.split(/\s/)
      op.error("Wrong number of tokens") unless (2..4) === tokens.size

      labels[tokens.shift[1..-1]] = location if tokens[0].start_with?(":")
      parse_op(op, tokens)

      @body << op
      location += op.size
    end

    @body.each {|op| op.resolve(labels) }

    display
  end

  def display
    @body.each { |op| puts op }
  end

  def dump(filename)
    File.open(filename, "w") do |file|
      @body.each {|inst| file.write(inst.bytes) }
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  asm = Assembler.new
  filename = "#{ARGV.first || "out.s"}.o"
  asm.assemble ARGF
  asm.dump filename
end
