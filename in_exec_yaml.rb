# Fluentd plugin for reading output of external program (needs to be YAML)
# main use: cfauditdump

require 'yaml'
require 'socket'

class FinishThread < Exception
end		

class ExecYAML < Fluent::Input
    Fluent::Plugin.register_input('exec_yaml', self)
    
    config_param :command, :string
    config_param :tag, :string
    config_param :run_interval, :time
    config_param :hostname_attr, :string, :default => nil
    
    # NOTE: this will work only for hashes
    config_param :key, :string, :default => nil
    config_param :key_type, :string, :default => 'int' # string | int | float
    config_param :state_file, :string, :default => nil
    
    def configure(conf)
        super
        
        if not @command
            raise Fluent::ConfigError, "'command' option is required for exec_yaml input"
        end
        if not @tag
            raise Fluent::ConfigError, "'tag' option is required for exec_yaml input"
        end
        if not @run_interval
            raise Fluent::ConfigError, "'run_interval' option is required for exec_yaml input"
        end
        
        if @state_file and not @key
            raise Fluent::ConfigError, "'key' option is required for 'state_file' for exec_yaml input"
        end
        if @key_type != 'string' and @key_type != 'int' and @key_type != 'float'
            raise Fluent::ConfigError, "'key_type' option is invalid for exec_yaml input"
        end
        
        $log.debug "emitting #{@tag} with command '#{@command}'"
    end
    
    def start
        @thread = Thread.new(&method(:scheduler))
    end
    
    def shutdown
        @thread.raise(FinishThread.new)
        @thread.join
    end
    
    private
    def scheduler
        $log.debug "starting scheduler with schedule of #{@run_interval}s"
        
        # loop exited manually
        while true
            sleep @run_interval
            
            begin
                data = read_yaml()
                next if not data or data == {} or data == [] or data == ""
                
                if data.is_a?(Array)
                    messages = data
                    else
                    messages = [data]
                end
                
                # read hostname each @run_interval, because hostname could have changed
                # in the meantime (rare, but possible)
                hostname = Socket.gethostname.split(".")[0]
                tag = @tag
                time = Fluent::Engine.now
                
                latest = read_state()
                new_latest = latest
                
                for m in messages
                    # enrich message to be emitted and skip already sent messages
                    if m.is_a?(Hash)
                        # should I add a hostname?
                        if @hostname_attr
                            m[@hostname_attr] = hostname
                        end
                        
                        if @state_file and m.has_key? @key
                            if @key_type == 'string'
                                current = m[@key].to_s
                                elsif @key_type == 'int'
                                current = m[@key].to_i
                                elsif @key_type == 'float'
                                current = m[@key].to_f
                                else # should never happen
                                current = m[@key]
                            end
                            
                            # skip if older than oldest already sent message
                            next if latest and current <= latest
                            
                            # remember largest sent message from this stream
                            new_latest = current if not new_latest or new_latest < current
                        end
                    end
                    
                    # TODO: save state on FinishThread exception
                    $log.debug "emitting message", :type => m.class.to_s
                    Fluent::Engine.emit(tag, time, m)
                end
                
                # save the key of largest message from stream
                save_state new_latest
                
                rescue FinishThread
                $log.debug "finishing scheduler thread"
                break
                rescue
                $log.error "failed to read/emit message", :error => $!
                $log.warn_backtrace $!.backtrace
            end
        end
    end
    
    private
    def read_yaml
        $log.debug "running command", :command => @command
        
        cmd = IO.popen(@command, "r")
        yaml = cmd.read
        Process.waitpid(cmd.pid)
        
        # even if signaled or returned with non-zero code, try to load already
        # produced YAML
        if $?.signaled?
            $log.warn "command got signal", :command => @command, :signal => $?.termsig
            elsif $?.exitstatus != 0
            $log.warn "command exited with non-zero code", :command => @command, :code => $?.exitstatus
        end
        
        # no output is not an error
        if yaml == ""
            $log.debug "command produced no output", :command => @command
            return false
        end
        
        begin
            data = YAML::load(yaml)
            rescue Exception => e
            $log.warn "command produced invalid YAML", :command => @command, :error => e
            return false
        end
        
        if not data
            # no data in YAML is not an error
            $log.debug "command produced empty YAML", :command => @command
        end
        
        return data
    end
    
    private
    def save_state(key)
        return if not @state_file
        return if not key
        return if key == @state_largest
        
        @state_largest = key
        
        f = File::open(@state_file, "w")
        f.write(key.to_s + "\n")
        f.close
    end
    
    private
    def read_state
        return nil if not @state_file
        
        if @state_largest
            return @state_largest
            else
            $log.debug "largest sent message read from file", :file => @state_file
            
            f = File::open(@state_file, "r")
            result = f.read.chomp "\n"
            f.close
            
            if @key_type == 'string'
                return result
                elsif @key_type == 'int'
                return result.to_i
                elsif @key_type == 'float'
                return result.to_f
                else # should never happen
                return nil
            end
        end
        rescue Errno::ENOENT
        $log.debug "file nonexistent, returning nil", :file => @state_file
        return nil
    end
end
