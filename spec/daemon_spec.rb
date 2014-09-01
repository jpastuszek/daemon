require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'daemon'
require 'timeout'
require 'tempfile'

describe Daemon do
	let! :pid_file do
		Tempfile.new('daemon-pid')
	end

	let! :log_file do
		Tempfile.new('daemon-log')
	end

	describe 'locking' do
		it '#lock should create a pid file with current process pid' do
			Daemon.lock(pid_file)
			File.open(pid_file).read.should == "#{Process.pid}\n"
		end

		it '#lock should raise error if called twice on same pid file' do
			Daemon.lock(pid_file)
			lambda {
				Daemon.lock(pid_file)
			}.should raise_error Daemon::LockError
		end
	end

	describe 'forking' do
		it 'forked sub process can be terminated with SIGHUP to whole process group' do
			cr, cw = *IO.pipe
			mr, mw = *IO.pipe

			pid = fork do # parent
				Process.setsid # start new process group

				pid = fork do # child
					loop{cr.readline and mw.puts 'pong'}
				end
				Process.wait(pid)
			end

			# close our end
			mw.close
			cr.close

			# wait for the child to start
			cw.puts 'ping'
			mr.readline.strip.should == 'pong'

			Process.kill('HUP', -pid) # kill the group; this should kill the child
			Process.wait(pid) # parent exit

			expect {
				Timeout.timeout(2) do
					# child is dead
					cw.puts 'ping'
				end
			}.to raise_error Errno::EPIPE
		end

		it '#fence should start new process group to protect the process from HUP signal' do
			cr, cw = *IO.pipe
			mr, mw = *IO.pipe

			pid = fork do # parent
				Process.setsid # start new process group

				Daemon.fence

				# now in protected child
				loop{cr.readline and mw.puts 'pong'}
			end
			Process.wait(pid) # parent exits

			# close our end
			mw.close
			cr.close

			# wait for the child to start
			cw.puts 'ping'
			mr.readline.strip.should == 'pong'

			expect {
				Process.kill('HUP', -pid)
				# the group is gone with the parent process
			}.to raise_error Errno::ESRCH

			Timeout.timeout(2) do
				# child still there
				cw.puts 'ping'
				mr.readline.strip.should == 'pong'
			end
		end

		it '#fence with block should start new process group to protect the process from HUP signal calling provided block within it' do
			cr, cw = *IO.pipe
			mr, mw = *IO.pipe

			pid = fork do # parent
				Process.setsid # start new process group

				pid = Daemon.fence do
					# now in protected child
					loop{cr.readline and mw.puts 'pong'}
				end

				Process.wait(pid)
			end

			# close our end
			mw.close
			cr.close

			# wait for the child to start
			cw.puts 'ping'
			mr.readline.strip.should == 'pong'

			Process.kill('HUP', -pid) # kill the group; this would kill the child
			Process.wait(pid) # parent exit

			Timeout.timeout(2) do
				# child still there
				cw.puts 'ping'
				mr.readline.strip.should == 'pong'
			end
		end

		it '#spawn should call block in fenced child process and return child pid and wait thread' do
			pid, wait = Daemon.spawn do |send_ok, send_error|
				send_ok.call
				sleep 0.2
			end

			pid.should > 0
			wait.should be_alive

			wait.value.should be_success
		end

		it '#spawn should call block in fenced child process raising reported errors in master' do
			expect {
				Daemon.spawn do |send_ok, send_error|
					begin
						fail 'test'
					rescue => error
						send_error.call error
					end
				end
			}.to raise_error RuntimeError, 'test'
		end
	end

	describe 'IO handling' do
		it '#disconnect should close STDIN and redirect STDIN and STDERR to given log file' do
			pid = fork do
				Daemon.disconnect(log_file)

				puts 'hello world'
				begin
					STDIN.read # should raise
				rescue IOError
					puts 'foo bar'
				end
			end
			Process.wait(pid)

			log_file.readlines.map(&:strip).should == ['hello world', 'foo bar']
		end

		it '#disconnect should provide log file IO' do
			pid = fork do
				log = Daemon.disconnect(log_file)
				log.puts 'hello world'
				puts 'foo bar'
			end
			Process.wait(pid)

			log_file.readlines.map(&:strip).should == ['hello world', 'foo bar']
		end

		it '#disconnect should provide /dev/null file IO when no log file specified' do
			pid = fork do
				log = Daemon.disconnect
				log.puts 'foo bar'
				log.path.should == '/dev/null'
			end

			Process.wait2(pid).last.should be_success
		end

		it '#disconnect should append log file' do
			pid = fork do
				Daemon.disconnect(log_file)
				puts 'hello world'
			end
			Process.wait(pid)

			pid = fork do
				Daemon.disconnect(log_file)
				puts 'foo bar'
			end

			Process.wait(pid)
			log_file.readlines.map(&:strip).should == ['hello world', 'foo bar']
		end
	end

	it '#deamonize should terminate current process while keeping the script running' do
		log_file.open do |log|

			pid = fork do
				puts master_pid = Process.pid
				Daemon.daemonize(pid_file, log_file, true)
				Process.pid.should_not == master_pid
				puts 'hello world'
			end

			Process.wait2(pid).last.should be_success # wait for master to go away (successfully)

			log.readline.map(&:strip).should == ['hello world']
		end
	end

	it '#deamonize should return log file IO' do
		log_file.open do |log|
			pid = fork do
				log = Daemon.daemonize(pid_file, log_file, true)
				log.puts 'hello world'
			end
			Process.wait2(pid).last.should be_success # wait for master to go away

			log.readline.map(&:strip).should == ['hello world']
		end
	end

	it '#daemonize with block should fork new process with pid file and log file and call block with log IO' do
		pid, wait = Daemon.daemonize(pid_file, log_file) do |log|
			log.puts 'hello world'
			puts 'foo bar'
		end

		# wait for process to finish
		wait.join

		log_file.readlines.map(&:strip).should == ['hello world', 'foo bar']
	end

	it '#daemonize with block should raise error when lock file is busy' do
		pid, wait = Daemon.daemonize(pid_file, log_file) do |log|
			log.puts 'hello world'
			puts 'foo bar'
			sleep 1
		end

		expect {
			Daemon.daemonize(pid_file, log_file){|log|}
		}.to raise_error Daemon::LockError

		Process.kill('TERM', pid)
		wait.join

		log_file.readlines.map(&:strip).should == ['hello world', 'foo bar']
	end

	it '#daemnize should not call at_exit handler' do
		pid = fork do
			pid = Process.pid
			at_exit do
				fail 'at_exit called' if pid != Process.pid
			end

			fork do
				Daemon.daemonize(pid_file, '/dev/stdout')
				exit! # dont call at_exit
			end
			Process.wait
		end
		Process.wait2(pid).last.should be_success
	end
end

