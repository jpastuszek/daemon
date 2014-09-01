require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'daemon'
require 'timeout'

$pf = 'test.pid'

describe Daemon do
	it '#lock should create a pid file with current process pid' do
		Daemon.lock($pf)
		File.open($pf).read.should == "#{Process.pid}\n"
	end

	it '#lock should raise error if called twice on same pid file' do
		Daemon.lock($pf)
		lambda {
			Daemon.lock($pf)
		}.should raise_error Daemon::LockError
	end

	it '#fence should start new process group to protect the process from HUP signal' do
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

		#### Now with the #fence used
		cr, cw = *IO.pipe
		mr, mw = *IO.pipe

		pid = fork do # parent
			Process.setsid # start new process group

			Daemon.fence
			loop{cr.readline and mw.puts 'pong'}
		end
		Process.wait # parent exits

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
			cw.puts 'ping'
			mr.readline.strip.should == 'pong'
		end
	end

	it 'should not call at_exit handler during daemonization' do
		pid = Process.pid
		at_exit do
			fail 'at_exit called' if pid != Process.pid
		end

		fork do
			Daemon.daemonize($pf, '/dev/stdout')
			exit! # dont call at_exit
		end
		Process.wait
	end

	after :each do
		File.unlink($pf) if File.exist?($pf)
	end
end

