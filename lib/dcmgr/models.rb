#!/usr/bin/ruby

require 'rubygems'
require 'sequel'

module Dcmgr::Model
  class InvalidUUIDError < StandardError; end
  class DuplicateUUIDError < StandardError; end

  module UUIDMethods
    module ClassMethods
      # override [] method. add search by uuid String
      def [](*args)
        if args.size == 1 and args[0].is_a? String
          super(:uuid=>trim_uuid(args[0]))
        else
          super(*args)
        end
      end
          
      def trim_uuid(p_uuid)
        if p_uuid and p_uuid.length == self.prefix_uuid.length + 9
          return p_uuid[(self.prefix_uuid.length+1), p_uuid.length]
        end
        raise InvalidUUIDError, "invalid uuid: #{p_uuid}"
      end

      def tags
        [Tag.new(:name=>"%s-_ROLETAG" % [self.prefix_uuid])]
      end
    end
    
    def self.included(mod)
      mod.extend ClassMethods
    end
      
    def generate_uuid
      "%08x" % rand(16 ** 8)
    end

    def setup_uuid
      self.uuid = generate_uuid unless self.values[:uuid]
    end

    def before_create
      setup_uuid
    end

    def save(*columns)
      super
    rescue Sequel::DatabaseError
      raise DuplicateUUIDError
    end

    def uuid
      "%s-%s" % [self.class.prefix_uuid, self.values[:uuid]]
    end

    def to_s
      uuid
    end
  end
end

class TagMapping < Sequel::Model
  TYPE_ACCOUNT = 0
  TYPE_TAG = 1
  TYPE_USER = 2
  TYPE_INSTANCE = 3
  TYPE_INSTANCE_IMAGE = 4
  TYPE_HV_CONTROLLER = 5
  TYPE_HV_AGENT = 6
  TYPE_PHYSICAL_HOST = 7
  TYPE_PHYSICAL_HOST_LOCATION = 8
  TYPE_IMAGE_STORAGE_HOST = 9
  TYPE_IMAGE_STORAGE = 10

  many_to_one :tag
end

class Account < Sequel::Model
  include Dcmgr::Model::UUIDMethods
  def self.prefix_uuid; 'A'; end
  
  many_to_many :users
  many_to_many :tags, :join_table=>:tag_mappings, :left_key=>:target_id, :conditions=>{:target_type=>TagMapping::TYPE_ACCOUNT}
  
  def before_create
    super
    self.created_at = Time.now unless self.created_at
  end
end

class User < Sequel::Model
  include Dcmgr::Model::UUIDMethods
  def self.prefix_uuid; 'U'; end

  many_to_many :accounts
  many_to_many :tags, :join_table=>:tag_mappings, :left_key=>:target_id, :conditions=>{:target_type=>TagMapping::TYPE_USER}

  def validate
    errors.add(:name, "can't empty") unless self.name and self.name.length > 0
    errors.add(:password, "can't empty") unless self.password and self.password.length > 0
  end
  
  def before_create
    super
    self.default_password = self.password
  end

  def self.enable_users
    filter(:enable=>true)
  end
end


class AccountsUser < Sequel::Model
  many_to_one :account
  many_to_one :user, :left_primary_key=>:user_id
end

