#!/usr/bin/env ruby

require 'flapjack/data/entity_check'
require 'flapjack/data/event'

def drain_events
  loop do
    event = Flapjack::Data::Event.next(:block => false, :persistence => @redis)
    break unless event
    @app.process_event(event)
  end
end

def submit_event(event)
  @redis.rpush 'events', event.to_json
end

def set_scheduled_maintenance(entity, check, duration = 60*60*2)
  entity_check = Flapjack::Data::EntityCheck.for_entity_name(entity, => check, :redis => @redis)
  t = Time.now.to_i
  entity_check.create_scheduled_maintenance(:start_time => t, :duration => duration, :summary => "upgrading everything")
  @redis.setex("#{entity}:#{check}:scheduled_maintenance", duration, t)
end

def remove_scheduled_maintenance(entity, check)
  entity_check = Flapjack::Data::EntityCheck.for_entity_name(entity, check, :redis => @redis)
  sm = entity_check.scheduled_maintenances
  sm.each do |m|
    entity_check.delete_scheduled_maintenance(:start_time => m[:start_time])
  end
end

def remove_unscheduled_maintenance(entity, check)
  # end any unscheduled downtime
  event_id = entity + ":" + check
  if (um_start = @redis.get("#{event_id}:unscheduled_maintenance"))
    @redis.del("#{event_id}:unscheduled_maintenance")
    duration = Time.now.to_i - um_start.to_i
    @redis.zadd("#{event_id}:unscheduled_maintenances", duration, um_start)
  end
end

def remove_notifications(entity, check)
  event_id = entity + ":" + check
  @redis.del("#{event_id}:last_problem_notification")
  @redis.del("#{event_id}:last_recovery_notification")
  @redis.del("#{event_id}:last_acknowledgement_notification")
end

def set_ok_state(entity, check)
  event_id = entity + ":" + check
  @redis.hset("check:" + event_id, 'state', 'ok')
  @redis.hset("check:" + event_id, 'last_change', (Time.now.to_i - (60*60*24)))
  @redis.zrem('failed_checks', event_id)
  @redis.zrem('failed_checks:client:clientx', event_id)
end

def set_failure_state(entity, check)
  event_id = entity + ":" + check
  @redis.hset("check:" + event_id, 'state', 'critical')
  @redis.hset("check:" + event_id, 'last_change', (Time.now.to_i - (60*60*24)))
  @redis.zadd('failed_checks', (Time.now.to_i - (60*60*24)), event_id)
  @redis.zadd('failed_checks:client:clientx', (Time.now.to_i - (60*60*24)), event_id)
end

def submit_ok(entity, check)
  event = {
    'type'    => 'service',
    'state'   => 'ok',
    'summary' => '0% packet loss',
    'entity'  => entity,
    'check'   => check,
    'client'  => 'clientx'
  }
  submit_event(event)
end

def submit_critical(entity, check)
  event = {
    'type'    => 'service',
    'state'   => 'critical',
    'summary' => '100% packet loss',
    'entity'  => entity,
    'check'   => check,
    'client'  => 'clientx'
  }
  submit_event(event)
end

def submit_acknowledgement(entity, check)
  event = {
    'type'    => 'action',
    'state'   => 'acknowledgement',
    'summary' => "I'll have this fixed in a jiffy, saw the same thing yesterday",
    'entity'  => entity,
    'check'   => check,
    'client'  => 'clientx'
  }
  submit_event(event)
end

Given /^an entity '([\w\.\-]+)' exists$/ do |entity|
  Flapjack::Data::Entity.add({'id'       => '5000',
                              'name'     => entity},
                             :redis => @redis )
end

Given /^^check '([\w\.\-]+)' for entity '([\w\.\-]+)' is in an ok state$/ do |check, entity|
  remove_unscheduled_maintenance(entity, check)
  remove_scheduled_maintenance(entity, check)
  remove_notifications(entity, check)
  set_ok_state(entity, check)
end

Given /^check '([\w\.\-]+)' for entity '([\w\.\-]+)' is in a failure state$/ do |check, entity|
  remove_unscheduled_maintenance(entity, check)
  remove_scheduled_maintenance(entity, check)
  remove_notifications(entity, check)
  set_failure_state(entity, check)
end

Given /^check '([\w\.\-]+)' for entity '([\w\.\-]+)' is in scheduled maintenance$/ do |check, entity|
  remove_unscheduled_maintenance(entity, check)
  set_scheduled_maintenance(entity, check)
end

# TODO set the state directly rather than submit & drain
Given /^check '([\w\.\-]+)' for entity '([\w\.\-]+)' is in unscheduled maintenance$/ do |check, entity|
  remove_scheduled_maintenance(entity, check)
  set_failure_state(entity, check)
  submit_acknowledgement(entity, check)
  drain_events  # TODO these should only be in When clauses
end

When /^an ok event is received for check '([\w\.\-]+)' on entity '([\w\.\-]+)'$/ do |check, entity|
  submit_ok(entity, check)
  drain_events
end

When /^a failure event is received for check '([\w\.\-]+)' on entity '([\w\.\-]+)'$/ do |check, entity|
  submit_critical(entity, check)
  drain_events
end

When /^an acknowledgement is received for check '([\w\.\-]+)' on entity '([\w\.\-]+)'$/ do |check, entity|
  submit_acknowledgement(entity, check)
  drain_events
end

When /^an acknowledgement event is received for check '([\w\.\-]+)' on entity '([\w\.\-]+)'$/ do |check, entity|
  submit_acknowledgement(entity, check)
  drain_events
end


# TODO logging is a side-effect, should test for notification generation itself
Then /^a notification should not be generated for check '([\w\.\-]+)' on entity '([\w\.\-]+)'$/ do |check, entity|
  message = @app.logger.messages.find {|m| m =~ /Not sending notifications for event/ }
  message.should_not be_nil
end

Then /^a notification should be generated for check '([\w\.\-]+)' on entity '([\w\.\-]+)'$/ do |check, entity|
  drain_events # TODO these should only be in When clauses
  message = @app.logger.messages.find {|m| m =~ /Sending notifications for event/ }
  message.should_not be_nil
end

Then /^show me the notifications?$/ do
  puts @app.logger.messages.join("\n")
end

