# -*- coding: utf-8 -*-
module Dcmgr::Models

  class Alarm < AccountResource
    taggable 'alm'
    subset(:alives, {:deleted_at => nil})
    plugin :serialization
    serialize_attributes :yaml, :params
    serialize_attributes :yaml, :ok_actions
    serialize_attributes :yaml, :alarm_actions
    serialize_attributes :yaml, :insufficient_data_actions

    include Dcmgr::Constants::Alarm

    def validate
      super

      if (notification_periods.nil? || notification_periods < 1) && is_log_alarm?
        errors.add(:notiification_periods, "it must have digit more than 1")
      end

      if self.is_log_alarm?
        notification_actions = LOG_NOTIFICATION_ACTIONS

        if params["match_pattern"].blank?
          errors.add(:match_pattern, "Unknown value")
        end

        unless /^[0-9a-z._]+$/ =~ params['tag']
          errors.add(:tag, "Invalid format")
        end
      else
        errors.add(:metric_name, 'Unknown metric name')
      end

      notification_actions.each {|name|
        action_name = name + "_actions"
        values = self.__send__(action_name)
        unless values.blank?
          if SUPPORT_NOTIFICATION_TYPE.include?(values['notification_type'])
            unless values.has_key? 'notification_type'
              errors.add(:notification_type, 'Unknown value')
            end

            unless values.has_key? 'notification_id'
              errors.add(:notification_id, 'Unknown value')
            end

            unless values.has_key? 'notification_message_type'
              errors.add(:notification_message_type, 'Unknown value')
            end
          else
            errors.add(action_name.to_sym, "Invalid notification type")
          end
        end
      }
    end

    def self.entry_new(account, &blk)
      al = self.new
      al.account_id = (account.is_a?(Account) ? account.canonical_uuid : account.to_s)
      blk.call(al)
      al.save
    end

    def update_alarm(&blk)
      blk.call(self)
      self.save_changes
    end

    def is_log_alarm?
      LOG_METRICS.include?(metric_name)
    end

    def to_hash
      h = super
      h
    end

    private
    def _destroy_delete
      self.deleted_at ||= Time.now
      self.save_changes
    end

    def before_save
      super
    end
  end
end
