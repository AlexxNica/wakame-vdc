# -*- coding: utf-8 -*-
require 'strscan'
require 'ipaddress'

module Dcmgr::Models
  class SecurityGroup < AccountResource
    taggable 'sg'
    accept_service_type

    many_to_many :network_vif, :join_table=>:network_vif_security_groups
    many_to_many :referencees, :class => self, :join_table => :security_group_references,:left_key => :referencer_id, :right_key => :referencee_id
    many_to_many :referencers, :class => self, :join_table => :security_group_references,:right_key => :referencer_id, :left_key => :referencee_id

    def to_hash
      rules = []
      rule.to_s.each_line { |line|
        next if line =~ /\A#/
        next if line.length == 0
        
        rules << self.class.parse_rule(line.chomp)
      }

      super.merge({
                    :id => self.canonical_uuid,
                    :rule => rule.to_s,
                    :rules => rules.compact,
                  })
    end

    def to_api_document
      self.to_hash
    end
    
    def after_save
      super
    end

    def before_save
      current_ref_group_ids = []

      # Establish relations with referenced groups
      rule.to_s.each_line { |line|
        next if line =~ /\A#/
        next if line.length == 0

        parsed_rule = self.class.parse_rule(line)
        next if parsed_rule.nil?

        ref_group_id = parsed_rule[:ip_source].scan(/sg-\w+/).first
        next if ref_group_id.nil?

        current_ref_group_ids << ref_group_id
        if self.referencees.find {|ref| ref.canonical_uuid == ref_group_id}.nil? && (not SecurityGroup[ref_group_id].nil?)
          self.add_referencee(SecurityGroup[ref_group_id])
        end
      } #TODO: Fix crash when adding reference rules on create

      # Destroy relations with groups that are no longer referenced
      self.referencees_dataset.each { |referencee|
        unless current_ref_group_ids.member?(referencee.canonical_uuid)
          self.remove_referencee(referencee)
        end
      } unless self.referencees.empty?
      
      super
    end

    def before_destroy
      return false if self.network_vif.size > 0
      return false if self.referencers.size > 0

      super
    end
    alias :destroy_group :destroy
    
    def self.parse_rule(rule)
      rule = rule.strip.gsub(/[\s\t]+/, '')
      from_group = false
      
      # ex.
      # "tcp:22,22,ip4:0.0.0.0"
      # "udp:53,53,ip4:0.0.0.0"
      # "icmp:-1,-1,ip4:0.0.0.0"
      
      # 1st phase
      # ip_tport    : tcp,udp? 1 - 16bit, icmp: -1
      # id_port has been separeted in first phase.
      from_pair, ip_tport, source_pair = rule.split(',')
      
      return nil if from_pair.nil? || ip_tport.nil? || source_pair.nil?
      
      # 2nd phase
      # ip_protocol : [ tcp | udp | icmp ]
      # ip_fport    : tcp,udp? 1 - 16bit, icmp: -1
      ip_protocol, ip_fport = from_pair.split(':')
      
      # protocol    : [ ip4 | ip6 | security_group_uuid ]
      # ip_source   : ip4? xxx.xxx.xxx.xxx./[0-32], ip6? (not yet supprted)
      protocol, ip_source = source_pair.split(':')
      
      s = StringScanner.new(protocol)
      until s.eos?
        case
        when s.scan(/ip6/)
          # TODO#FUTURE: support IPv6 address format
          return
        when s.scan(/ip4/)
          # IPAddress doesn't support prefix '0'.
          ip_addr, prefix = ip_source.split('/', 2)
          if prefix.to_i == 0
            ip_source = ip_addr
          end
        when s.scan(/sg-\w+/)
          from_group = true
        else
          raise InvalidSecurityGroupRuleSyntax, "Unexpected protocol '#{s.peep(20)}'"
        end
      end
      
      if from_group == false
        #p "from_group:(#{from_group}) ip_source -> #{ip_source}"
        ip = IPAddress(ip_source)
        ip_source = case ip.u32
                    when 0
                      "#{ip.address}/0"
                    else
                      "#{ip.address}/#{ip.prefix}"
                    end
      else
        ip_source = protocol
        protocol = nil
      end
      
      case ip_protocol
      when 'tcp', 'udp'
        ip_fport = ip_fport.to_i
        ip_tport = ip_tport.to_i
        
        # validate port range
        [ ip_fport, ip_tport ].each do |port|
          raise InvalidSecurityGroupRuleSyntax, "Out of range port number: #{port}" unless port >= 1 && port <= 65535
        end
        
        if !(ip_fport <= ip_tport)
          raise InvalidSecurityGroupRuleSyntax, "Invalid IP port range: #{ip_fport} <= #{ip_tport}"
        end
        
        {
          :ip_protocol => ip_protocol,
          :ip_fport    => ip_fport,
          :ip_tport    => ip_tport,
          :protocol    => protocol,
          :ip_source   => ip_source,
        }
      when 'icmp'
        # via http://docs.amazonwebservices.com/AWSEC2/latest/CommandLineReference/
        #
        # For the ICMP protocol, the ICMP type and code must be specified.
        # This must be specified in the format type:code where both are integers.
        # Type, code, or both can be specified as -1, which is a wildcard.
        
        icmp_type = ip_fport.to_i
        icmp_code = ip_tport.to_i
        
        # icmp_type
        case icmp_type
        when -1
        when 0, 3, 5, 8, 11, 12, 13, 14, 15, 16, 17, 18
        else
          raise InvalidSecurityGroupRuleSyntax, "Unsupported ICMP type number: #{icmp_type}"
        end
        
        # icmp_code
        case icmp_code
        when -1
        when 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
          # when icmp_type equals -1 icmp_code must equal -1.
          return if icmp_type == -1
        else
          raise InvalidSecurityGroupRuleSyntax, "Unsupported ICMP code number: #{icmp_code}"
        end
        
        {
          :ip_protocol => ip_protocol,
          :icmp_type   => ip_tport.to_i, # ip_tport.to_i, # -1 or 0,       3,    5,       8,        11, 12, 13, 14, 15, 16, 17, 18
          :icmp_code   => ip_fport.to_i, # ip_fport.to_i, # -1 or 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
          :protocol    => protocol,
          :ip_source   => ip_source,
        }
      else
        raise InvalidSecurityGroupRuleSyntax, "Unsupported protocol: #{ip_protocol}"
      end
    end

  end
end
