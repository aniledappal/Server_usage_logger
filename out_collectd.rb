#!/usr/bin/ruby1.9.1

class CollectdOutput < Fluent::BufferedOutput
    Fluent::Plugin.register_output('collectd', self)
    
    config_param :collectd_sock, :string
    config_param :typesdb, :string, :default => "/usr/share/collectd/types.db"
    
    def configure(conf)
        super
    end
    
    def format(tag, time, record)
        return "#{tag}\t#{time}\t#{record.to_json}\n"
    end
    
    def write(chunk)
        sock = UNIXSocket.new @collectd_sock
        # or pass it as @variable?
        typesdb = read_types_db(@typesdb)
        
        chunk.open {|io|
            while not io.eof
                tag, time, record = io.readline.split "\t", 3
                time = Time.at time.to_i
                message = JSON.load(record)
                
                colld = format_message(message, typesdb)
                next if colld == nil
                
                if colld.key? 'interval' and colld['interval'] != nil
                    sock.write sprintf "PUTVAL %s/%s/%s interval=%d %d:%s\n",
                    colld['host'], colld['plugin'], colld['type'],
                    colld['interval'],
                    colld['time'], colld['data'].join(":")
                    else
                    sock.write sprintf "PUTVAL %s/%s/%s %d:%s\n",
                    colld['host'], colld['plugin'], colld['type'],
                    colld['time'], colld['data'].join(":")
                end
                result  = sock.gets("\n").split(/\s+/, 2)
                code    = result[0].to_i
                message = result[1].strip
                if code < 0
                    $log.warn "writing metric failed",
                    :collectd => { :code => code, :message => message },
                    :format  => colld, :message => message
                end
            end
            
        }
        
        sock.close
    end
    
    #---------------------------------------------------------
    # format_message(message, typesdb) -- ModMon -> flat data {{{
    
    def format_message(message, typesdb)
        # TODO: check if everything is in place
        # TODO: get some kind of mapping (should have been provided in
        # configure())
        
        # NOTE: return `nil' on error or if message doesn't match ModMon metric
        # model
        
        location = message['location']
        values   = message['event']['datapoint']['value']
        
        result = {
            'host' => location['host'],
            'time' => message['time'].to_i,
            'interval' => nil,
            'plugin' => nil,
            'type'   => nil,
            'data'   => nil, # [...]
        }
        
        if location.key? 'plugin_instance'
            result['plugin'] = "#{location['plugin']}-#{location['plugin_instance']}"
            else
            result['plugin'] = location['plugin']
        end
        if location.key? 'type_instance'
            result['type'] = "#{location['type']}-#{location['type_instance']}"
            else
            result['type'] = location['type']
        end
        
        if typesdb.key? location['type']
            result['data'] = typesdb[location['type']].map {|v|
                if values[v] != nil; values[v].to_i; else 'U'; end
            }
            else
            # XXX: any order (single value?)
            result['data'] = values.values.map {|v|
                if v != nil; v.to_i; else 'U'; end
            }
        end
        
        result
    end
    
    # }}}
    #---------------------------------------------------------
    # read_types_db(file) -- reload collectd's types.db {{{
    
    def read_types_db(file = "/usr/share/collectd/types.db")
        # TODO: user should be able to provide multiple files
        result = {}
        for l in IO.readlines(file) do
            k, t = l.split /\s+/, 2
            types = t.split(/[[:space:],]+/).map {|k| k.split(/:/)[0]}
            result[k] = types
        end
        result 
        end
        
        # }}}
        #---------------------------------------------------------
    end
    
    # vim:ft=ruby:foldmethod=marker

