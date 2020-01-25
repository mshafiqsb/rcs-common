require 'rcs-common/evidence/common'

module RCS

module ScreenshotEvidence
  
  SCREENSHOT_VERSION = 2009031201
  
  def content
    path = File.join(File.dirname(__FILE__), 'content', 'screenshot', '00' + (rand(3) + 1).to_s + '.jpg')
    File.open(path, 'rb') {|f| f.read }
  end
  
  def generate_content
    [ content ]
  end
  
  def additional_header
    process_name = 'ruby'.to_utf16le_binary
    window_name = 'Ruby Backdoor!'.to_utf16le_binary
    header = StringIO.new
    header.write [SCREENSHOT_VERSION, process_name.size, window_name.size].pack("I*")
    header.write process_name
    header.write window_name
    
    header.string
  end
  
  def decode_additional_header(data)
    raise EvidenceDeserializeError.new("incomplete SCREENSHOT") if data.nil? or data.bytesize == 0

    binary = StringIO.new data

    version, process_name_len, window_name_len = binary.read(12).unpack("I*")
    raise EvidenceDeserializeError.new("invalid log version for SCREENSHOT") unless version == SCREENSHOT_VERSION

    ret = Hash.new
    ret[:data] = Hash.new
    ret[:data][:program] = binary.read(process_name_len).utf16le_to_utf8
    ret[:data][:window] = binary.read(window_name_len).utf16le_to_utf8
    return ret
  end

  def decode_content(common_info, chunks)
    info = Hash[common_info]
    info[:data] ||= Hash.new
    info[:grid_content] = chunks.join
    yield info if block_given?
    :delete_raw
  end
end

end # ::RCS