require 'spec_helper'
require 'flapjack/gateways/jabber'

describe Flapjack::Gateways::Jabber, :logger => true do

  let(:config) { {'queue'    => 'jabber_notifications',
                  'server'   => 'example.com',
                  'port'     => '5222',
                  'jabberid' => 'flapjack@example.com',
                  'password' => 'password',
                  'alias'    => 'flapjack',
                  'identifiers' => ['@flapjack'],
                  'rooms'    => ['flapjacktest@conference.example.com']
                 }
  }

  let(:check) { double(Flapjack::Data::Check) }

  let(:redis) { double(::Redis) }
  let(:stanza) { double('stanza') }

  let(:now) { Time.now}

  let(:lock) { double(Monitor) }
  let(:stop_cond) { double(MonitorMixin::ConditionVariable) }

  before(:each) do
    allow(Flapjack).to receive(:redis).and_return(redis)
  end

  context 'notifications' do

    let(:queue) { double(Flapjack::RecordQueue) }

    let(:alert) { double(Flapjack::Data::Alert) }

    it "starts and is stopped by an exception" do
      expect(Flapjack::RecordQueue).to receive(:new).with('jabber_notifications',
        Flapjack::Data::Alert).and_return(queue)

      expect(lock).to receive(:synchronize).and_yield
      expect(queue).to receive(:foreach).and_yield(alert)
      expect(queue).to receive(:wait).and_raise(Flapjack::PikeletStop)

      expect(redis).to receive(:quit)

      fjn = Flapjack::Gateways::Jabber::Notifier.new(:lock => lock,
        :config => config, :logger => @logger)
      expect(fjn).to receive(:handle_alert).with(alert)

      expect { fjn.start }.to raise_error(Flapjack::PikeletStop)
    end

    it "handles notifications received via Redis" do
      bot = double(Flapjack::Gateways::Jabber::Bot)
      expect(bot).to receive(:respond_to?).with(:announce).and_return(true)
      expect(bot).to receive(:announce).with('johns@example.com', /Problem: /)
      expect(bot).to receive(:alias).and_return('flapjack')

      expect(check).to receive(:name).twice.and_return('app-02:ping')

      expect(alert).to receive(:address).and_return('johns@example.com')
      expect(alert).to receive(:check).twice.and_return(check)
      expect(alert).to receive(:state).and_return('critical')
      expect(alert).to receive(:state_title_case).and_return('Critical')
      expect(alert).to receive(:summary).twice.and_return('')
      expect(alert).to receive(:event_count).and_return(33)
      expect(alert).to receive(:type).twice.and_return('problem')
      expect(alert).to receive(:type_sentence_case).and_return('Problem')
      expect(alert).to receive(:rollup).and_return(nil)
      expect(alert).to receive(:event_hash).and_return('abcd1234')

      fjn = Flapjack::Gateways::Jabber::Notifier.new(:config => config, :logger => @logger)
      fjn.instance_variable_set('@siblings', [bot])
      fjn.send(:handle_alert, alert)
    end

  end

  context 'commands' do

    let(:bot) { double(Flapjack::Gateways::Jabber::Bot) }

    let(:tag) { double(Flapjack::Data::Tag) }

    let(:all_checks) { double('all_checks', :all => [check]) }
    let(:all_tags)   { double('all_tags', :all => [tag]) }

    # TODO use separate threads in the test instead?
    it "starts and is stopped by a signal" do
      expect(lock).to receive(:synchronize).and_yield

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:lock => lock, :stop_condition => stop_cond,
        :config => config, :logger => @logger)
      msg = {:room => 'room1', :nick => 'jim', :time => now.to_i, :message => 'help'}
      fji.instance_variable_get('@messages').push(msg)
      expect(stop_cond).to receive(:wait_while) {
        fji.instance_variable_set('@should_quit', true)
      }

      expect(fji).to receive(:interpret).with('room1', 'jim', now.to_i, 'help')

      expect(redis).to receive(:quit)
      fji.start
    end

    it "receives a message and and signals a condition variable" do
      expect(lock).to receive(:synchronize).and_yield

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:lock => lock, :stop_condition => stop_cond,
        :config => config, :logger => @logger)
      expect(fji.instance_variable_get('@messages')).to be_empty
      expect(stop_cond).to receive(:signal)

      fji.receive_message('room1', 'jim', now.to_i, 'help')
      expect(fji.instance_variable_get('@messages').size).to eq(1)
    end

    it "interprets a received help command (from a room)" do
      expect(bot).to receive(:announce).with('room1', /^commands:/)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'help')
    end

    it "interprets a received help command (from a user)" do
      expect(bot).to receive(:say).with('jim', /^commands:/)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret(nil, 'jim', now.to_i, 'help')
    end

    it "interprets a received identify command " do
      expect(bot).to receive(:announce).with('room1', /System CPU Time/)
      expect(bot).to receive(:identifiers).and_return(['@flapjack'])

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config,
              :logger => @logger, :boot_time => now)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i + 60, 'identify')
    end

    it "interprets a received find command (with regex)" do
      expect(bot).to receive(:announce).with('room1', "Checks matching /example/:\nexample.com:ping")

      expect(check).to receive(:name).and_return('example.com:ping')
      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:name => ['example.com:ping']).and_return(all_checks)

      expect(Flapjack::Data::Check).to receive(:attributes_matching_name).
        with("example").and_return(['example.com:ping'])

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'find checks matching /example/')
    end

    it "interprets a received find command (with an invalid regex)" do
      expect(bot).to receive(:announce).with('room1', 'Error parsing /(example/')

      expect(Flapjack::Data::Check).to receive(:attributes_matching_name).
        with("(example").and_raise(RegexpError.new)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'find checks matching /(example/')
    end

    it "interprets a received find command (with tag)" do
      expect(bot).to receive(:announce).with('room1', "Checks with tag 'example.com':\nexample.com:ping")

      expect(check).to receive(:name).and_return('example.com:ping')

      expect(all_checks).to receive(:empty?).and_return(false)
      expect(tag).to receive(:checks).and_return(all_checks)

      expect(Flapjack::Data::Tag).to receive(:intersect).
        with(:name => 'example.com').and_return(all_tags)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'find checks with tag example.com')
    end

    it "interprets a received state command (with name)" do
      expect(bot).to receive(:announce).with('room1', /example.com:ping - ok/)

      expect(check).to receive(:name).and_return('example.com:ping')
      expect(check).to receive(:state).and_return('ok')

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:name => 'example.com:ping').and_return(all_checks)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'state of example.com:ping')
    end

    it "interprets a received state command (with tag)" do
      expect(bot).to receive(:announce).with('room1', /example.com:ping - ok/)

      expect(check).to receive(:name).and_return('example.com:ping')
      expect(check).to receive(:state).and_return('ok')

      expect(all_checks).to receive(:empty?).and_return(false)
      expect(tag).to receive(:checks).and_return(all_checks)

      expect(Flapjack::Data::Tag).to receive(:intersect).
        with(:name => 'example.com').and_return(all_tags)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'state of checks with tag example.com')
    end

    it "interprets a received state command (with regex)" do
      expect(bot).to receive(:announce).with('room1', /example.com:ping - ok/)

      expect(check).to receive(:name).and_return('example.com:ping')
      expect(check).to receive(:state).and_return('ok')

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:name => ['example.com:ping']).and_return(all_checks)

      expect(Flapjack::Data::Check).to receive(:attributes_matching_name).
        with("^example.com:p").and_return(['example.com:ping'])

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'state of checks matching /^example.com:p/')
    end

    it "interprets a received information command (with name)" do
      expect(bot).to receive(:announce).with('room1', /Not in scheduled or unscheduled maintenance./)

      expect(check).to receive(:scheduled_maintenance_at).and_return(nil)
      expect(check).to receive(:unscheduled_maintenance_at).and_return(nil)

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:name => 'example.com:ping').and_return(all_checks)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'tell me about example.com:ping')
    end

    it "handles a received information command (with name, with newline in the command)" do
      expect(bot).to receive(:announce).with('room1', /Not in scheduled or unscheduled maintenance./)

      expect(check).to receive(:scheduled_maintenance_at).and_return(nil)
      expect(check).to receive(:unscheduled_maintenance_at).and_return(nil)

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:name => 'example.com:ping').and_return(all_checks)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, "tell me \nabout example.com:ping")
    end

    it "interprets a received information command (with tag)" do
      expect(bot).to receive(:announce).with('room1', /Not in scheduled or unscheduled maintenance./)

      expect(check).to receive(:scheduled_maintenance_at).and_return(nil)
      expect(check).to receive(:unscheduled_maintenance_at).and_return(nil)

      expect(all_checks).to receive(:empty?).and_return(false)
      expect(tag).to receive(:checks).and_return(all_checks)

      expect(Flapjack::Data::Tag).to receive(:intersect).
        with(:name => 'example.com').and_return(all_tags)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'tell me about checks with tag example.com')
    end

    it "interprets a received information command (with regex)" do
      expect(bot).to receive(:announce).with('room1', /Not in scheduled or unscheduled maintenance./)

      expect(check).to receive(:scheduled_maintenance_at).and_return(nil)
      expect(check).to receive(:unscheduled_maintenance_at).and_return(nil)

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:name => ['example.com:ping']).and_return(all_checks)

      expect(Flapjack::Data::Check).to receive(:attributes_matching_name).
        with("^example.com:p").and_return(['example.com:ping'])

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'tell me about checks matching /^example.com:p/')
    end

    it "interprets a received ACKID command" do
      expect(bot).to receive(:announce).with('room1', "ACKing example.com:ping (abcd1234)")

      expect(check).to receive(:name).and_return('example.com:ping')
      expect(check).to receive(:in_unscheduled_maintenance?).and_return(false)

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:ack_hash => 'abcd1234').and_return(all_checks)

      expect(Flapjack::Data::Event).to receive(:create_acknowledgements).
        with('events', [check],
             :summary => 'JJ looking', :acknowledgement_id => 'abcd1234',
             :duration => (60 * 60))

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'ACKID abcd1234 JJ looking duration: 1 hour')
    end

    it "interprets a received acknowledgement command (with tag)" do
      expect(bot).to receive(:announce).with('room1', "Ack list:\nexample.com:ping")

      expect(check).to receive(:state).and_return('critical')
      expect(check).to receive(:name).and_return('example.com:ping')

      expect(all_checks).to receive(:empty?).and_return(false)
      expect(tag).to receive(:checks).and_return(all_checks)

      expect(Flapjack::Data::Tag).to receive(:intersect).
        with(:name => 'example.com').and_return(all_tags)

      expect(Flapjack::Data::Event).to receive(:create_acknowledgements).
        with('events', [check],
             :summary => 'jim: Set via chatbot', :duration => (60 * 60))

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'ack checks with tag example.com')
    end

    it "interprets a received acknowledgement command (with regex)" do
      expect(bot).to receive(:announce).with('room1', "Ack list:\nexample.com:ping")

      expect(check).to receive(:state).and_return('critical')
      expect(check).to receive(:name).and_return('example.com:ping')

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:name => ['example.com:ping']).and_return(all_checks)

      expect(Flapjack::Data::Check).to receive(:attributes_matching_name).
        with("^example.com:p").and_return(['example.com:ping'])

      expect(Flapjack::Data::Event).to receive(:create_acknowledgements).
        with('events', [check],
             :summary => 'jim: Set via chatbot', :duration => (60 * 60))

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'ack checks matching /^example.com:p/')
    end

    it "interprets a received test notifications command (with name)" do
      expect(bot).to receive(:announce).with('room1', /Testing notifications for check with name 'example.com:ping'/)

      expect(Flapjack::Data::Check).to receive(:intersect).
        with(:name => 'example.com:ping').and_return(all_checks)

      expect(Flapjack::Data::Event).to receive(:test_notifications).
        with('events', [check], an_instance_of(Hash))

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'test notifications for example.com:ping')
    end

    it "interprets a received test notifications command (with tag)" do
      expect(bot).to receive(:announce).with('room1', /Testing notifications for check with tag 'example.com'/)

      expect(all_checks).to receive(:empty?).and_return(false)
      expect(tag).to receive(:checks).and_return(all_checks)

      expect(Flapjack::Data::Tag).to receive(:intersect).
        with(:name => 'example.com').and_return(all_tags)

      expect(Flapjack::Data::Event).to receive(:test_notifications).
        with('events', [check], an_instance_of(Hash))

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'test notifications for checks with tag example.com')
    end

    it "interprets a received test notifications command (with regex)" do
      expect(bot).to receive(:announce).with('room1', /Testing notifications for check matching \/\^example.com:p\//)

     expect(Flapjack::Data::Check).to receive(:intersect).
        with(:name => ['example.com:ping']).and_return(all_checks)

      expect(Flapjack::Data::Check).to receive(:attributes_matching_name).
        with("^example.com:p").and_return(['example.com:ping'])

      expect(Flapjack::Data::Event).to receive(:test_notifications).
        with('events', [check], an_instance_of(Hash))

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'test notifications for checks matching /^example.com:p/')
    end

    it "doesn't interpret an unmatched command" do
      expect(bot).to receive(:announce).with('room1', /^what do you mean/)

      fji = Flapjack::Gateways::Jabber::Interpreter.new(:config => config, :logger => @logger)
      fji.instance_variable_set('@bot', bot)
      fji.interpret('room1', 'jim', now.to_i, 'hello!')
    end

  end

  context 'XMPP' do

    let(:client)      { double(::Jabber::Client) }
    let(:muc_client)  { double(::Jabber::MUC::SimpleMUCClient) }
    let(:muc_clients) { {config['rooms'].first => muc_client} }

    # TODO use separate threads in the test instead?
    it "starts and is stopped by a signal" do
      interpreter = double(Flapjack::Gateways::Jabber::Interpreter)
      expect(interpreter).to receive(:respond_to?).with(:interpret).and_return(true)
      expect(interpreter).to receive(:receive_message).with(nil, 'jim', nil, 'hello!')

      expect(client).to receive(:on_exception)

      msg_client = double('msg_client')
      expect(msg_client).to receive(:body).and_return('hello!')
      expect(msg_client).to receive(:from).and_return('jim')
      expect(msg_client).to receive(:each_element).and_yield([]) # TODO improve

      expect(client).to receive(:add_message_callback).and_yield(msg_client)

      expect(muc_client).to receive(:on_message).and_yield(now.to_i, 'jim', 'flapjack: hello!')
      expect(client).to receive(:is_connected?).times.and_return(true)

      expect(::Jabber::Client).to receive(:new).and_return(client)
      expect(::Jabber::MUC::SimpleMUCClient).to receive(:new).and_return(muc_client)

      expect(lock).to receive(:synchronize).and_yield
      stop_cond = double(MonitorMixin::ConditionVariable)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :stop_condition => stop_cond, :config => config, :logger => @logger)
      expect(stop_cond).to receive(:wait_until) {
        fjb.instance_variable_set('@should_quit', true)
      }
      fjb.instance_variable_set('@siblings', [interpreter])

      expect(fjb).to receive(:_join).with(client, muc_clients)
      expect(fjb).to receive(:_leave).with(client, muc_clients)

      fjb.start
    end

    it "should handle an exception and signal for leave and rejoin"

    it "strips XML from a received string"

    it "handles an announce state change" do
      expect(client).to receive(:is_connected?).and_return(true)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      expect(fjb).to receive(:_announce).with(muc_clients)
      fjb.instance_variable_set('@state_buffer', ['announce'])
      fjb.handle_state_change(client, muc_clients)
    end

    it "handles a say state change" do
      expect(client).to receive(:is_connected?).and_return(true)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      expect(fjb).to receive(:_say).with(client)
      fjb.instance_variable_set('@state_buffer', ['say'])
      fjb.handle_state_change(client, muc_clients)
    end

    it "handles a leave state change (when connected)" do
      expect(client).to receive(:is_connected?).and_return(true)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      expect(fjb).to receive(:_leave).with(client, muc_clients)
      fjb.instance_variable_set('@state_buffer', ['leave'])
      fjb.handle_state_change(client, muc_clients)
    end

    it "handles a leave state change (when not connected)" do
      expect(client).to receive(:is_connected?).and_return(false)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      expect(fjb).to receive(:_deactivate).with(muc_clients)
      fjb.instance_variable_set('@state_buffer', ['leave'])
      fjb.handle_state_change(client, muc_clients)
    end

    it "handles a rejoin state change" do
      expect(client).to receive(:is_connected?).and_return(false)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      expect(fjb).to receive(:_join).with(client, muc_clients, :rejoin => true)
      fjb.instance_variable_set('@state_buffer', ['rejoin'])
      fjb.handle_state_change(client, muc_clients)
    end

    it "joins the jabber client" do
      expect(client).to receive(:connect)
      expect(client).to receive(:auth).with('password')
      expect(client).to receive(:send).with(an_instance_of(::Jabber::Presence))

      expect(lock).to receive(:synchronize).twice.and_yield.and_yield

      expect(muc_client).to receive(:join).with('flapjacktest@conference.example.com/flapjack', nil, :history => false)
      expect(muc_client).to receive(:say).with(/^flapjack jabber gateway started/)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      fjb._join(client, muc_clients)
    end

    it "rejoins the jabber client" do
      expect(client).to receive(:connect)
      expect(client).to receive(:auth).with('password')
      expect(client).to receive(:send).with(an_instance_of(::Jabber::Presence))

      expect(lock).to receive(:synchronize).twice.and_yield.and_yield

      expect(muc_client).to receive(:join).with('flapjacktest@conference.example.com/flapjack', nil, :history => false)
      expect(muc_client).to receive(:say).with(/^flapjack jabber gateway rejoining/)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      fjb._join(client, muc_clients, :rejoin => true)
    end

    it "leaves the jabber client (connected)" do
      expect(muc_client).to receive(:active?).and_return(true)
      expect(muc_client).to receive(:exit)
      expect(client).to receive(:close)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      fjb.instance_variable_set('@joined', true)
      fjb._leave(client, muc_clients)
    end

    it "deactivates the jabber client (not connected)" do
      expect(muc_client).to receive(:deactivate)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock,
        :config => config, :logger => @logger)
      fjb._deactivate(muc_clients)
    end

    it "speaks its announce buffer" do
      expect(muc_client).to receive(:active?).and_return(true)
      expect(muc_client).to receive(:say).with('hello!')

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock, :config => config, :logger => @logger)
      fjb.instance_variable_set('@announce_buffer', [{:room => 'room1', :msg => 'hello!'}])
      fjb._announce('room1' => muc_client)
    end

    it "speaks its say buffer" do
      message = double(::Jabber::Message)
      expect(::Jabber::Message).to receive(:new).
        with('jim', 'hello!').and_return(message)

      expect(client).to receive(:send).with(message)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock, :config => config, :logger => @logger)
      fjb.instance_variable_set('@say_buffer', [{:nick => 'jim', :msg => 'hello!'}])
      fjb._say(client)
    end

    it "buffers an announce message and sends a signal" do
      expect(lock).to receive(:synchronize).and_yield
      expect(stop_cond).to receive(:signal)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock, :stop_condition => stop_cond,
        :config => config, :logger => @logger)
      fjb.announce('room1', 'hello!')
      expect(fjb.instance_variable_get('@state_buffer')).to eq(['announce'])
      expect(fjb.instance_variable_get('@announce_buffer')).to eq([{:room => 'room1', :msg => 'hello!'}])
    end

    it "buffers a say message and sends a signal" do
      expect(lock).to receive(:synchronize).and_yield
      expect(stop_cond).to receive(:signal)

      fjb = Flapjack::Gateways::Jabber::Bot.new(:lock => lock, :stop_condition => stop_cond,
        :config => config, :logger => @logger)
      fjb.say('jim', 'hello!')
      expect(fjb.instance_variable_get('@state_buffer')).to eq(['say'])
      expect(fjb.instance_variable_get('@say_buffer')).to eq([{:nick => 'jim', :msg => 'hello!'}])
    end

  end

end
