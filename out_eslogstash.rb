#!/usr/bin/ruby1.9.1

#-----------------------------------------------------------------------------
# ElasticSearch minimalistic client

require 'net/http'
require 'socket'
require 'uri'
require 'json'

class ElasticSearchError < Exception
    #def initialize(msg)
    #  super(msg)
    #end
end

class ElasticSearchClient
    
    #---------------------------------------------------------
    # properties required by Kibana (set by logstash)
    
    @@es_logstash_mappings = {
    "_default_" => {
    "properties" => {
    "@timestamp" => {
    "type"             => "date",
    "format"           => "dateOptionalTime",
    "ignore_malformed" => false,
    }
    }
    }
    }
    
    #---------------------------------------------------------
    # constructor
    
    def initialize(url = "http://localhost:9200/")
        u = URI.parse(url)
        @host = u.host
        @port = u.port
        @path = u.path.chomp "/"
        @http = Net::HTTP.new(@host, @port)
    end
    
    #---------------------------------------------------------
    # checking/creating an index
    
    def has_index(index = "logstash-#{today}")
        result = @http.get "#{@path}/#{index}/_mapping"
        return result.code.to_i / 100 == 2
    end
    
    def set_index(index = "logstash-#{today}")
        json = { "mappings" => @@es_logstash_mappings }.to_json
        result = @http.put("#{@path}/#{index}", json)
        if result.code.to_i / 100 == 4
            data = JSON.load result.body
            raise ElasticSearchError, data['error']
        end
    end
    
    #---------------------------------------------------------
    
    # following message metadata fields are used by logstash:
    #   "@type"        => "..."
    #   "@timestamp"   => ISO 8601 entry time
    #   "@fields"      => { parsed message }
    #   "@message"     => { parsed message }.to_json
    #   "@tags"        => [...]
    #   "@source"      => "fluent://what-host/..."
    #   "@source_host" => "what-host"
    #   "@source_path" => "/..."
    def store(index = "logstash-#{today}", type, data)
        time    = data[:time] || Time.now
        fields  = data[:fields] || {}
        message = data[:message] || fields.to_json
        tags    = data[:tags] || []
        if data[:source] and not (data[:source_host] and data[:source_path])
            # fill missing host/path from URI
            host_uri = URI.parse source
            source      = data[:source]
            source_host = data[:source_host] || host_uri.host
            source_path = data[:source_path] || host_uri.path
            else
            # autodetect host, if required
            source_host = data[:source_host] || Socket.gethostname
            # by default path is null
            source_path = data[:source_path] || ""
            # fill source URI if it's missing
            source = data[:source] || sprintf("fluent://%s/%s",
                                              source_host,
                                              source_path.sub(/^\//, ""))
        end
        
        url = "#{@path}/#{index}/#{type}"
        post_data = {
            "@type"        => type,
            "@timestamp"   => timestamp(time),
            "@fields"      => fields,
            "@message"     => message,
            "@tags"        => tags,
            "@source"      => source,
            "@source_host" => source_host,
            "@source_path" => source_path,
        }
        result = @http.post(url, post_data.to_json)
        data = JSON.load result.body
        if result.code.to_i / 100 == 4
            raise ElasticSearchError, data['error']
        end
        return data
    end
    
    #---------------------------------------------------------
    # auxiliary methods
    
    # date usable to define index name compatible with logstash
    def today(time = Time.now)
        return time.getutc.strftime "%Y.%m.%d"
    end
    
    # ISO 8601 time format
    def timestamp(time = Time.now)
        # require 'time'
        # time.getutc.getutc.iso8601
        return time.getutc.strftime "%Y-%m-%dT%H:%M:%S.%6NZ"
    end
end

#-----------------------------------------------------------------------------

class ElasticSearchLogStash < Fluent::BufferedOutput
    Fluent::Plugin.register_output('eslogstash', self)
    
    config_param :url, :string
    config_param :src_host_attr, :string, :default => nil
    config_param :src_path_attr, :string, :default => nil
    config_param :src_uri_attr , :string, :default => nil
    
    def configure(conf)
        super
        
        if not @url
            raise Fluent::ConfigError, "'url' option is not defined for eslogstash output"
        end
        
        @es = ElasticSearchClient.new @url
        @last_write = @es.today
        @index = "logstash-#{@last_write}"
        if not @es.has_index @index
            @es.set_index @index
        end
    end
    
    # unneeded
    #def start
    #  super
    #end
    
    # unneeded
    #def shutdown
    #  super
    #end
    
    def format(tag, time, record)
        json = record.to_json
        if not json.valid_encoding?
            # replace non-UTF characters, if any
            json.encode! "utf-8", "binary", :undef => :replace
        end
        return "#{tag}\t#{time}\t#{json}\n"
    end
    
    def write(chunk)
        chunk.open {|io|
            while not io.eof
                tag, time, record = io.readline.split "\t", 3
                time = Time.at time.to_i
                # this was stored as valid UTF-8, now make it UTF-8 back
                record.force_encoding "utf-8"
                
                # if the day from record's timestamp has changed since the last write,
                # change the index where the record will land
                if @es.today(time) != @last_write
                    @last_write = @es.today(time)
                    @index = "logstash-#{@last_write}"
                    
                    # try to create new index; this is quite important, because this
                    # will set a template for "@timestamp" metadata field, what is
                    # required for Kibana to work properly
                    begin
                        @es.set_index @index
                        rescue Exception => e
                        # TODO: filter out "index already exists" exception, what is
                        # possible when time shifted back or log entries came not in clock
                        # order
                        $log.warn "Error while creating ElasticSearch index", :reason => e.to_s
                    end
                end
                
                begin
                    # TODO: change this to bulk INSERTs
                    payload = JSON.load(record)
                    src_host = @src_host_attr ? payload[@src_host_attr] : nil
                    src_path = @src_path_attr ? payload[@src_path_attr] : nil
                    src_uri  = @src_uri_attr  ? payload[@src_uri_attr]  : nil
                    
                    @es.store @index, tag,
                    :fields  => payload,
                    :message => record, # could be left nil as well
                    :time    => time,
                    :source_host => src_host,
                    :source_path => src_path,
                    :source      => src_uri,
                    :tags    => tag.split(".")
                    rescue ElasticSearchError => e
                    $log.warn "Error in connection to ElasticSearch", :reason => e.to_s
                    rescue JSON::ParserError => e
                    # most possibly buffer a record was not written fully
                    $log.warn "JSON parse error (disk was full at some point?)",
                    :reason => e.to_s, :record => record
                end
            end
        }
    end
    
end

__END__