class Instance < Sequel::Model
  include Dcmgr::Model::UUIDMethods
  def self.prefix_uuid; 'I'; end
  
  STATUS_TYPE_OFFLINE = 0
  STATUS_TYPE_RUNNING = 1
  STATUS_TYPE_ONLINE = 2
  STATUS_TYPE_TERMINATING = 3

  STATUS_TYPES = {
    STATUS_TYPE_OFFLINE => :offline,
    STATUS_TYPE_RUNNING => :running,
    STATUS_TYPE_ONLINE => :online,
    STATUS_TYPE_TERMINATING => :terminating,
  }
  
  many_to_one :account
  many_to_one :user

  many_to_one :image_storage
  many_to_one :hv_agent

  many_to_many :tags, :join_table=>:tag_mappings, :left_key=>:target_id, :conditions=>{:target_type=>TagMapping::TYPE_INSTANCE}

  set_dataset filter({~:status => Instance::STATUS_TYPE_OFFLINE} | ({:status => Instance::STATUS_TYPE_OFFLINE} & (:status_updated_at > Time.now - 3600)))
  
  def physical_host
    if self.hv_agent
      self.hv_agent.physical_host
    else
      nil
    end
  end

  def mac_address
    Dcmgr::IP_MANAGER.macaddress_by_ip(self.ip)
  end

  def status_sym
    STATUS_TYPES[self.status]
  end

  def status_sym=(sym)
    match = STATUS_TYPES.find{|k,v| v == sym}
    return nil unless match
    self.status = match[0]
  end

  def before_create
    super
    self.status = STATUS_TYPE_OFFLINE unless self.status
    self.status_updated_at = Time.now
    Dcmgr::logger.debug "becore create: status = %s" % self.status
    unless self.hv_agent
      physical_host = PhysicalHost.assign(self)
      self.hv_agent = physical_host.hv_agents[0]
    end
    
    mac, self.ip = Dcmgr::IP_MANAGER.assign_ip
    Dcmgr::logger.debug "assigned ip: mac: #{mac}, ip: #{self.ip}"
  end

  def validate
    errors.add(:account, "can't empty") unless self.account
    errors.add(:user, "can't empty") unless self.user
    
    # errors.add(:hv_agent, "can't empty") unless self.hv_agent
    errors.add(:image_storage, "can't empty") unless self.image_storage

    errors.add(:need_cpus, "can't empty") unless self.need_cpus
    errors.add(:need_cpu_mhz, "can't empty") unless self.need_cpu_mhz
    errors.add(:need_memory, "can't empty") unless self.need_memory
  end

  def run
    Dcmgr::http(self.host, 80).open {|http|
      res = http.get('/run')
      return res.success?
    }
  end

  def shutdown
    Dcmgr::http(self.host, 80).open {|http|
      res = http.get('/shutdown')
      return res.success?
    }
  end
end

class ImageStorage < Sequel::Model
  include Dcmgr::Model::UUIDMethods
  def self.prefix_uuid; 'IS'; end

  many_to_one :image_storage_host

  many_to_one :account
  many_to_one :user
  
  many_to_many :tags, :join_table=>:tag_mappings, :left_key=>:target_id, :conditions=>{:target_type=>TagMapping::TYPE_IMAGE_STORAGE}
end

class ImageStorageHost < Sequel::Model
  include Dcmgr::Model::UUIDMethods
  def self.prefix_uuid; 'ISH'; end
  
  many_to_many :tags, :join_table=>:tag_mappings, :left_key=>:target_id, :conditions=>{:target_type=>TagMapping::TYPE_IMAGE_STORAGE_HOST}
end

class PhysicalHost < Sequel::Model
  include Dcmgr::Model::UUIDMethods

  def self.prefix_uuid; 'PH'; end

  one_to_many :hv_agents
  
  many_to_many :tags, :join_table=>:tag_mappings, :left_key=>:target_id, :conditions=>{:target_type=>TagMapping::TYPE_PHYSICAL_HOST}
  many_to_many :location_tags, :class=>:Tag, :right_key=>:tag_id, :join_table=>:tag_mappings, :left_key=>:target_id, :conditions=>{:target_type=>TagMapping::TYPE_PHYSICAL_HOST_LOCATION}

  many_to_one :relate_user, :class=>:User

  def self.enable_hosts
    filter(~:id => TagMapping.filter(:target_type=>TagMapping::TYPE_PHYSICAL_HOST).select(:target_id)).order_by(:id).all
  end

  def self.assign(instance)
    Dcmgr::scheduler.assign_to_instance(enable_hosts, instance)
  end
  
  def before_create
    super
  end

  def after_create
    super
    TagMapping.create(:tag_id=>Tag.system_tag(:STANDBY_INSTANCE).id,
                      :target_type=>TagMapping::TYPE_PHYSICAL_HOST,
                      :target_id=>self.id)
  end

  def instances
    self.hv_agents.map{|hva| hva.instances}.flatten
  end

  def create_location_tag(name, account)
    TagMapping.create(:tag_id=>Tag.create(:name=>name, :account=>account).id,
                      :target_type=>TagMapping::TYPE_PHYSICAL_HOST_LOCATION,
                      :target_id=>self.id)
  end

  def space_cpu_mhz
    setup_space unless @space_cpu_mhz
    @space_cpu_mhz
  end

  def setup_space
    
    need_cpu_mhz = instances.inject(0) {|v, ins| v + ins.need_cpu_mhz}
    space_cpu_mhz = cpu_mhz - need_cpu_mhz
    # 10 % down
    @space_cpu_mhz = space_cpu_mhz * 0.9
    
    need_memory = instances.inject(0) {|v, ins| v + ins.need_memory}
    space_memory = memory - need_memory
    # 10 % down
    @space_memory = space_memory * 0.9
  end
  
  def space_memory
    setup_space unless @space_memory
    @space_memory
  end
