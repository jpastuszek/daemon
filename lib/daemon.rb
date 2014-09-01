class Daemon
	class LockError < RuntimeError
		def initialize(pid_file)
			super("cannot lock pid file '#{pid_file.path}', process already running with pid: #{pid_file.read.strip}")
		end
	end

	def self.daemonize(pid_file, log_file = nil, sync = true)
		if block_given?
			spawn do |send_ok, send_error|
				log = begin
					# try to lock before we kill stdin/out
					lock(pid_file)

					# close I/O
					disconnect(log_file, sync)
				rescue => error
					send_error.call(error)
				end

				send_ok.call

				yield log
			end # => pid, wait
		else
			# become new process group leader
			fence

			# try to lock before we kill stdin/out
			lock(pid_file)

			# close I/O
			disconnect(log_file, sync) # => log
		end
	end

	def self.spawn
		r, w = IO.pipe

		pid = fence do
			r.close

			yield(
				->{
					w.write Marshal.dump(nil) # send OK to parent
					w.close
				},
				->(error){
					w.write Marshal.dump(error) # send error to parent
					w.close
					exit 42
				}
			)
		end
		thr = Process.detach(pid)

		w.close
		data = r.read
		data.empty? and fail 'ok/error handler not called!'

		if error = Marshal.load(data)
			thr.join # wait for child to die
			raise error
		end

		return pid, thr
	ensure
		w.close unless w.closed?
		r.close
	end

	def self.fence
		if block_given?
			fork do
				Process.setsid # become new session leader
				# now in child
				yield
			end # => pid
		else
			exit! 0 if fork
			Process.setsid # become new session leader
			# now in child
		end
	end

	def self.lock(pid_file)
		pf = File.open(pid_file, File::RDWR | File::CREAT)
		raise LockError, pf unless pf.flock(File::LOCK_EX | File::LOCK_NB)
		pf.truncate(0)
		pf.write(Process.pid.to_s + "\n")
		pf.flush

		@pf = pf # keep it open and locked until process exits
	end

	def self.disconnect(log_file = nil, sync = true)
		if log_file
			log = File.open(log_file, 'ab') # TODO: use flags as above
			log.sync = sync
		else
			# don't raise on STDOUT/STDERR write
			log = File.new('/dev/null', 'w')
		end

		# disconnect
		STDIN.close # raise IOError on STDIN.read
		STDOUT.reopen log
		STDERR.reopen log

		# provide log IO
		return log
	end
end
