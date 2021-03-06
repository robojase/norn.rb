require "norn/util/memory-store"
require "norn/util/worker"
Dir[File.dirname(__FILE__) + '/../world/**/*.rb'].each do |file| require file end

class Script < Thread
  RUNNING = MemoryStore.new(:scripts)

  SUPERVISOR = Norn::Worker.new(:script_supervisor) do      
    RUNNING.each do |name, script, store|
      unless script.alive?
        store.delete(name)
      end
    end
  end

  def self.running?(name)
    fetch(name) && fetch(name).alive?
  end

  def self.running
    fetch
  end

  def self.fetch(name = nil)
    RUNNING.fetch(name)
  end

  def self.register(name, script)
    RUNNING.put(name, script)
    self
  end

  def self.kill(name)
    fetch(name).kill
    RUNNING.delete(name)
    self
  end

  def self.label(*labels)
    labels.flatten.compact.map(&:to_s)
      .join(".")
      .gsub(/\s+/, "")
  end

  def self.current
    fetch.values.find do |script|
      Thread.current == script
    end
  end

  attr_reader :name, :code, :mode
  attr_accessor :result, :package
  
  def initialize(name, mode: :normal)
    @name   = name
    @mode   = mode
    @start  = Time.now
    script  = self
    super do
      script.write(%{running}, label: :up) unless silent?
      work = Try.new do
        yield self
        @code = 0
      end
      if work.failed?
        @code = 1 if ok?
        write work.result.message
        write work.backtrace.join("\n")
      end
      script.write(%{status:#{script.code} time:#{script.uptime}s}, label: :end) unless silent?
      Script.kill(@name)
    end
    Script.register(@name, self)
  end

  def debug?
    mode == :debug
  end

  def silent?
    mode == :silent
  end

  def ok?
    @code = 0
  end

  def debug(*args, label: nil)
    return self unless debug?
    write(*args, 
      label: [:debug] + [label])
  end

  def view(t, label: nil)
    "[#{Script.label(@name, label)}] " + t.to_s.gsub(/(<|>&)/) do 
      CGI.escape_html $1
    end
  end

  def await
    sleep 0.1 while alive?
    @result
  end

  def write(*strs, label: nil)
    begin
      strs.each do |str|
        output = view(str, label: label)
        puts output
        if Norn.game.nil?
          puts output
        else
          Norn.game.write_to_clients output
        end
      end
    rescue Exception => e
      unless Norn.game.nil?
        Norn.game.write_to_clients(e.message)
        Norn.game.write_to_clients(e.backtrace.join("\n"))
      end
      puts e.message
      puts e.backtrace.join("\n")
    end
    self
  end

  def dead?
    !alive?
  end
  
  def to_s
    "<Script:#{@name} @uptime=#{uptime.as_time}>"
  end

  def uptime
    Time.now - @start
  end
end