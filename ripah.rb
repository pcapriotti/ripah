require 'qtutils'
require 'uri'
require 'net/http'

$KCODE = 'UTF8'

class Ripah < KDE::XmlGuiWindow
  def initialize(filename)
    super nil
    
    @loader = StaticLoader.new(filename)
    
    widget = Qt::Widget.new(self)
    layout = Qt::VBoxLayout.new(widget)
    @box = Qt::TextEdit.new(widget)
    @display = Qt::TextEdit.new(widget)
    
    @format = @display.current_char_format
    @format_typed = @display.current_char_format
    @format_typed.foreground = Qt::Brush.new(Qt::blue)
    
    @format_current = @display.current_char_format
    @format_current.font_underline = true
    
    @format_mistake = @display.current_char_format
    @format_mistake.font_underline = true
    @format_mistake.foreground = Qt::Brush.new(Qt::red)
    
    @display.read_only = true
    
    new_label = lambda do
      label = Qt::Label.new(status_bar)
      status_bar.add_permanent_widget(label)
      label
    end
    @info = {
      :speed => new_label[],
      :average => new_label[],
      :words => new_label[],
      :time => new_label[],
      :mistakes => new_label[] }
    
    layout.add_widget(@display)
    layout.add_widget(@box)
    
    self.central_widget = widget
    setupGUI
    
    @text = @loader.get_text(100, 1000).gsub(/\s*$/, '')
    self.text = @text
    
    @time = Qt::Time.new
    @timer = Qt::Timer.new
    @meter = Meter.new(20)
    @in_mistake = false
    @mistakes = 0
    
    @timer.connect(SIGNAL('timeout()')) do
      @meter.add_constant_measure(@time.elapsed)
      @info[:speed].text = "Speed: #{format_speed(@meter.speed)}"
      @info[:average].text = "Average: #{format_speed(@meter.avg_speed)}"
      @info[:words].text = "Words: #{@meter.value / 5}"
      @info[:time].text = "Time: #{@time.elapsed / 1000}s"
      @info[:mistakes].text = "Mistakes: #{@mistakes}"
    end
    
    @box.connect(SIGNAL('textChanged()')) do
      unless @timer.is_active
        @time.restart
        @timer.start(500)
      end
      
      input = @box.plainText
      if input == @text
        @timer.stop
        
        @info.values.each do |label|
          font = label.font
          font.bold = true
          label.font = font
        end
        
        @box.read_only = true
        
        cursor = Qt::TextCursor.new(@display.document)
        cursor.move_position(Qt::TextCursor::End, Qt::TextCursor::KeepAnchor)
        cursor.charFormat = @format_typed
      elsif input == @text[0...input.size]
        cursor = Qt::TextCursor.new(@display.document)
        cursor.move_position(Qt::TextCursor::End, Qt::TextCursor::KeepAnchor)
        cursor.charFormat = @format
        
        cursor.position = @box.textCursor.position
        @display.textCursor = cursor
        @display.move_cursor(Qt::TextCursor::Down)
        @display.ensure_cursor_visible
        
        # select typed part
        cursor.set_position(0, Qt::TextCursor::KeepAnchor)
        cursor.charFormat = @format_typed
        
        # select current word
        cursor.position = @box.textCursor.position
        cursor.move_position(Qt::TextCursor::StartOfWord)
        cursor.move_position(Qt::TextCursor::EndOfWord, Qt::TextCursor::KeepAnchor)
        cursor.charFormat = @format_current
        
        @meter.add_measure(@time.elapsed, @box.plainText.size)
        
        @in_mistake = false
      else
        # select current word
        cursor = Qt::TextCursor.new(@display.document)
        cursor.position = @box.textCursor.position
        cursor.move_position(Qt::TextCursor::StartOfWord)
        cursor.move_position(Qt::TextCursor::EndOfWord, Qt::TextCursor::KeepAnchor)
        cursor.charFormat = @format_mistake
        
        @meter.add_constant_measure(@time.elapsed)
        @mistakes += 1 unless @in_mistake
        @in_mistake = true
      end
    end
  end
  
  def text=(str)
    str ||= '(nothing to display)'
    @display.setPlainText(str)
    cursor = Qt::TextCursor.new(@display.document)
    cursor.position = 0
    @display.textCursor = cursor
    @display.ensure_cursor_visible
  end
  
  private
  
  def format_speed(speed)
    if speed
      "%4f" % (speed * 12000)
    else
      "???"
    end
  end
end

class Meter
  def initialize(size)
    @size = size
    @data = Array.new(@size, [0, 0])
    @index = 0
  end
  
  def add_measure(mark, value)
    @data[@index] = [mark, value]
    @index = (@index + 1) % @size
  end
  
  def add_constant_measure(mark)
    add_measure(mark, value)
  end
  
  def speed
    mark0, value0 = @data[@index]
    mark1, value1 = @data[(@index - 1) % @size]
    
    delta = mark1 - mark0
    if delta > 0
      (value1 - value0).to_f / delta
    end
  end
  
  def avg_speed
    mark, value = @data[(@index - 1) % @size]
    if mark > 0
      value.to_f / mark
    end
  end
  
  def value
    @data[(@index - 1) % @size][1]
  end
end

class StaticLoader
  def initialize(filename)
    @filename = filename
  end
  
  def get_text(*args)
    File.open(@filename, 'r') do |file|
      file.read
    end
  end
end

class WikipediaLoader
  def initialize(language)
    @url = URI.parse("http://#{language}.wikipedia.org/wiki/Special:Random")
  end
  
  def get_text(min_length, max_length)
    resp = Net::HTTP.get_response(@url)
    actual_uri = nil
    if resp.is_a? Net::HTTPRedirection
      actual_uri = resp['location']
    end
    
    if actual_uri
      resp = Net::HTTP.get_response(URI.parse(actual_uri))
      if resp.is_a? Net::HTTPSuccess
        resp.body
      end
    end
  rescue Errno::ECONNREFUSED, Net::HTTPExceptions => e
    puts e
    puts e.backtrace
  end
end

#### STARTUP

app = KDE::Application.init(
  :id => 'ripah',
  :name => KDE::ki18n('Ripah'),
  :version => '0.1',
  :description => KDE::ki18n('A typing practice application'),
  :copyright => KDE::ki18n('(c) 2009 Paolo Capriotti'),
  :authors => [KDE::ki18n('Paolo Capriotti'), 
               KDE::ki18n('p.capriotti@gmail.com')],
  :contributors => [],
  :options => [['+file', KDE.ki18n('File containing text to type')]])
    
args = KDE::CmdLineArgs.parsed_args
filename = if args.count > 0
  args.arg(0)
end
if filename && File.exist?(filename)
  main = Ripah.new(filename)
  main.show
else
  KDE::CmdLineArgs::usage
end

app.exec
