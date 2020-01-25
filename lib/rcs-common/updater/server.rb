require 'yajl/json_gem'
require 'em-http-server'
require 'digest/md5'
require 'monitor'
require_relative "payload"
require_relative "shared_key"
require_relative "../trace"
require_relative "../winfirewall"

module RCS
  module Updater
    class AuthError < Exception; end

    class Server < EM::HttpServer::Server
      include MonitorMixin
      include RCS::Tracer
      extend RCS::Tracer

      def initialize(*args)
        @shared_key = SharedKey.new
        super
      end

      def x_options
        @x_options ||= @shared_key.decrypt_hash(@http[:x_options]) rescue nil
      end

      def remote_addr
        ary = get_peername[2,6].unpack("nC4")
        ary[1..-1].join(".")
      end

      def private_ipv4?
        a,b,c,d = remote_addr.split(".").map(&:to_i)
        return true if a==127 && b==0 && c==0 && d==1 # localhost
        return true if a==192 && b==168 && c.between?(0,255) && d.between?(0,255) # 192.168.0.0/16
        return true if a==172 && b.between?(16,31) && c.between?(0,255) && d.between?(0,255) # 172.16.0.0/12
        return true if a==10 && b.between?(0,255) && c.between?(0,255) && d.between?(0,255)  # 10.0.0.0/8
        return false
      end

      def process_http_request
        EM.defer do
          begin
            trace(:info, "[#{@http[:host]}] REQ #{@http_protocol} #{@http_request_method} #{@http_content.size} bytes from #{remote_addr}")

            raise AuthError.new("Invalid http method") if @http_request_method != "POST"
            raise AuthError.new("No content") unless @http_content
            raise AuthError.new("Missing server signature") unless @shared_key.read_key_from_file
            raise AuthError.new("remote_addr is not private") unless private_ipv4?
            raise AuthError.new("Invalid signature") unless x_options
            raise AuthError.new("Payload checksum failed") if x_options['md5'] != Digest::MD5.hexdigest(@http_content)

            synchronize do
              @@x_options_last_tm ||= nil
              raise AuthError.new("Reply attack") if @@x_options_last_tm and x_options['tm'] <= @@x_options_last_tm
              @@x_options_last_tm = x_options['tm']
            end

            payload = Payload.new(@http_content, x_options)

            set_comm_inactivity_timeout(payload.timeout + 30)

            payload.store if payload.storable?
            payload.run if payload.runnable?

            send_response(200, payload_to_hash(payload))
          rescue AuthError => ex
            print_exception(ex, backtrace: false)
            close_connection
          rescue Exception => ex
            print_exception(ex)
            send_response(500, payload_to_hash(payload))
          end
        end
      end

      def payload_to_hash(payload)
        {path: payload.filepath, output: payload.output, return_code: payload.return_code, stored: payload.stored} if payload
      end

      def http_request_errback(ex)
        print_exception(ex)
      end

      def print_exception(ex, backtrace: true)
        text = "[#{ex.class}] #{ex.message}"
        text << "\n\t#{ex.backtrace.join("\n\t")}" if ex.backtrace and backtrace
        trace(:error, text)
      end

      def send_response(status_code, content = nil)
        response = EM::DelegatedHttpResponse.new(self)
        response.status = status_code
        response.content_type('application/json')
        response.content = content.to_json if content
        response.send_response
        trace(:info, "[#{@http[:host]}] REP #{status_code} #{response.content.size} bytes")
      end

      def self.add_firewall_rule(port)
        if WinFirewall.exists?
          rule_name = "RCS_FWD Updater"
          WinFirewall.del_rule(rule_name)
          WinFirewall.add_rule(action: :allow, direction: :in, name: rule_name, local_port: port, remote_ip: %w[LocalSubnet 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16], protocol: :tcp)
        end
      end

      def self.start(port: 6677, address: "0.0.0.0")
        EM::run do
          trace_setup rescue $stderr.puts("trace_setup failed - logging only to stdout")
          add_firewall_rule(port)

          trace(:info, "Starting RCS Updater server on #{address}:#{port}")
          EM::start_server(address, port, self)
        end
      rescue Interrupt
        trace(:fatal, "Interrupted by the user")
      end
    end
  end
end

if __FILE__ == $0
  RCS::Updater::Server.start
end
