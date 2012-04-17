require "qless/lua"
require "redis"
require "json"

module Qless
  class Job
    attr_reader :jid, :expires, :state, :queue, :history, :worker, :retries, :remaining, :failure, :klass, :delay, :tracked
    attr_accessor :data, :priority, :tags
    
    def perform
      klass = @klass.split('::').inject(nil) { |m, el| (m || Kernel).const_get(el) }
    end
    
    def initialize(client, atts)
      @client    = client
      %w{jid data klass priority tags worker expires state tracked queue
        retries remaining failure history dependencies dependents}.each do |att|
        self.instance_variable_set("@#{att}".to_sym, atts.fetch(att))
      end
      @delay = atts.fetch('delay', 0)

      # This is a silly side-effect of Lua doing JSON parsing
      @tags         = [] unless @tags != {}
      @dependents   = [] unless @depenents != {}
      @dependencies = [] unless @dependencies != {}
    end
    
    def [](key)
      @data[key]
    end
    
    def []=(key, val)
      @data[key] = val
    end
    
    def to_s
      inspect
    end
    
    def inspect
      "< Qless::Job #{@jid} >"
    end
    
    def ttl
      @expires - Time.now.to_f
    end
    
    # Move this from it's current queue into another
    def move(queue)
      @client._put.call([queue], [
        @jid, @klass, JSON.generate(@data), Time.now.to_f, 0
      ])
    end
    
    # Fail a job
    def fail(group, message)
      @client._fail.call([], [
        @jid,
        @worker,
        group, message,
        Time.now.to_f,
        JSON.generate(@data)]) || false
    end
    
    # Heartbeat a job
    def heartbeat()
      @client._heartbeat.call([], [
        @jid,
        @worker,
        Time.now.to_f,
        JSON.generate(@data)]) || false
    end
    
    # Complete a job
    # Options include
    # => next (String) the next queue
    # => delay (int) how long to delay it in the next queue
    def complete(nxt=nil, options={})
      if nxt.nil?
        response = @client._complete.call([], [
          @jid, @worker, @queue, Time.now.to_f, JSON.generate(@data)])
      else
        response = @client._complete.call([], [
          @jid, @worker, @queue, Time.now.to_f, JSON.generate(@data), 'next', nxt, 'delay',
          options.fetch(:delay, 0), 'depends', JSON.generate(options.fetch(:depends, []))])
      end
      response.nil? ? false : response
    end
    
    def cancel
      @client._cancel.call([], [@jid])
    end
    
    def track(*tags)
      @client._track.call([], ['track', @jid, Time.now.to_f] + tags)
    end
    
    def untrack
      @client._track.call([], ['untrack', @jid, Time.now.to_f])
    end
    
    def depend(*jids)
      !!@client._depends.call([], [@jid, 'on'] + jids)
    end
    
    def undepend(*jids)
      !!@client._depends.call([], [@jid, 'off'] + jids)
    end
  end  
end