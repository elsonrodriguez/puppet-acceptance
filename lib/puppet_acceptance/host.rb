module PuppetAcceptance
  class Host
    def self.create(name, overrides, defaults)
      case overrides['platform']
      when /windows/;
        Windows::Host.new(name, overrides, defaults)
      else
        Unix::Host.new(name, overrides, defaults)
      end
    end

    # A cache for active SSH connections to our execution nodes.
    def initialize(name, overrides, defaults)
      @name,@overrides,@defaults = name,overrides,defaults
    end
    def []=(k,v)
      @overrides[k] = v
    end
    def [](k)
      @overrides.has_key?(k) ? @overrides[k] : @defaults[k]
    end
    def to_str
      @name
    end
    def to_s
      @name
    end
    def +(other)
      @name+other
    end

    attr_reader :name, :overrides

    # Wrap up the SSH connection process; this will cache the connection and
    # allow us to reuse it for each operation without needing to reauth every
    # single time.
    def ssh
      tries = 1
      @ssh ||= begin
                 Net::SSH.start(self, self['user'], self['ssh'])
               rescue
                 tries += 1
                 if tries < 4
                   puts "Try #{tries} -- Host Unreachable"
                   puts 'Trying again in 20 seconds'
                   sleep 20
                   retry
                 end
               end
    end

    def close
      if @ssh
        @ssh.close
      end
    end

    def do_action(verb,*args)
      result = Result.new(self,args,'','',0)
      Log.debug "#{self}: #{verb}(#{args.inspect})"
      yield result unless $dry_run
      result
    end

    def exec(command, options)
      do_action('RemoteExec',command) do |result|
        ssh.open_channel do |channel|
          if options[:pty] then
            channel.request_pty do |ch, success|
              if success
                puts "Allocated a PTY on #{@name} for #{command.inspect}"
              else
                abort "FAILED: could not allocate a pty when requested on " +
                  "#{@name} for #{command.inspect}"
              end
            end
          end

          channel.exec(command) do |terminal, success|
            abort "FAILED: to execute command on a new channel on #{@name}" unless success
            terminal.on_data do |ch, data|
              result.stdout << data
              result.output << data
            end
            terminal.on_extended_data do |ch, type, data|
              if type == 1
                result.stderr << data
                result.output << data
              end
            end
            terminal.on_request("exit-status") { |ch, data|       result.exit_code = data.read_long  }

            # queue stdin data, force it to packets, and signal eof: this
            # triggers action in many remote commands, notably including
            # 'puppet apply'.  It must be sent at some point before the rest
            # of the action.
            terminal.send_data(options[:stdin].to_s)
            terminal.process
            terminal.eof!
          end
        end
        # Process SSH activity until we stop doing that - which is when our
        # channel is finished with...
        ssh.loop
      end
    end

    def do_scp(source, target)
      do_action("ScpFile",source,target) { |result|
        # Net::Scp always returns 0, so just set the return code to 0 Setting
        # these values allows reporting via result.log(test_name)
        result.stdout = "SCP'ed file #{source} to #{@host}:#{target}"
        result.stderr=nil
        result.exit_code=0
        recursive_scp='false'
        recursive_scp='true' if File.directory? source
        ssh.scp.upload!(source, target, :recursive => recursive_scp)
      }
    end
  end

  require File.expand_path(File.join(File.dirname(__FILE__), 'host/windows'))
  require File.expand_path(File.join(File.dirname(__FILE__), 'host/unix'))
end
