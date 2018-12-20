#
# TCP keepalive hack applied to in_forward plugin from standard Fluentd
# distribution.
#

module Fluent
    
    class ForwardInput
        class Handler
            _old_initialize = self.instance_method :initialize
            
            define_method(:initialize) do |io,on_message|
            result = _old_initialize.bind(self).call(io, on_message)
            
            if io.is_a?(TCPSocket)
            opt = [1].pack("I!")  # { int bool_value; }
            v = io.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, opt)
            # 75 seconds of idle before sending first keepalive message; value the
            # same as Linux' default interval between keepalive messages
            opt = [75].pack("I!") # { int idle_time; }
            v = io.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_KEEPIDLE, opt)
        end
        
        result
    end
end
end

end
