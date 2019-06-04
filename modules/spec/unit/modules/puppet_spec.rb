#!/usr/bin/env rspec
require 'time'

load File.join(File.dirname(__FILE__), "../", "../", "../", "pxp-module-puppet")
FIXTURE_DIR = File.join(File.expand_path(File.dirname(__FILE__)), '../', '../', 'fixtures')

describe Pxp::ModulePuppet do

  let(:default_input) {
    {"flags" => []}
  }

  let(:subject) {
    described_class.new(default_configuration, described_class.process_flags(default_input))
  }

  let(:default_configuration) {
    {"puppet_bin" => "puppet"}
  }

  describe "last_run_result" do
    it "returns the basic structure with exitcode set" do
      expect(described_class.last_run_result(42)).to be == {"time"             => "unknown",
                                                            "transaction_uuid" => "unknown",
                                                            "environment"      => "unknown",
                                                            "status"           => "unknown",
                                                            "metrics"          => {},
                                                            "exitcode"         => 42,
                                                            "version"          => 1}
    end
  end

  describe "handle_action" do
    describe "when the action is 'metadata'" do
      it "prints the metadata" do
        described_class.handle_action('metadata')
      end
    end

    describe "for other actions" do
      it "builds and runs the action" do
        original_stdin = $stdin
        original_stdout = $stdout
        allow_any_instance_of(described_class).to receive(:run).and_return({})
        begin
          $stdin = StringIO.new({"config" => {}, "input" => {}}.to_json)
          $stdout = StringIO.new
          described_class.handle_action('run')
          $stdout.rewind
          result = JSON.parse($stdout.read)
          expect(result).to be == {}
        ensure
          $stdin = original_stdin
          $stdout = original_stdout
        end
      end
    end
  end

  describe "config_print" do
    it "returns the result of configprint" do
      cli_vec = ["puppet", "agent", "--configprint", "key"]
      expect(subject).to receive(:get_env_fix_up).and_return({"FIXVAR" => "fixvalue"})
      expect(Puppet::Util::Execution).to receive(:execute).with(cli_vec,
                                                                {:custom_environment => {"FIXVAR" => "fixvalue"},
                                                                 :override_locale => false}).and_return("value\n")
      expect(subject.config_print("key")).to be == "value"
    end

    it "returns the result of configprint with multiple values" do
      cli_vec = ["puppet", "agent", "--configprint", "key1,key2"]
      expect(subject).to receive(:get_env_fix_up).and_return({"FIXVAR" => "fixvalue"})
      expect(Puppet::Util::Execution).to receive(:execute).with(cli_vec,
                                                                {:custom_environment => {"FIXVAR" => "fixvalue"},
                                                                 :override_locale => false}).and_return("key1 = value1\nkey2 = value2\n")
      expect(subject.config_print("key1", "key2")).to be == {"key1" => "value1", "key2" => "value2"}
    end

    it "returns the result of configprint with UTF-8 even though locale is POSIX" do
      cli_vec = ["puppet", "agent", "--configprint", "value"]
      expect(subject).to receive(:get_env_fix_up).and_return({"FIXVAR" => "fixvalue"})
      expect(Puppet::Util::Execution).to receive(:execute).with(cli_vec,
                                                                {:custom_environment => {"FIXVAR" => "fixvalue"},
                                                                 :override_locale => false}).
                                                                 and_return("value☃".force_encoding(Encoding::US_ASCII))
      expect(subject.config_print("value")).to be == "value☃"
    end
  end

  describe "make_environment_hash" do
    it "should correctly add the env entries" do
      expect(subject).to receive(:get_env_fix_up).and_return({"FIXVAR" => "fixvalue"})
      expect(subject.make_environment_hash()).to be == {"FIXVAR" => "fixvalue"}
    end
  end

  describe "puppet_agent_command" do
    it "should correctly append the executable and action" do
      runner = described_class.new(default_configuration, [])
      expect(runner.puppet_agent_command).to be == ["puppet", "agent"]
    end

    it "should correctly append any flags" do
      default_input["flags"] = ["--noop", "--verbose"]
      expect(subject.puppet_agent_command).to be ==
        ["puppet", "agent", "--noop", "--verbose", "--onetime", "--no-daemonize"]
    end
  end

  describe "make_error_result" do
    it "should set the exitcode, error_type and error_message" do
      expect(described_class.make_error_result(42, Pxp::ModulePuppet::Errors::FailedToStart, "test error")).to be ==
          {"time"             => "unknown",
           "transaction_uuid" => "unknown",
           "environment"      => "unknown",
           "status"           => "unknown",
           "metrics"          => {},
           "error_type"       => "agent_failed_to_start",
           "error"            => "test error",
           "exitcode"         => 42,
           "version"          => 1}
    end
  end

  describe "get_result_from_report" do
    let(:last_run_report_path) {
      File.join(FIXTURE_DIR, 'last_run_report.yaml')
    }

    it "doesn't process the last_run_report if the file doesn't exist" do
      allow(File).to receive(:exist?).and_return(false)
      expect(subject.get_result_from_report(last_run_report_path, 0, Time.now)).to be ==
          {"time"             => "unknown",
           "transaction_uuid" => "unknown",
           "environment"      => "unknown",
           "status"           => "unknown",
           "metrics"          => {},
           "error_type"       => "no_last_run_report",
           "error"            => "#{last_run_report_path} doesn't exist",
           "exitcode"         => 0,
           "version"          => 1}
    end

    it "doesn't process the last_run_report if the file cant be loaded" do
      start_time = Time.now
      allow(File).to receive(:mtime).and_return(start_time+1)
      allow(File).to receive(:exist?).and_return(true)
      allow(subject).to receive(:parse_report).and_raise("error")
      expect(subject.get_result_from_report(last_run_report_path, 0, start_time)).to be ==
          {"time"             => "unknown",
           "transaction_uuid" => "unknown",
           "environment"      => "unknown",
           "status"           => "unknown",
           "metrics"          => {},
           "error_type"       => "invalid_last_run_report",
           "error"            => "#{last_run_report_path} could not be loaded: error",
           "exitcode"         => 0,
           "version"          => 1}
    end

    it "reports an unexpected error if the report wasn't updated after the run" do
      start_time = Time.now
      run_time = Time.now - 10
      last_run_report = {
        'time' => run_time,
        'transaction_uuid' => "ac59acbe-6a0f-49c9-8ece-f781a689fda9",
        'environment' => "production",
        'status' => "changed"
      }

      allow(File).to receive(:mtime).and_return(start_time)
      allow(File).to receive(:exist?).and_return(true)
      allow(subject).to receive(:parse_report).with(last_run_report_path).and_return(last_run_report)

      expect(subject.get_result_from_report(last_run_report_path, -1, start_time)).to be ==
          {"time"             => "unknown",
           "transaction_uuid" => "unknown",
           "environment"      => "unknown",
           "status"           => "unknown",
           "metrics"          => {},
           "error_type"       => "no_last_run_report",
           "error"            => "The Puppet run failed in an unexpected way",
           "exitcode"         => -1,
           "version"          => 1}
    end

    it "processes the last_run_report if it has been updated after the run was kicked" do
      start_time = Time.now
      run_time = Time.now + 10
      last_run_report = {
        'time' => run_time,
        'transaction_uuid' => "ac59acbe-6a0f-49c9-8ece-f781a689fda9",
        'environment' => "production",
        'status' => "changed",
        'metrics' => {},
      }

      allow(File).to receive(:mtime).and_return(start_time+1)
      allow(File).to receive(:exist?).and_return(true)
      allow(subject).to receive(:parse_report).with(last_run_report_path).and_return(last_run_report)

      expect(subject.get_result_from_report(last_run_report_path, -1, start_time)).to be ==
          {"time"             => run_time,
           "transaction_uuid" => "ac59acbe-6a0f-49c9-8ece-f781a689fda9",
           "environment"      => "production",
           "status"           => "changed",
           "metrics"          => {},
           "error_type"       => "agent_exit_non_zero",
           "error"            => "Puppet agent exited with a non 0 exitcode",
           "exitcode"         => -1,
           "version"          => 1}
    end

    it "correctly processes the last_run_report" do
      start_time = Time.parse('2016-01-01')
      result = subject.get_result_from_report(last_run_report_path, 0, start_time)
      result.delete('metrics')
      expect(result).to be ==
        {'time'             => Time.parse('2016-02-24 23:07:21.694017000 +00:00'),
         'transaction_uuid' => '691f00ee-86fa-4563-8b53-f60c1fdae601',
         'environment'      => 'production',
         'status'           => 'changed',
         'exitcode'         => 0,
         'version'          => 1}
    end

    it "includes metrics in the report" do
      start_time = Time.parse('2016-01-01')
      result = subject.get_result_from_report(last_run_report_path, 0, start_time)
      expect(result['metrics']).to be ==
        {'total' => 183,
         'skipped' => 0,
         'failed' => 0,
         'failed_to_restart' => 0,
         'restarted' => 0,
         'changed' => 1,
         'out_of_sync' => 1,
         'scheduled' => 0,}
    end

  end

  describe "run" do
    let(:success_outcome) { Puppet::Util::Execution::ProcessOutput.new('', 0) }
    let(:failure_outcome) { Puppet::Util::Execution::ProcessOutput.new('', 1) }
    let(:disabled_outcome) { Puppet::Util::Execution::ProcessOutput.new("administratively disabled (Reason: 'testing');\nUse 'puppet agent --enable' to re-enable", 1) }
    let(:running_outcome) { Puppet::Util::Execution::ProcessOutput.new('Run of Puppet configuration client already in progress', 1) }

    let(:last_run_report) {
      "/opt/puppetlabs/puppet/cache/state/last_run_report.yaml"
    }

    let(:lockfile) {
      "/opt/puppetlabs/puppet/cache/state/agent_catalog_run.lock"
    }

    let(:disfile) {
      "/opt/puppetlabs/puppet/cache/state/agent_disabled.lock"
    }

    before :each do
      allow(subject).to receive(:config_print).with('lastrunreport', 'agent_disabled_lockfile', 'agent_catalog_run_lockfile')
        .and_return({'lastrunreport' => last_run_report, 'agent_disabled_lockfile' => disfile, 'agent_catalog_run_lockfile' => lockfile})
      allow(subject).to receive(:puppet_bin_present?).and_return(true)
      allow(subject).to receive(:get_start_time).and_return(nil)
    end

    it "fails when puppet_bin doesn't exist" do
      allow(subject).to receive(:puppet_bin_present?).and_return(false)
      expect(subject.run["error"]).to be ==
          "Puppet executable 'puppet' does not exist"
    end

    it "populates output when it terminated normally" do
      allow(Puppet::Util::Execution).to receive(:execute).and_return(success_outcome)
      expect(subject).to receive(:get_result_from_report).with(last_run_report, 0, anything)
      subject.run
    end

    it "populates output when it terminated with a non 0 code" do
      allow(Puppet::Util::Execution).to receive(:execute).and_return(failure_outcome)
      expect(subject).to receive(:get_result_from_report).with(last_run_report, 1, anything)
      subject.run
    end

    it "populates output when it couldn't start" do
      allow(Puppet::Util::Execution).to receive(:execute).and_return(nil)
      expect(described_class).to receive(:make_error_result).with(-1, Pxp::ModulePuppet::Errors::FailedToStart, anything)
      subject.run
    end

    it "populates the output if puppet is disabled" do
      expect(subject).to receive(:disabled?).and_return(true)
      allow(Puppet::Util::Execution).to receive(:execute).and_return(disabled_outcome)
      expect(described_class).to receive(:make_error_result).with(1, Pxp::ModulePuppet::Errors::Disabled, anything)
      subject.run
    end

    it "waits for puppet to finish if already running" do
      allow(subject).to receive(:disabled?).and_return(false)
      expect(Puppet::Util::Execution).to receive(:execute).and_return(running_outcome).ordered
      expect(subject).to receive(:running?).and_return(true).ordered
      expect(subject).to receive(:wait_for_lockfile).with(lockfile).ordered
      expect(Puppet::Util::Execution).to receive(:execute).and_return(success_outcome).ordered

      expect(subject).to receive(:get_result_from_report).with(last_run_report, 0, anything)
      subject.run
    end

    it "retries puppet after 10 minutes if lockfile still present" do
      allow(File).to receive(:exist?).with(lockfile).and_return(true)
      allow(File).to receive(:exist?).with(disfile).and_return(false)

      expect(Puppet::Util::Execution).to receive(:execute).and_return(running_outcome).ordered
      expect(subject).to receive(:running?).and_return(true).ordered
      expect(subject).to receive(:sleep).with(0.1).exactly(6000).times.ordered
      expect(Puppet::Util::Execution).to receive(:execute).and_return(success_outcome).ordered

      expect(subject).to receive(:get_result_from_report).with(last_run_report, 0, anything)
      subject.run
    end

    it "reports a failure if an agent run was in progress when it retried the run" do
      allow(subject).to receive(:disabled?).and_return(false)
      allow(subject).to receive(:running?).and_return(true)
      allow(subject).to receive(:wait_for_lockfile)

      expect(Puppet::Util::Execution).to receive(:execute).and_return(running_outcome).ordered
      expect(Puppet::Util::Execution).to receive(:execute).and_return(running_outcome).ordered

      expect(described_class).to receive(:make_error_result).with(1, Pxp::ModulePuppet::Errors::Locked, anything)
      subject.run
    end

    it "processes output when puppet's output is US_ASCII (POSIX or C locale) and contains non-ASCII" do
      output = "everything normal, we're all fine here ☃".force_encoding(Encoding::US_ASCII)
      allow(Puppet::Util::Execution).to receive(:execute).and_return(Puppet::Util::Execution::ProcessOutput.new(output, 0))
      expect(subject).to receive(:get_result_from_report).with(last_run_report, 0, anything)
      subject.run
    end

    it "processes output when puppet's output contains potentially syntax-significant characters" do
      output = "Who knows what Puppet might do '\"&+/\\()?,.\#!@$_-~'"
      allow(Puppet::Util::Execution).to receive(:execute).and_return(Puppet::Util::Execution::ProcessOutput.new(output, 0))
      expect(subject).to receive(:get_result_from_report).with(last_run_report, 0, anything)
      subject.run
    end
  end

  describe "get_flag_name" do
    it "returns the flag name" do
      expect(described_class.get_flag_name("--spam")).to be == "spam"
    end

    it "returns the flag name in case it's negative" do
      expect(described_class.get_flag_name("--no-spam")).to be == "spam"
    end

    it "returns an empty string in case the flag has only a suffix" do
      expect(described_class.get_flag_name("--")).to be == ""
      expect(described_class.get_flag_name("--no-")).to be == ""
    end

    it "raises an error in case of invalid suffix" do
      expect do
        described_class.get_flag_name("-spam")
      end.to raise_error(RuntimeError, /Assertion error: we're here by mistake/)
    end

    it "raises an error in case the flag has no suffix" do
      expect do
        described_class.get_flag_name("eggs")
      end.to raise_error(RuntimeError, /Assertion error: we're here by mistake/)
    end
  end

  describe "action_metadata" do
    it "has the correct metadata" do
      expect(described_class.metadata).to be == {
        :description => "PXP Puppet module",
        :actions => [
          { :name        => "run",
            :description => "Start a Puppet run",
            :input       => {
              :type      => "object",
              :properties => {
                :env => {
                  :type => "array",
                },
                :flags => {
                  :type => "array",
                  :items => {
                    :type => "string"
                  }
                },
                :job => {
                  :type => "string"
                }
              },
              :required => [:flags]
            },
            :results => {
              :type => "object",
              :properties => {
                :time => {
                  :type => "string"
                },
                :transaction_uuid => {
                  :type => "string"
                },
                :metrics => {
                  :type => "object"
                },
                :environment => {
                  :type => "string"
                },
                :status => {
                  :type => "string"
                },
                :error_type => {
                  :type => "string"
                },
                :error => {
                  :type => "string"
                },
                :exitcode => {
                  :type => "number"
                },
                :version => {
                  :type => "number"
                }
              },
              :required => [:time, :transaction_uuid, :environment, :status,
                            :exitcode, :version]
            }
          }
        ],
        :configuration => {
          :type => "object",
          :properties => {
            :puppet_bin => {
              :type => "string"
            }
          }
        }
      }
    end
  end

  describe "create_runner" do
    it "fails when invalid json is passed" do
      expect(described_class.create_runner("{")["error"]).to be ==
          "Invalid json received on STDIN: {"
    end

    it "fails when the passed json data isn't a hash" do
      expect(described_class.create_runner("[]")["error"]).to be ==
          "The json received on STDIN was not a hash: []"
    end

    it "fails when the passed json data doesn't contain the 'input' key" do
      expect(described_class.create_runner("{\"input\": null}")["error"]).to be ==
          "The json received on STDIN did not contain a valid 'input' key: {\"input\"=>nil}"
    end

    it "fails when the flags of the passed json data are not all whitelisted" do
      passed_args = {"configuration" => default_configuration,
                     "input" => {"flags" => ["--prerun_command", "echo safe"]}}
      expect(described_class.create_runner(passed_args.to_json)["error"]).to be ==
          "The json received on STDIN included a non-permitted flag: --prerun_command"
    end

    it "does not allow changing settings of default flags" do
      passed_args = {"configuration" => default_configuration,
                     "input" => {"flags" => ["--daemonize"]}}
      expect(described_class.create_runner(passed_args.to_json)["error"]).to be ==
          "The json received on STDIN overrides a default setting with: --daemonize"
    end

    it "fails when a non-whitelisted flag of the passed json data has whitespace padding" do
      passed_args = {"configuration" => default_configuration,
                     "input" => {"flags" => ["  --prerun_command", "echo safe"]}}
      expect(described_class.create_runner(passed_args.to_json)["error"]).to be ==
          "The json received on STDIN included a non-permitted flag: --prerun_command"
    end

    it "fails when a non-whitelisted flag of the passed json data has unicode padding" do
      passed_args = {"configuration" => default_configuration,
                     "input" => {"flags" => [" --prerun_command", "echo safe"]}}
      expect(described_class.create_runner(passed_args.to_json)["error"]).to be ==
          "The json received on STDIN contained characters not present in valid flags:  --prerun_command"
    end

    it "fails when a non-whitelisted flag of the passed json data has escaped padding" do
      passed_args = {"configuration" => default_configuration,
                     "input" => {"flags" => ["\\t--prerun_command", "echo safe"]}}
      expect(described_class.create_runner(passed_args.to_json)["error"]).to be ==
          "The json received on STDIN contained characters not present in valid flags: \\t--prerun_command"
    end

    it "builds a runner with the provided config and flags" do
      runner = described_class.create_runner({:configuration => default_configuration, :input => default_input}.to_json)

      expect(runner.config).to be == {'puppet_bin' => 'puppet'}
      expect(runner.flags).to be == ['--onetime', '--no-daemonize', '--verbose']
    end
  end

  describe "process_flags" do
    it "populates flags with the correct defaults" do
      expected_flags = ["--onetime", "--no-daemonize", "--verbose"]
      expect(described_class.process_flags(default_input)).to be == expected_flags
    end

    it "passes --job-id flag if a job id is set" do
      input = default_input.merge('job' => 'foobar')
      expected_flags = ["--onetime", "--no-daemonize", "--verbose", "--job-id", "foobar"]

      expect(described_class.process_flags(input)).to be == expected_flags
    end

    it "does not add flag defaults if they have been passed" do
      expected_flags = ["--show_diff", "--onetime", "--no-daemonize", "--verbose"]
      input = {"flags" => ["--show_diff", "--onetime", "--no-daemonize"]}

      expect(described_class.process_flags(input)).to be == expected_flags
    end

    it "allows passing arguments of flags" do
      expected_flags = ["--environment", "the_environment",
                        "--onetime", "--no-daemonize", "--verbose"]
      input = {"flags" => ["--environment", "the_environment"]}

      expect(described_class.process_flags(input)).to be == expected_flags
    end

    it "allows passing the obsolete `env` input array" do
      expected_flags = ["--onetime", "--no-daemonize", "--verbose"]
      input = {"env" => ["MY_PATH", "/some/path"],
               "flags" => []}

      expect(described_class.process_flags(input)).to be == expected_flags
    end
  end
end
