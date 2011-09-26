require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'daemon'

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

	after :each do
		File.unlink($pf) if File.exist?($pf)
	end
end