end

class HvController < Sequel::Model
  include Dcmgr::Model::UUIDMethods
  def self.prefix_uuid; 'HVC'; end
  many_to_one :physical_host
  one_to_many :hv_agents
  many_to_many :tags, :join_table=>:tag_mappings, :left_key=>:target_id, :conditions=>{:target_type=>TagMapping::TYPE_HV_CONTROLLER}
end

class HvAgent < Sequel::Model
  include Dcmgr::Model::UUIDMethods
  def self.prefix_uuid; 'HVA'; end
  many_to_one :hv_controller
  many_to_one :physical_host
  one_to_many :instances
  many_to_many :tags, :join_table=>:tag_mappings, :left_key=>:target_id, :conditions=>{:target_type=>TagMapping::TYPE_HV_AGENT}
end

class Tag < Sequel::Model
  include Dcmgr::Model::UUIDMethods
  def self.prefix_uuid; 'TAG'; end

  TYPE_NORMAL = 0
  TYPE_AUTH = 1

  many_to_one :account
  one_to_many :tag_mappings
  many_to_many :tags, :join_table=>:tag_mappings, :left_key=>:target_id, :conditions=>{:target_type=>TagMapping::TYPE_TAG}

  many_to_one :owner, :class=>:User

  one_to_many :tag_attributes, :one_to_one=>true

  def self.create_system_tag(name)
    create(:account_id=>0, :owner_id=>0,
           :role=>0, :name=>name)
  end

  def initialize(*args)
    @attribute = nil
    super
  end
  
  def self.create_system_tags
    SYSTEM_TAG_NAMES.each{|tag_name|
      create_system_tag(tag_name)
    }
  end

  def self.system_tag(name)
    tag_name = name.to_s.tr('_', ' ').downcase
    key = SYSTEM_TAG_NAMES.index(tag_name)
    unless key
      raise "unkown system tag: %s" % tag_name
    end
    Tag[key + 1]
  end

  def hash
    self.id
  end

  def eql?(obj)
    return false if obj == nil
    return false unless obj.is_a? Tag
    self.id.eql? obj.id
  end

  def ==(obj)
    return false if obj == nil
    return false unless obj.is_a? Tag
    self.id == obj.id
  end

  def role=(val)
    attribute = find_attribute
    attribute.role = val
  end

  def role
    attribute = find_attribute
    attribute.role
  end

  def save
    super
    if @attribute
      @attribute.tag_id = self.id unless @attribute.tag_id
      @attribute.save
    end
    self
  end

  def find_attribute
    return @attribute if @attribute
      
    if self.id
      unless @attribute = TagAttribute[:tag_id=>self.id]
        @attribute = TagAttribute.create(:tag_id=>self.id)
      end
    else
      @attribute = TagAttribute.new
    end

    @attribute
  end
  
  def validate
    errors.add(:name, "can't empty") if self.name == nil or self.name.length == 0
  end
  
  SYSTEM_TAG_NAMES = ['standby instance',
                      'wakame image',
                     ]
end

class TagAttribute < Sequel::Model
  many_to_one :tag, :one_to_one=>true
end

class Log < Sequel::Model
  many_to_one :account
  many_to_one :user, :left_primary_key=>:user_id

  def before_create
    super
    self.created_at = Time.now unless self.created_at
  end

  def validate
    errors.add(:account, "can't empty") unless (self.account or self.account_id)
    errors.add(:tareget_uuid, "can't empty") unless self.target_uuid
    errors.add(:action, "can't empty") unless self.action
    errors.add(:user, "can't empty") unless (self.user or self.user_id)
  end
end

class LocationGroup < Sequel::Model
  def initialize(name)
    @name = name
  end

  attr_reader :name

  def keys
    [:name]
  end
  
  def self.all
    Dcmgr::location_groups.map{|name|
      LocationGroup.new(name)
    }
  end
end
