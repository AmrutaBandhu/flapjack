Pact.provider_states_for "flapjack-diner" do

  provider_state "no check exists" do
    tear_down { default_tear_down }
  end

  provider_state "no contact exists" do
    tear_down { default_tear_down }
  end

  provider_state "no medium exists" do
    tear_down { default_tear_down }
  end

  provider_state "no pagerduty credentials exist" do
    tear_down { default_tear_down }
  end

  provider_state "no rule exists" do
    tear_down { default_tear_down }
  end

  provider_state "no scheduled maintenance period exists" do
    tear_down { default_tear_down }
  end

  provider_state "no tag exists" do
    tear_down { default_tear_down }
  end

  provider_state "no unscheduled maintenance period exists" do
    tear_down { default_tear_down }
  end


  provider_state "a check exists" do
    set_up do
      check = Flapjack::Data::Check.new(check_data)
      check.save
    end

    tear_down { default_tear_down }
  end

  provider_state "two checks exist" do
    set_up do
      check = Flapjack::Data::Check.new(check_data)
      check.save

      check_2 = Flapjack::Data::Check.new(check_2_data)
      check_2.save
    end

    tear_down { default_tear_down }
  end

  provider_state "a contact exists" do
    set_up do
      contact = Flapjack::Data::Contact.new(contact_data)
      contact.save
    end

    tear_down { default_tear_down }
  end

  provider_state "a contact with one medium exists" do
    set_up do
      contact = Flapjack::Data::Contact.new(contact_data)
      contact.save

      email = Flapjack::Data::Medium.new(email_data)
      email.save

      contact.media << email
    end

    tear_down { default_tear_down }
  end

  provider_state "two contacts exist" do
    set_up do
      contact = Flapjack::Data::Contact.new(contact_data)
      contact.save

      contact_2 = Flapjack::Data::Contact.new(contact_2_data)
      contact_2.save
    end

    tear_down { default_tear_down }
  end

  provider_state "a medium exists" do
    set_up do
      sms = Flapjack::Data::Medium.new(sms_data)
      sms.save
    end

    tear_down { default_tear_down }
  end

  provider_state "two media exist" do
    set_up do
      sms = Flapjack::Data::Medium.new(sms_data)
      sms.save

      email = Flapjack::Data::Medium.new(email_data)
      email.save
    end

    tear_down { default_tear_down }
  end

  provider_state "a rule exists" do
    set_up do
      rule = Flapjack::Data::Rule.new(rule_data)
      rule.save
      rule.recalculate_routes
    end

    tear_down { default_tear_down }
  end

  provider_state "two rules exist" do
    set_up do
      rule = Flapjack::Data::Rule.new(rule_data)
      rule.save
      rule.recalculate_routes

      rule_2 = Flapjack::Data::Rule.new(rule_2_data)
      rule_2.save
      rule_2.recalculate_routes
    end

    tear_down { default_tear_down }
  end

  provider_state "a tag exists" do
    set_up do
      tag = Flapjack::Data::Tag.new(tag_data)
      tag.save
    end

    tear_down { default_tear_down }
  end

  provider_state "two tags exist" do
    set_up do
      tag = Flapjack::Data::Tag.new(tag_data)
      tag.save

      tag_2 = Flapjack::Data::Tag.new(tag_2_data)
      tag_2.save
    end

    tear_down { default_tear_down }
  end

  provider_state "a scheduled maintenance period exists" do
    set_up do
      smd = scheduled_maintenance_data.dup
      [:start_time, :end_time].each {|t| smd[t] = Time.parse(smd[t]) }
      scheduled_maintenance = Flapjack::Data::ScheduledMaintenance.new(smd)
      scheduled_maintenance.save
    end

    tear_down { default_tear_down }
  end

  provider_state "two scheduled maintenance periods exist" do
    set_up do
      smd = scheduled_maintenance_data.dup
      [:start_time, :end_time].each {|t| smd[t] = Time.parse(smd[t]) }
      scheduled_maintenance = Flapjack::Data::ScheduledMaintenance.new(smd)
      scheduled_maintenance.save

      smd_2 = scheduled_maintenance_2_data.dup
      [:start_time, :end_time].each {|t| smd_2[t] = Time.parse(smd_2[t]) }
      scheduled_maintenance_2 = Flapjack::Data::ScheduledMaintenance.new(smd_2)
      scheduled_maintenance_2.save
    end

    tear_down { default_tear_down }
  end

  provider_state "an unscheduled maintenance period exists" do
    set_up do
      usmd = unscheduled_maintenance_data.dup
      usmd[:end_time] = Time.parse(usmd[:end_time])
      unscheduled_maintenance = Flapjack::Data::UnscheduledMaintenance.new(usmd)
      unscheduled_maintenance.save
    end

    tear_down { default_tear_down }
  end

  provider_state "two unscheduled maintenance periods exist" do
    set_up do
      usmd = unscheduled_maintenance_data.dup
      usmd[:end_time] = Time.parse(usmd[:end_time])
      unscheduled_maintenance = Flapjack::Data::UnscheduledMaintenance.new(usmd)
      unscheduled_maintenance.save

      usmd_2 = unscheduled_maintenance_2_data.dup
      usmd_2[:end_time] = Time.parse(usmd_2[:end_time])
      unscheduled_maintenance_2 = Flapjack::Data::UnscheduledMaintenance.new(usmd_2)
      unscheduled_maintenance_2.save
    end

    tear_down { default_tear_down }
  end

  provider_state "a check and a tag exist" do
    set_up do
      check = Flapjack::Data::Check.new(check_data)
      check.save

      tag = Flapjack::Data::Tag.new(tag_data)
      tag.save
    end

    tear_down { default_tear_down }
  end

  provider_state "a contact and a medium exist" do
    set_up do
      contact = Flapjack::Data::Contact.new(contact_data)
      contact.save

      email = Flapjack::Data::Medium.new(email_data)
      email.save
    end

    tear_down { default_tear_down }
  end

  provider_state "a contact with a medium exists" do
    set_up do
      contact = Flapjack::Data::Contact.new(contact_data)
      contact.save

      email = Flapjack::Data::Medium.new(email_data)
      email.save

      contact.media << email
    end

    tear_down { default_tear_down }
  end

  provider_state "a contact with a rule exists" do
    set_up do
      contact = Flapjack::Data::Contact.new(contact_data)
      contact.save

      rule = Flapjack::Data::Rule.new(rule_data)
      rule.save
      rule.recalculate_routes

      contact.rules << rule
    end

    tear_down { default_tear_down }
  end

  provider_state "a check with a tag exists" do
    set_up do
      check = Flapjack::Data::Check.new(check_data)
      check.save

      tag = Flapjack::Data::Tag.new(tag_data)
      tag.save

      Flapjack::Data::Check.lock(Flapjack::Data::Tag,
        Flapjack::Data::Rule, Flapjack::Data::Route) do

        check.tags << tag
      end
    end

    tear_down { default_tear_down }
  end

  provider_state "a check and two tags exist" do
    set_up do
      check = Flapjack::Data::Check.new(check_data)
      check.save

      tag = Flapjack::Data::Tag.new(tag_data)
      tag.save

      tag_2 = Flapjack::Data::Tag.new(tag_2_data)
      tag_2.save
    end

    tear_down { default_tear_down }
  end

  provider_state "a check with two tags exists" do
    set_up do
      check = Flapjack::Data::Check.new(check_data)
      check.save

      tag = Flapjack::Data::Tag.new(tag_data)
      tag.save

      tag_2 = Flapjack::Data::Tag.new(tag_2_data)
      tag_2.save

      Flapjack::Data::Check.lock(Flapjack::Data::Tag,
        Flapjack::Data::Rule, Flapjack::Data::Route) do

        check.tags.add(tag, tag_2)
      end
    end

    tear_down { default_tear_down }
  end

  provider_state "a tag with two checks exists" do
    set_up do
      tag = Flapjack::Data::Tag.new(tag_data)
      tag.save

      check = Flapjack::Data::Check.new(check_data)
      check.save

      check_2 = Flapjack::Data::Check.new(check_2_data)
      check_2.save

      Flapjack::Data::Check.lock(Flapjack::Data::Tag,
        Flapjack::Data::Rule, Flapjack::Data::Route) do

        tag.checks.add(check, check_2)

      end
    end

    tear_down { default_tear_down }
  end

end