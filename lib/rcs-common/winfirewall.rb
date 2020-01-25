require 'resolv'
require 'timeout'
require_relative 'trace'
require_relative 'resolver'

module RCS
  module Common
    module WinFirewall
      extend RCS::Tracer

      # Represent a Windows Firewall rule.
      class Rule
        include Resolver

        ATTRIBUTES = %i[direction action local_ip remote_ip local_port remote_port name protocol profiles enabled grouping edge_traversal]

        RULE_GROUP = 'RCS Firewall Rules'

        attr_reader :attributes

        def initialize(attributes = {})
          # Default attribute values
          @attributes = {
            grouping: RULE_GROUP
          }

          # Merge default attributes with the given ones
          # and remove invalid attributes
          attributes.symbolize_keys! if attributes.respond_to?(:symbolize_keys!)
          attributes.reject! { |key| !ATTRIBUTES.include?(key) }
          @attributes.merge!(attributes)

          # Define getters and setters
          ATTRIBUTES.each do |name|
            define_singleton_method(name) { @attributes[name] }
            define_singleton_method("#{name}=") { |value| @attributes[name] = value }
          end
        end

        def resolve_addresses!
          resolve_addresses(true)
        end

        def resolve_addresses(_raise = false)
          return if @addresses_resolved

          %i[remote_ip local_ip].each do |name|
            next unless @attributes[name]

            addresses = [@attributes[name]].flatten

            addresses.each_with_index do |address, index|
              next if %w[any localsubnet dns dhcp wins defaultgateway].include?(address.to_s.downcase)
              next if address.to_s =~ Resolv::IPv4::Regex
              next if address.to_s =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)\/(\d+)/

              is_localhost =  Socket.gethostname.casecmp(address).zero?

              addresses[index] = if is_localhost
                '127.0.0.1'
              elsif _raise
                resolve_dns(address)
              else
                resolve_dns(address) rescue address
              end
            end

            @attributes[name] = addresses.size == 1 ? addresses[0] : addresses
          end

          @addresses_resolved = true
        end

        def save
          resolve_addresses!

          if Advfirewall.call("firewall add rule #{stringify_attributes}").ok?
            true
          else
            raise "Unable to save firewall rule #{@attributes[:name]}"
          end
        end

        def del
          resolve_addresses

          only = %i[dir profile program service localip remoteip localport remoteport protocol name]

          Advfirewall.call("firewall delete rule #{stringify_attributes(only)}")
        end

        private

        def stringify_attributes(only = [])
          attrs = {
            name:       name,
            dir:        direction,
            action:     action,
            enable:     enabled,
            protocol:   protocol,
            profile:    profiles,
            remoteip:   remote_ip,
            localip:    local_ip,
            localport:  local_port,
            remoteport: remote_port,
            #group:      grouping  / why isn't working?
          }

          string = ""

          attrs.each do |key, value|
            next if only.any? and !only.include?(key)
            next if value.to_s.strip.empty?
            next if value == :any
            value = value.respond_to?(:join) ? value.map(&:to_s).join(',') : "\"#{value}\""
            string << "#{key}=#{value} "
          end

          string
        end
      end


      # Parse the response of the netsh advfirewall command
      class AdvfirewallResponse < String
        SEPARATOR = '-'*70

        attr_accessor :ok

        def ok?
          return self.ok unless self.ok.nil?
          self.strip =~ /OK\.\z/i
        end

        def has_separator?
          self.include?(SEPARATOR)
        end

        def first_line
          index = nil
          self.lines.each_with_index{ |line, i| index = i if line.include?(SEPARATOR)  }
          self.lines[index+1].strip if index
        end
      end


      class Advfirewall
        extend RCS::Tracer

        # Return true if the current os is Windows
        def self.exists?
          @firewall_exists ||= (RbConfig::CONFIG['host_os'] =~ /mingw/i)
        end

        def self.call(command, read: false)
          command = "netsh advfirewall #{command.strip}"

          unless exists?
            raise "The Windows Firewall is missing. You cannot call the command #{command.inspect} on this OS."
          end

          #trace(:debug, "[Advfirewall] #{command}")

          if read
            resp = AdvfirewallResponse.new(`#{command}`)
            trace(:debug, "[Advfirewall] #{resp}") unless resp.ok?
            resp
          else
            resp = AdvfirewallResponse.new
            resp.ok = system(command)
            resp
          end
        end
      end


      extend self


      # Return :on or :off depending of the firewall state
      #
      # Note that the files test/fixtures/advfirewall/show_currentprofile_state_on and
      # test/fixtures/advfirewall/show_currentprofile_state_off contains an example of the command output
      def status
        return status_from_registry if @use_registry_for_status

        first_line = Advfirewall.call("show currentprofile state", read: true).first_line

        if first_line =~ /ON\z/
          :on
        elsif first_line =~ /OFF\z/
          :off
        else
          @use_registry_for_status = true
          status_from_registry
        end
      end

      def status_from_registry
        command = 'reg query HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile /v EnableFirewall'
        trace(:debug, "[Advfirewall] #{command}")
        `#{command}`.include?('0x1') ? :on : :off
      end

      # Returns true if the default firewall policy is to block all inbound connections
      def block_inbound?
        line = Advfirewall.call("show currentprofile firewallpolicy", read: true).first_line
        line.to_s.downcase.include?('blockinbound')
      end

      # Delegate
      def exists?
        Advfirewall.exists?
      end

      def add_rule(attributes)
        Rule.new(attributes).save
      end

      def del_rule(name)
        Rule.new(name: name.to_s).del
      end

      def has_rule?(name)
        Advfirewall.call("firewall show rule name=\"#{name}\"").ok?
      end

      def raw_rules
        Advfirewall.call("firewall show rule name=all", read: true)
      end
    end
  end
end

WinFirewall = RCS::Common::WinFirewall
